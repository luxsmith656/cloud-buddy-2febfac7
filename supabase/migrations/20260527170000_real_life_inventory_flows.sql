-- Real-life inventory flows: receiving, dispatch, activity history, and costing fields.

GRANT EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) TO authenticated;

ALTER TABLE public.ingredients
  ADD COLUMN IF NOT EXISTS unit_cost NUMERIC NOT NULL DEFAULT 0 CHECK (unit_cost >= 0);

ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS unit_price NUMERIC NOT NULL DEFAULT 0 CHECK (unit_price >= 0),
  ADD COLUMN IF NOT EXISTS estimated_unit_cost NUMERIC NOT NULL DEFAULT 0 CHECK (estimated_unit_cost >= 0);

CREATE TABLE IF NOT EXISTS public.ingredient_receipts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ingredient_id UUID NOT NULL REFERENCES public.ingredients(id) ON DELETE RESTRICT,
  supplier_id UUID REFERENCES public.suppliers(id) ON DELETE SET NULL,
  lot_number TEXT,
  invoice_number TEXT,
  quantity NUMERIC NOT NULL CHECK (quantity > 0),
  unit_cost NUMERIC CHECK (unit_cost IS NULL OR unit_cost >= 0),
  total_cost NUMERIC GENERATED ALWAYS AS (quantity * COALESCE(unit_cost, 0)) STORED,
  received_date DATE NOT NULL DEFAULT CURRENT_DATE,
  expiration_date DATE,
  notes TEXT,
  received_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.product_dispatches (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
  batch_id UUID REFERENCES public.batches(id) ON DELETE SET NULL,
  dispatch_type TEXT NOT NULL DEFAULT 'sale'
    CHECK (dispatch_type IN ('sale', 'delivery', 'transfer', 'sample', 'return', 'other')),
  destination TEXT,
  reference_number TEXT,
  quantity INTEGER NOT NULL CHECK (quantity > 0),
  unit_price NUMERIC CHECK (unit_price IS NULL OR unit_price >= 0),
  total_value NUMERIC GENERATED ALWAYS AS (quantity * COALESCE(unit_price, 0)) STORED,
  dispatched_date DATE NOT NULL DEFAULT CURRENT_DATE,
  notes TEXT,
  dispatched_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.inventory_activity (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  item_type public.movement_item_type NOT NULL,
  item_id UUID NOT NULL,
  item_name TEXT NOT NULL,
  activity_type TEXT NOT NULL,
  quantity NUMERIC,
  reference_table TEXT,
  reference_id UUID,
  details TEXT,
  user_id UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.ingredient_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_dispatches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_activity ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.ingredient_receipts TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.product_dispatches TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.inventory_activity TO authenticated;

DROP POLICY IF EXISTS "Authenticated users can read ingredient receipts" ON public.ingredient_receipts;
DROP POLICY IF EXISTS "Admins can manage ingredient receipts" ON public.ingredient_receipts;
DROP POLICY IF EXISTS "Authenticated users can read product dispatches" ON public.product_dispatches;
DROP POLICY IF EXISTS "Admins can manage product dispatches" ON public.product_dispatches;
DROP POLICY IF EXISTS "Authenticated users can read inventory activity" ON public.inventory_activity;
DROP POLICY IF EXISTS "Admins can manage inventory activity" ON public.inventory_activity;

CREATE POLICY "Authenticated users can read ingredient receipts"
ON public.ingredient_receipts FOR SELECT
TO authenticated
USING (true);

CREATE POLICY "Admins can manage ingredient receipts"
ON public.ingredient_receipts FOR ALL
TO authenticated
USING (public.has_role(auth.uid(), 'admin'))
WITH CHECK (public.has_role(auth.uid(), 'admin'));

CREATE POLICY "Authenticated users can read product dispatches"
ON public.product_dispatches FOR SELECT
TO authenticated
USING (true);

CREATE POLICY "Admins can manage product dispatches"
ON public.product_dispatches FOR ALL
TO authenticated
USING (public.has_role(auth.uid(), 'admin'))
WITH CHECK (public.has_role(auth.uid(), 'admin'));

CREATE POLICY "Authenticated users can read inventory activity"
ON public.inventory_activity FOR SELECT
TO authenticated
USING (true);

CREATE POLICY "Admins can manage inventory activity"
ON public.inventory_activity FOR ALL
TO authenticated
USING (public.has_role(auth.uid(), 'admin'))
WITH CHECK (public.has_role(auth.uid(), 'admin'));

CREATE INDEX IF NOT EXISTS idx_ingredient_receipts_ingredient_date
  ON public.ingredient_receipts (ingredient_id, received_date DESC);
CREATE INDEX IF NOT EXISTS idx_ingredient_receipts_supplier
  ON public.ingredient_receipts (supplier_id);
CREATE INDEX IF NOT EXISTS idx_product_dispatches_product_date
  ON public.product_dispatches (product_id, dispatched_date DESC);
CREATE INDEX IF NOT EXISTS idx_product_dispatches_batch
  ON public.product_dispatches (batch_id);
CREATE INDEX IF NOT EXISTS idx_inventory_activity_item
  ON public.inventory_activity (item_type, item_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_inventory_activity_created_at
  ON public.inventory_activity (created_at DESC);

CREATE OR REPLACE FUNCTION public.record_stock_movement_activity()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  activity_type_value text;
BEGIN
  IF NEW.remarks LIKE 'Received ingredient%' OR NEW.remarks LIKE 'Dispatched product%' THEN
    RETURN NEW;
  END IF;

  activity_type_value := CASE
    WHEN NEW.type = 'ADJUSTMENT' THEN 'ADJUSTMENT'
    WHEN NEW.remarks LIKE 'Used in batch%' OR NEW.remarks LIKE 'Batch produced%' THEN 'PRODUCTION'
    WHEN NEW.remarks LIKE 'Defect logged%' THEN 'DEFECT'
    WHEN NEW.type = 'IN' THEN 'STOCK_IN'
    WHEN NEW.type = 'OUT' THEN 'STOCK_OUT'
    ELSE 'STOCK_MOVEMENT'
  END;

  INSERT INTO public.inventory_activity (
    item_type,
    item_id,
    item_name,
    activity_type,
    quantity,
    reference_table,
    reference_id,
    details,
    user_id,
    created_at
  )
  VALUES (
    NEW.item_type,
    NEW.item_id,
    NEW.item_name,
    activity_type_value,
    NEW.quantity,
    'stock_movements',
    NEW.id,
    NEW.remarks,
    NEW.user_id,
    NEW.created_at
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS record_stock_movement_activity ON public.stock_movements;
CREATE TRIGGER record_stock_movement_activity
  AFTER INSERT ON public.stock_movements
  FOR EACH ROW EXECUTE FUNCTION public.record_stock_movement_activity();

CREATE OR REPLACE FUNCTION public.receive_ingredient(
  ingredient_id_value uuid,
  quantity_value numeric,
  supplier_id_value uuid DEFAULT NULL,
  unit_cost_value numeric DEFAULT NULL,
  lot_number_value text DEFAULT NULL,
  invoice_number_value text DEFAULT NULL,
  received_date_value date DEFAULT NULL,
  expiration_date_value date DEFAULT NULL,
  notes_value text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  ingredient_row public.ingredients%ROWTYPE;
  receipt_id_value uuid;
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin') THEN
    RAISE EXCEPTION 'Only admins can receive inventory';
  END IF;

  IF quantity_value IS NULL OR quantity_value <= 0 THEN
    RAISE EXCEPTION 'Quantity must be greater than zero';
  END IF;

  IF unit_cost_value IS NOT NULL AND unit_cost_value < 0 THEN
    RAISE EXCEPTION 'Unit cost cannot be negative';
  END IF;

  SELECT *
  INTO ingredient_row
  FROM public.ingredients
  WHERE id = ingredient_id_value
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ingredient not found';
  END IF;

  INSERT INTO public.ingredient_receipts (
    ingredient_id,
    supplier_id,
    lot_number,
    invoice_number,
    quantity,
    unit_cost,
    received_date,
    expiration_date,
    notes,
    received_by
  )
  VALUES (
    ingredient_id_value,
    COALESCE(supplier_id_value, ingredient_row.supplier_id),
    nullif(trim(lot_number_value), ''),
    nullif(trim(invoice_number_value), ''),
    quantity_value,
    unit_cost_value,
    COALESCE(received_date_value, CURRENT_DATE),
    expiration_date_value,
    nullif(trim(notes_value), ''),
    auth.uid()
  )
  RETURNING id INTO receipt_id_value;

  UPDATE public.ingredients
  SET current_stock = current_stock + quantity_value,
      unit_cost = COALESCE(unit_cost_value, unit_cost),
      expiration_date = COALESCE(expiration_date_value, expiration_date),
      updated_at = now()
  WHERE id = ingredient_id_value;

  INSERT INTO public.stock_movements (type, item_type, item_id, item_name, quantity, remarks, user_id)
  VALUES (
    'IN',
    'ingredient',
    ingredient_id_value,
    ingredient_row.name,
    quantity_value,
    'Received ingredient' ||
      CASE WHEN nullif(trim(invoice_number_value), '') IS NULL THEN '' ELSE ' / invoice ' || trim(invoice_number_value) END ||
      CASE WHEN nullif(trim(lot_number_value), '') IS NULL THEN '' ELSE ' / lot ' || trim(lot_number_value) END,
    auth.uid()
  );

  INSERT INTO public.inventory_activity (
    item_type,
    item_id,
    item_name,
    activity_type,
    quantity,
    reference_table,
    reference_id,
    details,
    user_id
  )
  VALUES (
    'ingredient',
    ingredient_id_value,
    ingredient_row.name,
    'RECEIPT',
    quantity_value,
    'ingredient_receipts',
    receipt_id_value,
    'Received ' || quantity_value || ' ' || ingredient_row.unit,
    auth.uid()
  );

  INSERT INTO public.audit_logs (user_id, action, module, details)
  VALUES (auth.uid(), 'RECEIVE', 'Ingredient Receiving', 'Received ' || quantity_value || ' ' || ingredient_row.unit || ' of ' || ingredient_row.name);

  RETURN receipt_id_value;
END;
$$;

CREATE OR REPLACE FUNCTION public.dispatch_product(
  product_id_value uuid,
  quantity_value integer,
  batch_id_value uuid DEFAULT NULL,
  dispatch_type_value text DEFAULT 'sale',
  destination_value text DEFAULT NULL,
  reference_number_value text DEFAULT NULL,
  unit_price_value numeric DEFAULT NULL,
  dispatched_date_value date DEFAULT NULL,
  notes_value text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  product_row public.products%ROWTYPE;
  batch_row public.batches%ROWTYPE;
  dispatch_id_value uuid;
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin') THEN
    RAISE EXCEPTION 'Only admins can dispatch products';
  END IF;

  IF quantity_value IS NULL OR quantity_value <= 0 THEN
    RAISE EXCEPTION 'Quantity must be greater than zero';
  END IF;

  IF dispatch_type_value NOT IN ('sale', 'delivery', 'transfer', 'sample', 'return', 'other') THEN
    RAISE EXCEPTION 'Invalid dispatch type';
  END IF;

  IF unit_price_value IS NOT NULL AND unit_price_value < 0 THEN
    RAISE EXCEPTION 'Unit price cannot be negative';
  END IF;

  SELECT *
  INTO product_row
  FROM public.products
  WHERE id = product_id_value
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Product not found';
  END IF;

  IF product_row.quantity < quantity_value THEN
    RAISE EXCEPTION 'Insufficient product stock';
  END IF;

  IF batch_id_value IS NOT NULL THEN
    SELECT *
    INTO batch_row
    FROM public.batches
    WHERE id = batch_id_value
      AND product_id = product_id_value
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Batch not found for this product';
    END IF;

    IF batch_row.quantity_produced < quantity_value THEN
      RAISE EXCEPTION 'Insufficient batch stock';
    END IF;

    UPDATE public.batches
    SET quantity_produced = quantity_produced - quantity_value,
        updated_at = now()
    WHERE id = batch_id_value;
  END IF;

  INSERT INTO public.product_dispatches (
    product_id,
    batch_id,
    dispatch_type,
    destination,
    reference_number,
    quantity,
    unit_price,
    dispatched_date,
    notes,
    dispatched_by
  )
  VALUES (
    product_id_value,
    batch_id_value,
    dispatch_type_value,
    nullif(trim(destination_value), ''),
    nullif(trim(reference_number_value), ''),
    quantity_value,
    unit_price_value,
    COALESCE(dispatched_date_value, CURRENT_DATE),
    nullif(trim(notes_value), ''),
    auth.uid()
  )
  RETURNING id INTO dispatch_id_value;

  UPDATE public.products
  SET quantity = quantity - quantity_value,
      unit_price = COALESCE(unit_price_value, unit_price),
      updated_at = now()
  WHERE id = product_id_value;

  INSERT INTO public.stock_movements (type, item_type, item_id, item_name, quantity, remarks, user_id)
  VALUES (
    'OUT',
    'product',
    product_id_value,
    product_row.name,
    -quantity_value,
    'Dispatched product' ||
      CASE WHEN nullif(trim(reference_number_value), '') IS NULL THEN '' ELSE ' / ref ' || trim(reference_number_value) END ||
      CASE WHEN nullif(trim(destination_value), '') IS NULL THEN '' ELSE ' / to ' || trim(destination_value) END,
    auth.uid()
  );

  INSERT INTO public.inventory_activity (
    item_type,
    item_id,
    item_name,
    activity_type,
    quantity,
    reference_table,
    reference_id,
    details,
    user_id
  )
  VALUES (
    'product',
    product_id_value,
    product_row.name,
    'DISPATCH',
    -quantity_value,
    'product_dispatches',
    dispatch_id_value,
    'Dispatched ' || quantity_value || ' units',
    auth.uid()
  );

  IF product_row.quantity - quantity_value <= product_row.min_stock THEN
    PERFORM public.create_inventory_alert(
      CASE WHEN product_row.quantity - quantity_value <= 0 THEN 'critical' ELSE 'low-stock' END,
      product_row.name || ' is at or below minimum stock after dispatch.',
      product_row.name,
      product_row.quantity - quantity_value <= 0
    );
  END IF;

  INSERT INTO public.audit_logs (user_id, action, module, details)
  VALUES (auth.uid(), 'DISPATCH', 'Product Dispatch', 'Dispatched ' || quantity_value || ' units of ' || product_row.name);

  RETURN dispatch_id_value;
END;
$$;

REVOKE ALL ON FUNCTION public.receive_ingredient(uuid, numeric, uuid, numeric, text, text, date, date, text) FROM public;
GRANT EXECUTE ON FUNCTION public.receive_ingredient(uuid, numeric, uuid, numeric, text, text, date, date, text) TO authenticated;

REVOKE ALL ON FUNCTION public.dispatch_product(uuid, integer, uuid, text, text, text, numeric, date, text) FROM public;
GRANT EXECUTE ON FUNCTION public.dispatch_product(uuid, integer, uuid, text, text, text, numeric, date, text) TO authenticated;
