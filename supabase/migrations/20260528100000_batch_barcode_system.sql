-- Batch barcode system: unique per-run batch codes, scanner lookup fields, and explicit expiration.

ALTER TABLE public.batches
  ADD COLUMN IF NOT EXISTS batch_code TEXT,
  ADD COLUMN IF NOT EXISTS barcode_token TEXT,
  ADD COLUMN IF NOT EXISTS barcode_value TEXT,
  ADD COLUMN IF NOT EXISTS manufactured_date DATE,
  ADD COLUMN IF NOT EXISTS price NUMERIC NOT NULL DEFAULT 0 CHECK (price >= 0);

UPDATE public.batches
SET manufactured_date = COALESCE(manufactured_date, production_date);

UPDATE public.batches b
SET batch_code = COALESCE(
      NULLIF(batch_code, ''),
      'CB-BTCH-' || to_char(COALESCE(b.production_date, CURRENT_DATE), 'YYYYMMDD') || '-' ||
      regexp_replace(upper(left(coalesce(p.name, 'ITEM'), 8)), '[^A-Z0-9]+', '', 'g') || '-' ||
      upper(substr(replace(b.id::text, '-', ''), 1, 6))
    ),
    barcode_token = COALESCE(
      NULLIF(barcode_token, ''),
      'CB-BTCH-' || to_char(COALESCE(b.production_date, CURRENT_DATE), 'YYYYMMDD') || '-' ||
      regexp_replace(upper(left(coalesce(p.name, 'ITEM'), 8)), '[^A-Z0-9]+', '', 'g') || '-' ||
      upper(substr(replace(b.id::text, '-', ''), 1, 6))
    ),
    barcode_value = COALESCE(
      NULLIF(barcode_value, ''),
      'CB-BTCH-' || to_char(COALESCE(b.production_date, CURRENT_DATE), 'YYYYMMDD') || '-' ||
      regexp_replace(upper(left(coalesce(p.name, 'ITEM'), 8)), '[^A-Z0-9]+', '', 'g') || '-' ||
      upper(substr(replace(b.id::text, '-', ''), 1, 6))
    ),
    price = COALESCE(NULLIF(b.price, 0), p.unit_price, 0)
FROM public.products p
WHERE p.id = b.product_id;

ALTER TABLE public.batches
  ALTER COLUMN batch_code SET NOT NULL,
  ALTER COLUMN barcode_token SET NOT NULL,
  ALTER COLUMN barcode_value SET NOT NULL,
  ALTER COLUMN manufactured_date SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_batches_batch_code_unique ON public.batches (batch_code);
CREATE UNIQUE INDEX IF NOT EXISTS idx_batches_barcode_token_unique ON public.batches (barcode_token);
CREATE UNIQUE INDEX IF NOT EXISTS idx_batches_barcode_value_unique ON public.batches (barcode_value);
CREATE INDEX IF NOT EXISTS idx_batches_batch_code_search ON public.batches USING btree (batch_code text_pattern_ops);
CREATE INDEX IF NOT EXISTS idx_stock_movements_item_date ON public.stock_movements (item_type, item_id, created_at DESC);

ALTER TABLE public.stock_movements
  ADD COLUMN IF NOT EXISTS batch_id UUID REFERENCES public.batches(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS batch_code TEXT;

CREATE OR REPLACE FUNCTION public.normalize_batch_token(value text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT upper(regexp_replace(coalesce(trim(value), ''), '\s+', '', 'g'));
$$;

CREATE OR REPLACE FUNCTION public.product_code(value text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT left(coalesce(nullif(regexp_replace(upper(coalesce(value, 'ITEM')), '[^A-Z0-9]+', '', 'g'), ''), 'ITEM'), 10);
$$;

CREATE OR REPLACE FUNCTION public.generate_batch_token(product_name_value text, production_date_value date)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  candidate text;
BEGIN
  LOOP
    candidate := 'CB-BTCH-' ||
      to_char(COALESCE(production_date_value, CURRENT_DATE), 'YYYYMMDD') || '-' ||
      public.product_code(product_name_value) || '-' ||
      upper(substr(encode(gen_random_bytes(4), 'hex'), 1, 8));

    EXIT WHEN NOT EXISTS (
      SELECT 1 FROM public.batches
      WHERE batch_code = candidate OR barcode_token = candidate OR barcode_value = candidate
    );
  END LOOP;

  RETURN candidate;
END;
$$;

CREATE OR REPLACE FUNCTION public.produce_batch(
  product_id_value uuid,
  quantity_value integer,
  expiration_date_value date,
  batch_code_value text DEFAULT NULL,
  production_date_value date DEFAULT CURRENT_DATE
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  product_row public.products%ROWTYPE;
  recipe_id_value uuid;
  batch_id_value uuid;
  batch_code_normalized text;
  ingredient_row record;
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin') THEN
    RAISE EXCEPTION 'Only admins can produce batches';
  END IF;

  IF quantity_value IS NULL OR quantity_value <= 0 THEN
    RAISE EXCEPTION 'Quantity must be greater than zero';
  END IF;

  IF expiration_date_value IS NULL THEN
    RAISE EXCEPTION 'Expiration date is required';
  END IF;

  IF expiration_date_value <= COALESCE(production_date_value, CURRENT_DATE) THEN
    RAISE EXCEPTION 'Expiration date must be after production date';
  END IF;

  SELECT *
  INTO product_row
  FROM public.products
  WHERE id = product_id_value
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Product not found';
  END IF;

  batch_code_normalized := public.normalize_batch_token(batch_code_value);
  IF batch_code_normalized = '' THEN
    batch_code_normalized := public.generate_batch_token(product_row.name, COALESCE(production_date_value, CURRENT_DATE));
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.batches
    WHERE batch_code = batch_code_normalized
       OR barcode_token = batch_code_normalized
       OR barcode_value = batch_code_normalized
  ) THEN
    RAISE EXCEPTION 'Batch barcode already exists';
  END IF;

  SELECT id
  INTO recipe_id_value
  FROM public.recipes
  WHERE product_id = product_id_value
  ORDER BY created_at DESC
  LIMIT 1;

  IF recipe_id_value IS NULL THEN
    RAISE EXCEPTION 'No recipe found for this product';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.recipe_ingredients WHERE recipe_id = recipe_id_value) THEN
    RAISE EXCEPTION 'Recipe has no ingredients';
  END IF;

  FOR ingredient_row IN
    SELECT
      ri.ingredient_id,
      ri.quantity * quantity_value AS required_quantity,
      i.name,
      i.current_stock,
      i.min_stock,
      i.unit
    FROM public.recipe_ingredients ri
    JOIN public.ingredients i ON i.id = ri.ingredient_id
    WHERE ri.recipe_id = recipe_id_value
    ORDER BY i.id
    FOR UPDATE OF i
  LOOP
    IF ingredient_row.current_stock < ingredient_row.required_quantity THEN
      RAISE EXCEPTION 'Insufficient stock for %: need %, have %',
        ingredient_row.name,
        ingredient_row.required_quantity,
        ingredient_row.current_stock;
    END IF;
  END LOOP;

  INSERT INTO public.batches (
    product_id,
    batch_code,
    barcode_token,
    barcode_value,
    quantity_planned,
    quantity_produced,
    production_date,
    manufactured_date,
    expiration_date,
    price,
    status,
    created_by
  )
  VALUES (
    product_id_value,
    batch_code_normalized,
    batch_code_normalized,
    batch_code_normalized,
    quantity_value,
    quantity_value,
    COALESCE(production_date_value, CURRENT_DATE),
    COALESCE(production_date_value, CURRENT_DATE),
    expiration_date_value,
    COALESCE(product_row.unit_price, 0),
    'completed',
    auth.uid()
  )
  RETURNING id INTO batch_id_value;

  FOR ingredient_row IN
    SELECT
      ri.ingredient_id,
      ri.quantity * quantity_value AS required_quantity,
      i.name,
      i.current_stock,
      i.min_stock,
      i.unit
    FROM public.recipe_ingredients ri
    JOIN public.ingredients i ON i.id = ri.ingredient_id
    WHERE ri.recipe_id = recipe_id_value
    ORDER BY i.id
  LOOP
    UPDATE public.ingredients
    SET current_stock = current_stock - ingredient_row.required_quantity
    WHERE id = ingredient_row.ingredient_id;

    INSERT INTO public.stock_movements (
      type,
      item_type,
      item_id,
      item_name,
      quantity,
      remarks,
      user_id,
      batch_id,
      batch_code
    )
    VALUES (
      'OUT',
      'ingredient',
      ingredient_row.ingredient_id,
      ingredient_row.name,
      -ingredient_row.required_quantity,
      'Used in batch ' || batch_code_normalized || ' for ' || product_row.name,
      auth.uid(),
      batch_id_value,
      batch_code_normalized
    );

    IF (ingredient_row.current_stock - ingredient_row.required_quantity) <= ingredient_row.min_stock THEN
      PERFORM public.create_inventory_alert(
        'low-stock',
        ingredient_row.name || ' is at or below minimum stock.',
        ingredient_row.name,
        (ingredient_row.current_stock - ingredient_row.required_quantity) <= 0
      );
    END IF;
  END LOOP;

  UPDATE public.products
  SET quantity = quantity + quantity_value,
      expiration_date = expiration_date_value
  WHERE id = product_id_value;

  INSERT INTO public.stock_movements (
    type,
    item_type,
    item_id,
    item_name,
    quantity,
    remarks,
    user_id,
    batch_id,
    batch_code
  )
  VALUES (
    'IN',
    'product',
    product_id_value,
    product_row.name,
    quantity_value,
    'Batch production completed: ' || batch_code_normalized,
    auth.uid(),
    batch_id_value,
    batch_code_normalized
  );

  INSERT INTO public.audit_logs (user_id, action, module, details)
  VALUES (auth.uid(), 'PRODUCE', 'Batch Production', 'Produced batch ' || batch_code_normalized || ' for ' || product_row.name || ': ' || quantity_value);

  RETURN batch_id_value;
END;
$$;

REVOKE ALL ON FUNCTION public.produce_batch(uuid, integer, date, text, date) FROM public;
GRANT EXECUTE ON FUNCTION public.produce_batch(uuid, integer, date, text, date) TO authenticated;

CREATE OR REPLACE FUNCTION public.find_batch_by_barcode(barcode_value_value text)
RETURNS TABLE (
  batch_id uuid,
  batch_code text,
  barcode_token text,
  product_id uuid,
  product_name text,
  category text,
  variant text,
  manufactured_date date,
  expiration_date date,
  shelf_life integer,
  price numeric,
  quantity_produced integer,
  remaining_quantity integer,
  status public.batch_status,
  defect_quantity integer
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    b.id,
    b.batch_code,
    b.barcode_token,
    p.id,
    p.name,
    p.category,
    p.variant,
    b.manufactured_date,
    b.expiration_date,
    p.shelf_life,
    b.price,
    b.quantity_planned,
    b.quantity_produced,
    b.status,
    COALESCE(SUM(d.quantity), 0)::integer
  FROM public.batches b
  JOIN public.products p ON p.id = b.product_id
  LEFT JOIN public.defects d ON d.batch_id = b.id
  WHERE b.batch_code = public.normalize_batch_token(barcode_value_value)
     OR b.barcode_token = public.normalize_batch_token(barcode_value_value)
     OR b.barcode_value = public.normalize_batch_token(barcode_value_value)
  GROUP BY b.id, p.id;
$$;

GRANT EXECUTE ON FUNCTION public.find_batch_by_barcode(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.log_defect(
  batch_id_value uuid,
  quantity_value integer,
  reason_value text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  batch_row public.batches%ROWTYPE;
  product_row public.products%ROWTYPE;
  defect_id_value uuid;
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin') THEN
    RAISE EXCEPTION 'Only admins can log defects';
  END IF;

  IF quantity_value IS NULL OR quantity_value <= 0 THEN
    RAISE EXCEPTION 'Quantity must be greater than zero';
  END IF;

  SELECT *
  INTO batch_row
  FROM public.batches
  WHERE id = batch_id_value
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Batch not found';
  END IF;

  IF quantity_value > batch_row.quantity_produced THEN
    RAISE EXCEPTION 'Defect quantity cannot exceed remaining batch quantity';
  END IF;

  SELECT *
  INTO product_row
  FROM public.products
  WHERE id = batch_row.product_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Product not found';
  END IF;

  IF quantity_value > product_row.quantity THEN
    RAISE EXCEPTION 'Defect quantity cannot exceed product stock';
  END IF;

  INSERT INTO public.defects (batch_id, quantity, reason)
  VALUES (batch_id_value, quantity_value, nullif(trim(reason_value), ''))
  RETURNING id INTO defect_id_value;

  UPDATE public.batches
  SET quantity_produced = quantity_produced - quantity_value,
      updated_at = now()
  WHERE id = batch_id_value;

  UPDATE public.products
  SET quantity = quantity - quantity_value,
      updated_at = now()
  WHERE id = product_row.id;

  INSERT INTO public.stock_movements (
    type,
    item_type,
    item_id,
    item_name,
    quantity,
    remarks,
    user_id,
    batch_id,
    batch_code
  )
  VALUES (
    'OUT',
    'product',
    product_row.id,
    product_row.name,
    -quantity_value,
    'Defect logged for batch ' || batch_row.batch_code || ': ' || coalesce(nullif(trim(reason_value), ''), 'No reason'),
    auth.uid(),
    batch_id_value,
    batch_row.batch_code
  );

  IF product_row.quantity - quantity_value <= product_row.min_stock THEN
    PERFORM public.create_inventory_alert(
      CASE WHEN product_row.quantity - quantity_value <= 0 THEN 'critical' ELSE 'low-stock' END,
      product_row.name || ' is at or below minimum stock.',
      product_row.name,
      product_row.quantity - quantity_value <= 0
    );
  END IF;

  INSERT INTO public.audit_logs (user_id, action, module, details)
  VALUES (auth.uid(), 'DEFECT', 'Defects', 'Logged ' || quantity_value || ' defective units for batch ' || batch_row.batch_code);

  RETURN defect_id_value;
END;
$$;

REVOKE ALL ON FUNCTION public.log_defect(uuid, integer, text) FROM public;
GRANT EXECUTE ON FUNCTION public.log_defect(uuid, integer, text) TO authenticated;

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
  movement_batch_code text;
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

    movement_batch_code := batch_row.batch_code;
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

  INSERT INTO public.stock_movements (type, item_type, item_id, item_name, quantity, remarks, user_id, batch_id, batch_code)
  VALUES (
    'OUT',
    'product',
    product_id_value,
    product_row.name,
    -quantity_value,
    'Dispatched product' ||
      CASE WHEN movement_batch_code IS NULL THEN '' ELSE ' / batch ' || movement_batch_code END ||
      CASE WHEN nullif(trim(reference_number_value), '') IS NULL THEN '' ELSE ' / ref ' || trim(reference_number_value) END ||
      CASE WHEN nullif(trim(destination_value), '') IS NULL THEN '' ELSE ' / to ' || trim(destination_value) END,
    auth.uid(),
    batch_id_value,
    movement_batch_code
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
    'Dispatched ' || quantity_value || ' units' ||
      CASE WHEN movement_batch_code IS NULL THEN '' ELSE ' from batch ' || movement_batch_code END,
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
  VALUES (auth.uid(), 'DISPATCH', 'Product Dispatch', 'Dispatched ' || quantity_value || ' units of ' || product_row.name ||
    CASE WHEN movement_batch_code IS NULL THEN '' ELSE ' from batch ' || movement_batch_code END);

  RETURN dispatch_id_value;
END;
$$;

REVOKE ALL ON FUNCTION public.dispatch_product(uuid, integer, uuid, text, text, text, numeric, date, text) FROM public;
GRANT EXECUTE ON FUNCTION public.dispatch_product(uuid, integer, uuid, text, text, text, numeric, date, text) TO authenticated;

UPDATE public.products
SET shelf_life = CASE
  WHEN name ILIKE '%banana ketchup%' THEN 210
  WHEN name ILIKE '%sweet sauce%' THEN 210
  WHEN name ILIKE '%soy sauce%' THEN 240
  WHEN name ILIKE '%vinegar%' THEN 240
  WHEN name ILIKE '%fish sauce%' THEN 240
  ELSE shelf_life
END;
