
-- 1. has_role execute grants (idempotent)
GRANT EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) TO authenticated;
GRANT EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) TO anon;

-- 2. stock_movements append-only
DROP TRIGGER IF EXISTS prevent_stock_movements_update ON public.stock_movements;
DROP TRIGGER IF EXISTS prevent_stock_movements_delete ON public.stock_movements;

CREATE OR REPLACE FUNCTION public.prevent_stock_movement_changes()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'Stock movements are append-only'; END;
$$;

CREATE TRIGGER prevent_stock_movements_update
BEFORE UPDATE ON public.stock_movements
FOR EACH ROW EXECUTE FUNCTION public.prevent_stock_movement_changes();

CREATE TRIGGER prevent_stock_movements_delete
BEFORE DELETE ON public.stock_movements
FOR EACH ROW EXECUTE FUNCTION public.prevent_stock_movement_changes();

-- 3. audit_logs append-only (ensure triggers exist)
DROP TRIGGER IF EXISTS prevent_audit_logs_update ON public.audit_logs;
DROP TRIGGER IF EXISTS prevent_audit_logs_delete ON public.audit_logs;

CREATE TRIGGER prevent_audit_logs_update
BEFORE UPDATE ON public.audit_logs
FOR EACH ROW EXECUTE FUNCTION public.prevent_audit_log_changes();

CREATE TRIGGER prevent_audit_logs_delete
BEFORE DELETE ON public.audit_logs
FOR EACH ROW EXECUTE FUNCTION public.prevent_audit_log_changes();

-- 4. Force role mutations through set_user_role RPC
DROP POLICY IF EXISTS "Admins can manage roles" ON public.user_roles;

-- Read-only view of roles for users (existing "Users can view own roles" stays)
-- Admins can still read everyone:
CREATE POLICY "Admins can view all roles"
ON public.user_roles FOR SELECT
TO authenticated
USING (public.has_role(auth.uid(), 'admin'));

-- No INSERT/UPDATE/DELETE policy => blocked for normal clients.
-- set_user_role is SECURITY DEFINER and handles writes + audit logging.

GRANT EXECUTE ON FUNCTION public.set_user_role(uuid, public.app_role, boolean) TO authenticated;

-- 5. save_recipe RPC: atomic create/update of recipe + ingredients
CREATE OR REPLACE FUNCTION public.save_recipe(
  recipe_id_value uuid,
  product_id_value uuid,
  name_value text,
  image_url_value text,
  ingredients_value jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result_id uuid;
  ing jsonb;
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin') THEN
    RAISE EXCEPTION 'Only admins can manage recipes';
  END IF;
  IF product_id_value IS NULL THEN
    RAISE EXCEPTION 'Product is required';
  END IF;
  IF ingredients_value IS NULL OR jsonb_array_length(ingredients_value) = 0 THEN
    RAISE EXCEPTION 'At least one ingredient is required';
  END IF;

  IF recipe_id_value IS NULL THEN
    INSERT INTO public.recipes (product_id, name, image_url)
    VALUES (product_id_value, nullif(trim(name_value), ''), nullif(image_url_value, ''))
    RETURNING id INTO result_id;
  ELSE
    UPDATE public.recipes
    SET product_id = product_id_value,
        name = nullif(trim(name_value), ''),
        image_url = nullif(image_url_value, ''),
        updated_at = now()
    WHERE id = recipe_id_value
    RETURNING id INTO result_id;
    IF result_id IS NULL THEN RAISE EXCEPTION 'Recipe not found'; END IF;
    DELETE FROM public.recipe_ingredients WHERE recipe_id = result_id;
  END IF;

  FOR ing IN SELECT * FROM jsonb_array_elements(ingredients_value)
  LOOP
    IF (ing->>'ingredient_id') IS NULL OR (ing->>'quantity')::numeric <= 0 THEN
      RAISE EXCEPTION 'Each ingredient needs an id and positive quantity';
    END IF;
    INSERT INTO public.recipe_ingredients (recipe_id, ingredient_id, quantity)
    VALUES (result_id, (ing->>'ingredient_id')::uuid, (ing->>'quantity')::numeric);
  END LOOP;

  INSERT INTO public.audit_logs (user_id, action, module, details)
  VALUES (
    auth.uid(),
    CASE WHEN recipe_id_value IS NULL THEN 'CREATE' ELSE 'UPDATE' END,
    'Recipes',
    'Saved recipe ' || coalesce(nullif(trim(name_value), ''), '(unnamed)')
  );

  RETURN result_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.save_recipe(uuid, uuid, text, text, jsonb) TO authenticated;
