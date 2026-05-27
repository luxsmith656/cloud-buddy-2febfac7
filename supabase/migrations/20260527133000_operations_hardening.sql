-- Operational hardening for role management, adjustment approvals, barcodes, audit safety, and alert refreshes.

ALTER TABLE public.products ADD COLUMN IF NOT EXISTS barcode TEXT;
ALTER TABLE public.ingredients ADD COLUMN IF NOT EXISTS barcode TEXT;

DROP POLICY IF EXISTS "Admins can view profiles" ON public.profiles;
CREATE POLICY "Admins can view profiles"
ON public.profiles FOR SELECT
TO authenticated
USING (public.has_role(auth.uid(), 'admin'));

CREATE UNIQUE INDEX IF NOT EXISTS idx_products_barcode_unique
  ON public.products (barcode)
  WHERE barcode IS NOT NULL AND barcode <> '';

CREATE UNIQUE INDEX IF NOT EXISTS idx_ingredients_barcode_unique
  ON public.ingredients (barcode)
  WHERE barcode IS NOT NULL AND barcode <> '';

CREATE TYPE public.adjustment_status AS ENUM ('pending', 'approved', 'rejected');

CREATE TABLE IF NOT EXISTS public.inventory_adjustment_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  item_type public.movement_item_type NOT NULL,
  item_id UUID NOT NULL,
  item_name TEXT NOT NULL,
  quantity NUMERIC NOT NULL,
  reason TEXT NOT NULL,
  status public.adjustment_status NOT NULL DEFAULT 'pending',
  requested_by UUID REFERENCES auth.users(id),
  reviewed_by UUID REFERENCES auth.users(id),
  reviewed_at TIMESTAMPTZ,
  review_note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT inventory_adjustment_requests_quantity_nonzero CHECK (quantity <> 0)
);

ALTER TABLE public.inventory_adjustment_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated users can read adjustment requests" ON public.inventory_adjustment_requests;
DROP POLICY IF EXISTS "Users can create adjustment requests" ON public.inventory_adjustment_requests;
DROP POLICY IF EXISTS "Admins can review adjustment requests" ON public.inventory_adjustment_requests;

CREATE POLICY "Authenticated users can read adjustment requests"
ON public.inventory_adjustment_requests FOR SELECT
TO authenticated
USING (true);

CREATE POLICY "Users can create adjustment requests"
ON public.inventory_adjustment_requests FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = requested_by);

CREATE POLICY "Admins can review adjustment requests"
ON public.inventory_adjustment_requests FOR UPDATE
TO authenticated
USING (public.has_role(auth.uid(), 'admin'))
WITH CHECK (public.has_role(auth.uid(), 'admin'));

CREATE INDEX IF NOT EXISTS idx_inventory_adjustment_requests_status
  ON public.inventory_adjustment_requests (status, created_at DESC);

CREATE TRIGGER update_inventory_adjustment_requests_updated_at
  BEFORE UPDATE ON public.inventory_adjustment_requests
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE OR REPLACE FUNCTION public.request_inventory_adjustment(
  item_type_value public.movement_item_type,
  item_id_value uuid,
  quantity_value numeric,
  reason_value text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  item_name_value text;
  request_id_value uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF quantity_value IS NULL OR quantity_value = 0 THEN
    RAISE EXCEPTION 'Quantity must not be zero';
  END IF;

  IF nullif(trim(reason_value), '') IS NULL THEN
    RAISE EXCEPTION 'Reason is required';
  END IF;

  IF item_type_value = 'ingredient' THEN
    SELECT name INTO item_name_value FROM public.ingredients WHERE id = item_id_value;
  ELSE
    SELECT name INTO item_name_value FROM public.products WHERE id = item_id_value;
  END IF;

  IF item_name_value IS NULL THEN
    RAISE EXCEPTION 'Inventory item not found';
  END IF;

  INSERT INTO public.inventory_adjustment_requests (
    item_type,
    item_id,
    item_name,
    quantity,
    reason,
    requested_by
  )
  VALUES (
    item_type_value,
    item_id_value,
    item_name_value,
    quantity_value,
    trim(reason_value),
    auth.uid()
  )
  RETURNING id INTO request_id_value;

  INSERT INTO public.audit_logs (user_id, action, module, details)
  VALUES (auth.uid(), 'REQUEST', 'Inventory Adjustments', 'Requested adjustment for ' || item_name_value || ': ' || quantity_value);

  RETURN request_id_value;
END;
$$;

CREATE OR REPLACE FUNCTION public.review_inventory_adjustment(
  request_id_value uuid,
  approve_value boolean,
  review_note_value text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  request_row public.inventory_adjustment_requests%ROWTYPE;
  resulting_stock numeric;
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin') THEN
    RAISE EXCEPTION 'Only admins can review adjustment requests';
  END IF;

  SELECT *
  INTO request_row
  FROM public.inventory_adjustment_requests
  WHERE id = request_id_value
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Adjustment request not found';
  END IF;

  IF request_row.status <> 'pending' THEN
    RAISE EXCEPTION 'Adjustment request has already been reviewed';
  END IF;

  IF NOT approve_value THEN
    UPDATE public.inventory_adjustment_requests
    SET status = 'rejected',
        reviewed_by = auth.uid(),
        reviewed_at = now(),
        review_note = nullif(trim(review_note_value), '')
    WHERE id = request_id_value;

    INSERT INTO public.audit_logs (user_id, action, module, details)
    VALUES (auth.uid(), 'REJECT', 'Inventory Adjustments', 'Rejected adjustment for ' || request_row.item_name);
    RETURN;
  END IF;

  IF request_row.item_type = 'ingredient' THEN
    UPDATE public.ingredients
    SET current_stock = current_stock + request_row.quantity
    WHERE id = request_row.item_id
      AND current_stock + request_row.quantity >= 0
    RETURNING current_stock INTO resulting_stock;
  ELSE
    UPDATE public.products
    SET quantity = quantity + request_row.quantity::integer
    WHERE id = request_row.item_id
      AND quantity + request_row.quantity::integer >= 0
    RETURNING quantity INTO resulting_stock;
  END IF;

  IF resulting_stock IS NULL THEN
    RAISE EXCEPTION 'Adjustment would make stock negative';
  END IF;

  INSERT INTO public.stock_movements (
    type,
    item_type,
    item_id,
    item_name,
    quantity,
    remarks,
    user_id
  )
  VALUES (
    'ADJUSTMENT',
    request_row.item_type,
    request_row.item_id,
    request_row.item_name,
    request_row.quantity,
    'Approved adjustment: ' || request_row.reason,
    auth.uid()
  );

  UPDATE public.inventory_adjustment_requests
  SET status = 'approved',
      reviewed_by = auth.uid(),
      reviewed_at = now(),
      review_note = nullif(trim(review_note_value), '')
  WHERE id = request_id_value;

  INSERT INTO public.audit_logs (user_id, action, module, details)
  VALUES (auth.uid(), 'APPROVE', 'Inventory Adjustments', 'Approved adjustment for ' || request_row.item_name || ': ' || request_row.quantity);
END;
$$;

REVOKE ALL ON FUNCTION public.request_inventory_adjustment(public.movement_item_type, uuid, numeric, text) FROM public;
GRANT EXECUTE ON FUNCTION public.request_inventory_adjustment(public.movement_item_type, uuid, numeric, text) TO authenticated;

REVOKE ALL ON FUNCTION public.review_inventory_adjustment(uuid, boolean, text) FROM public;
GRANT EXECUTE ON FUNCTION public.review_inventory_adjustment(uuid, boolean, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.prevent_audit_log_changes()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION 'Audit logs are immutable';
END;
$$;

DROP TRIGGER IF EXISTS prevent_audit_log_update ON public.audit_logs;
CREATE TRIGGER prevent_audit_log_update
  BEFORE UPDATE OR DELETE ON public.audit_logs
  FOR EACH ROW EXECUTE FUNCTION public.prevent_audit_log_changes();

CREATE OR REPLACE FUNCTION public.set_user_role(
  target_user_id uuid,
  role_value public.app_role,
  enabled_value boolean
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin') THEN
    RAISE EXCEPTION 'Only admins can manage roles';
  END IF;

  IF target_user_id = auth.uid() AND role_value = 'admin' AND NOT enabled_value THEN
    RAISE EXCEPTION 'Admins cannot remove their own admin role';
  END IF;

  IF enabled_value THEN
    INSERT INTO public.user_roles (user_id, role)
    VALUES (target_user_id, role_value)
    ON CONFLICT DO NOTHING;
  ELSE
    DELETE FROM public.user_roles
    WHERE user_id = target_user_id AND role = role_value;
  END IF;

  INSERT INTO public.audit_logs (user_id, action, module, details)
  VALUES (
    auth.uid(),
    CASE WHEN enabled_value THEN 'GRANT_ROLE' ELSE 'REVOKE_ROLE' END,
    'Role Management',
    role_value || ' role ' || CASE WHEN enabled_value THEN 'granted to ' ELSE 'revoked from ' END || target_user_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.set_user_role(uuid, public.app_role, boolean) FROM public;
GRANT EXECUTE ON FUNCTION public.set_user_role(uuid, public.app_role, boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.refresh_inventory_alerts()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  product_row record;
  ingredient_row record;
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin') THEN
    RAISE EXCEPTION 'Only admins can refresh inventory alerts';
  END IF;

  FOR product_row IN
    SELECT name, quantity, min_stock, expiration_date
    FROM public.products
  LOOP
    IF product_row.quantity <= product_row.min_stock THEN
      PERFORM public.create_inventory_alert(
        CASE WHEN product_row.quantity <= 0 THEN 'critical' ELSE 'low-stock' END,
        product_row.name || ' is at or below minimum stock.',
        product_row.name,
        product_row.quantity <= 0
      );
    END IF;

    IF product_row.expiration_date IS NOT NULL AND product_row.expiration_date <= CURRENT_DATE + 7 THEN
      PERFORM public.create_inventory_alert(
        'expiring',
        product_row.name || ' expires on ' || product_row.expiration_date || '.',
        product_row.name,
        product_row.expiration_date <= CURRENT_DATE
      );
    END IF;
  END LOOP;

  FOR ingredient_row IN
    SELECT name, current_stock, min_stock, expiration_date
    FROM public.ingredients
  LOOP
    IF ingredient_row.current_stock <= ingredient_row.min_stock THEN
      PERFORM public.create_inventory_alert(
        CASE WHEN ingredient_row.current_stock <= 0 THEN 'critical' ELSE 'low-stock' END,
        ingredient_row.name || ' is at or below minimum stock.',
        ingredient_row.name,
        ingredient_row.current_stock <= 0
      );
    END IF;

    IF ingredient_row.expiration_date IS NOT NULL AND ingredient_row.expiration_date <= CURRENT_DATE + 7 THEN
      PERFORM public.create_inventory_alert(
        'expiring',
        ingredient_row.name || ' expires on ' || ingredient_row.expiration_date || '.',
        ingredient_row.name,
        ingredient_row.expiration_date <= CURRENT_DATE
      );
    END IF;
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.refresh_inventory_alerts() FROM public;
GRANT EXECUTE ON FUNCTION public.refresh_inventory_alerts() TO authenticated;
