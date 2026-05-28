-- Label-informed seed data. Quantities are demo placeholders; ingredient names come from readable labels.

INSERT INTO public.products (name, category, variant, shelf_life, quantity, min_stock, unit_price, estimated_unit_cost)
SELECT name, category, variant, shelf_life, quantity, min_stock, unit_price, estimated_unit_cost
FROM (VALUES
  ('Banana Ketchup', 'Condiments', 'Bottle', 210, 0, 10, 0, 0),
  ('Sweet Sauce', 'Condiments', 'Bottle', 210, 0, 10, 0, 0),
  ('Soy Sauce', 'Condiments', 'Bottle', 240, 0, 10, 0, 0),
  ('Vinegar', 'Condiments', 'Bottle', 240, 0, 10, 0, 0),
  ('Fish Sauce', 'Condiments', 'Bottle', 240, 0, 10, 0, 0),
  ('Tomato Sauce', 'Condiments - estimated placeholder', 'Bottle', 210, 0, 10, 0, 0),
  ('Spaghetti Sauce', 'Condiments - estimated placeholder', 'Bottle', 210, 0, 10, 0, 0),
  ('Hot Sauce', 'Condiments - estimated placeholder', 'Bottle', 210, 0, 10, 0, 0),
  ('Oyster Sauce', 'Condiments - estimated placeholder', 'Bottle', 240, 0, 10, 0, 0)
) AS seed(name, category, variant, shelf_life, quantity, min_stock, unit_price, estimated_unit_cost)
WHERE NOT EXISTS (
  SELECT 1 FROM public.products p WHERE lower(p.name) = lower(seed.name)
);

UPDATE public.products
SET shelf_life = CASE
  WHEN name ILIKE '%banana ketchup%' THEN 210
  WHEN name ILIKE '%sweet sauce%' THEN 210
  WHEN name ILIKE '%soy sauce%' THEN 240
  WHEN name ILIKE '%vinegar%' THEN 240
  WHEN name ILIKE '%fish sauce%' THEN 240
  ELSE shelf_life
END;

INSERT INTO public.ingredients (name, unit, current_stock, min_stock, expiration_date)
SELECT name, unit, current_stock, min_stock, NULL
FROM (VALUES
  ('Water', 'liters', 0, 20),
  ('Fish Extract', 'liters', 0, 10),
  ('Iodized Salt', 'kg', 0, 10),
  ('Sodium Benzoate', 'kg', 0, 2),
  ('Sodium Metabisulfite', 'kg', 0, 2),
  ('Flavor Enhancer', 'kg', 0, 2),
  ('Caramel Color', 'liters', 0, 2),
  ('Caramel as Color', 'liters', 0, 2),
  ('Caramel as Colorant', 'liters', 0, 2),
  ('Hydrolyzed Soybean Protein', 'kg', 0, 10),
  ('Citric Acid as Acidulant', 'kg', 0, 2),
  ('Cane Vinegar', 'liters', 0, 20),
  ('Sugar', 'kg', 0, 20),
  ('Spices', 'kg', 0, 5),
  ('Modified Starch', 'kg', 0, 5),
  ('Garlic', 'kg', 0, 5),
  ('Acidulant', 'kg', 0, 2),
  ('Artificial Food Colors with Tartrazine', 'kg', 0, 1),
  ('Banana', 'kg', 0, 20),
  ('Onion', 'kg', 0, 5),
  ('Vinegar', 'liters', 0, 10),
  ('FD&C Red No. 40', 'kg', 0, 1),
  ('FD&C Yellow No. 5', 'kg', 0, 1),
  ('Tomato Base - estimated placeholder', 'kg', 0, 10),
  ('Oyster Extract - estimated placeholder', 'liters', 0, 5),
  ('Chili Pepper - estimated placeholder', 'kg', 0, 5)
) AS seed(name, unit, current_stock, min_stock)
WHERE NOT EXISTS (
  SELECT 1 FROM public.ingredients i WHERE lower(i.name) = lower(seed.name)
);

INSERT INTO public.recipes (product_id, name)
SELECT p.id, p.name || ' label ingredients - demo quantities editable'
FROM public.products p
WHERE p.name IN ('Fish Sauce', 'Soy Sauce', 'Vinegar', 'Sweet Sauce', 'Banana Ketchup', 'Tomato Sauce', 'Spaghetti Sauce', 'Hot Sauce', 'Oyster Sauce')
  AND NOT EXISTS (SELECT 1 FROM public.recipes r WHERE r.product_id = p.id);

INSERT INTO public.recipe_ingredients (recipe_id, ingredient_id, quantity)
SELECT r.id, i.id, seed.quantity
FROM (VALUES
  ('Fish Sauce', 'Water', 0.6), ('Fish Sauce', 'Fish Extract', 0.25), ('Fish Sauce', 'Iodized Salt', 0.08), ('Fish Sauce', 'Sodium Benzoate', 0.002), ('Fish Sauce', 'Sodium Metabisulfite', 0.001), ('Fish Sauce', 'Flavor Enhancer', 0.002), ('Fish Sauce', 'Caramel Color', 0.002),
  ('Soy Sauce', 'Iodized Salt', 0.08), ('Soy Sauce', 'Water', 0.55), ('Soy Sauce', 'Hydrolyzed Soybean Protein', 0.25), ('Soy Sauce', 'Caramel as Color', 0.002), ('Soy Sauce', 'Citric Acid as Acidulant', 0.001), ('Soy Sauce', 'Sodium Benzoate', 0.002),
  ('Vinegar', 'Water', 0.55), ('Vinegar', 'Cane Vinegar', 0.45), ('Vinegar', 'Caramel as Colorant', 0.001),
  ('Sweet Sauce', 'Sugar', 0.25), ('Sweet Sauce', 'Water', 0.45), ('Sweet Sauce', 'Spices', 0.02), ('Sweet Sauce', 'Modified Starch', 0.04), ('Sweet Sauce', 'Iodized Salt', 0.02), ('Sweet Sauce', 'Garlic', 0.01), ('Sweet Sauce', 'Acidulant', 0.002), ('Sweet Sauce', 'Sodium Benzoate', 0.002), ('Sweet Sauce', 'Artificial Food Colors with Tartrazine', 0.001),
  ('Banana Ketchup', 'Banana', 0.25), ('Banana Ketchup', 'Water', 0.35), ('Banana Ketchup', 'Sugar', 0.16), ('Banana Ketchup', 'Modified Starch', 0.04), ('Banana Ketchup', 'Iodized Salt', 0.02), ('Banana Ketchup', 'Onion', 0.01), ('Banana Ketchup', 'Garlic', 0.01), ('Banana Ketchup', 'Spices', 0.01), ('Banana Ketchup', 'Vinegar', 0.05), ('Banana Ketchup', 'FD&C Red No. 40', 0.001), ('Banana Ketchup', 'FD&C Yellow No. 5', 0.001), ('Banana Ketchup', 'Sodium Benzoate', 0.002),
  ('Tomato Sauce', 'Tomato Base - estimated placeholder', 0.55), ('Tomato Sauce', 'Water', 0.3), ('Tomato Sauce', 'Iodized Salt', 0.02), ('Tomato Sauce', 'Sugar', 0.05),
  ('Spaghetti Sauce', 'Tomato Base - estimated placeholder', 0.5), ('Spaghetti Sauce', 'Sugar', 0.08), ('Spaghetti Sauce', 'Spices', 0.02), ('Spaghetti Sauce', 'Modified Starch', 0.03),
  ('Hot Sauce', 'Chili Pepper - estimated placeholder', 0.25), ('Hot Sauce', 'Vinegar', 0.3), ('Hot Sauce', 'Water', 0.25), ('Hot Sauce', 'Iodized Salt', 0.02),
  ('Oyster Sauce', 'Oyster Extract - estimated placeholder', 0.25), ('Oyster Sauce', 'Sugar', 0.16), ('Oyster Sauce', 'Water', 0.35), ('Oyster Sauce', 'Modified Starch', 0.04)
) AS seed(product_name, ingredient_name, quantity)
JOIN public.products p ON lower(p.name) = lower(seed.product_name)
JOIN public.recipes r ON r.product_id = p.id
JOIN public.ingredients i ON lower(i.name) = lower(seed.ingredient_name)
WHERE NOT EXISTS (
  SELECT 1 FROM public.recipe_ingredients ri
  WHERE ri.recipe_id = r.id AND ri.ingredient_id = i.id
);
