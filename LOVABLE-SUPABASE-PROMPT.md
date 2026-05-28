# Lovable Prompt For Supabase Setup

Copy and paste this into Lovable when you want it to apply the required Supabase database changes:

```text
Please apply the latest Cloud Buddy Supabase migrations exactly and safely.

Project goal: make Cloud Buddy production-ready without removing existing features.

Apply all SQL migration files in order from the repo:

1. supabase/migrations/20260412134318_e4c9a585-0318-4ac9-8285-c27144b03e0e.sql
2. supabase/migrations/20260412140000_add_image_fields.sql
3. supabase/migrations/20260523041855_43406f70-7f1c-4a17-a8e3-235217ebb35a.sql
4. supabase/migrations/20260527120000_harden_inventory_transactions.sql
5. supabase/migrations/20260527133000_operations_hardening.sql
6. supabase/migrations/20260527141545_7ddf89f0-86c8-4c9e-9203-43c8b0402080.sql
7. supabase/migrations/20260527143201_e504c6df-ebaa-4b48-a6e6-97b23938021d.sql
8. supabase/migrations/20260527150000_grant_has_role_execute.sql
9. supabase/migrations/20260527170000_real_life_inventory_flows.sql
10. supabase/migrations/20260528100000_batch_barcode_system.sql
11. supabase/migrations/20260528101000_label_seed_data.sql
12. supabase/migrations/20260528104146_0015b4b9-737b-45b5-9954-6f7964aa0321.sql
13. supabase/migrations/20260603090000_security_pwa_hardening.sql

Important requirements:
- Preserve existing data.
- Do not drop existing production tables or auth users.
- Add barcode columns to products and ingredients.
- Add inventory_adjustment_requests and RLS policies.
- Add request_inventory_adjustment and review_inventory_adjustment RPCs.
- Add set_user_role RPC for admin role management.
- Add refresh_inventory_alerts RPC.
- Make stock_movements append-only.
- Add save_recipe RPC so recipe header and ingredient rows are saved atomically.
- Grant authenticated users EXECUTE access on has_role(uuid, app_role), because the frontend and policies need this helper to resolve admin/user access.
- Add ingredient_receipts, product_dispatches, and inventory_activity tables.
- Add unit_cost to ingredients and unit_price/estimated_unit_cost to products.
- Add receive_ingredient RPC so inbound ingredient stock, receipt history, stock movement, activity history, and audit log are committed atomically.
- Add dispatch_product RPC so outbound product stock, optional batch deduction, dispatch history, stock movement, activity history, alert creation, and audit log are committed atomically.
- Keep audit_logs immutable with the new trigger.
- Keep batch production and defect logging atomic through produce_batch and log_defect.
- Replace old batch production behavior with the new barcode-aware produce_batch RPC signature:
  produce_batch(product_id_value uuid, quantity_value integer, expiration_date_value date, batch_code_value text default null, production_date_value date default current_date).
- Add unique batch-level batch_code/barcode_token/barcode_value fields to batches and backfill existing batches with internal CB-BTCH tokens.
- Add batch_id and batch_code to stock_movements.
- Update log_defect and dispatch_product so stock movements keep batch barcode details.
- Add find_batch_by_barcode(text) for scanner lookup. The barcode must store only the internal token; product details stay in Supabase and are shown only inside Cloud Buddy after authenticated lookup.
- Use 210-day shelf life for Banana Ketchup and Sweet Sauce. Use 240-day shelf life for Soy Sauce, Vinegar, and Fish Sauce.
- Add label-informed seed ingredients exactly where readable:
  Fish Sauce: Water, Fish Extract, Iodized Salt, Sodium Benzoate, Sodium Metabisulfite, Flavor Enhancer, Caramel Color.
  Soy Sauce: Iodized Salt, Water, Hydrolyzed Soybean Protein, Caramel as Color, Citric Acid as Acidulant, Sodium Benzoate as Preservative.
  Vinegar: Water, Cane Vinegar, Caramel as Colorant.
  Sweet Sauce: Sugar, Water, Spices, Modified Starch, Iodized Salt, Garlic, Acidulant, Sodium Benzoate as Preservative, Artificial Food Colors with Tartrazine.
  Banana Ketchup: Banana, Water, Sugar, Modified Starch, Iodized Salt, Onion, Garlic, Spices, Vinegar, FD&C Red No. 40, FD&C Yellow No. 5, Sodium Benzoate as Preservative.
- Add Tomato Sauce, Spaghetti Sauce, Hot Sauce, and Oyster Sauce as estimated placeholder products and editable demo recipes only. Do not treat their demo quantities as confirmed formulas.
- Harden the images storage bucket: public read, admin-only upload/update/delete, PNG/JPG/WEBP only, 5 MB limit.
- Add the admin profile read policy so admins can see user profiles in the Role Management page.
- Revoke anonymous EXECUTE access from has_role(uuid, app_role). Only authenticated users should call role helpers.
- Reconfirm the images bucket rejects SVG/GIF/BMP and only accepts PNG/JPG/WEBP up to 5 MB.

After applying migrations:
- Confirm RLS is enabled on all app tables.
- Confirm only admins can mutate products, ingredients, recipes, batches, defects, stock movements, alerts, roles, storage objects, and adjustment reviews.
- Confirm authenticated users can submit adjustment requests.
- Confirm the app anon key and JWT secret were rotated because a previous anon key was committed.
- Create or confirm one admin user by inserting into public.user_roles:

insert into public.user_roles (user_id, role)
values ('PASTE_ADMIN_USER_UUID_HERE', 'admin')
on conflict do nothing;

Then test these workflows:
- Signup/login.
- Admin can open Role Management and grant/revoke admin for another user.
- User can request a stock adjustment.
- Admin can approve/reject adjustment.
- Approved adjustment creates a stock movement and updates product/ingredient stock atomically.
- Admin can receive an ingredient; stock increases, a receipt is recorded, stock movement is created, and the activity page shows the receipt.
- Admin can dispatch a product; stock decreases, optional batch quantity decreases, dispatch history is recorded, stock movement is created, and the activity page shows the dispatch.
- Reports export inventory, receiving, dispatch, batch, usage, and defect data safely to CSV/PDF.
- Batch production works through produce_batch.
- Each production run creates its own separate batch row.
- Batch Production shows Batch Barcode/Lot Code, not "Batch 1" or "Batch 2".
- Expiration date is editable and required during batch creation, and the exact entered date is saved.
- Duplicate batch barcodes are rejected.
- Barcode Scanner can find a batch by token and shows product, category, manufactured date, expiration, shelf life, price/SRP, produced quantity, remaining stock, status, defect status, and recent stock movements.
- Barcode Scanner can sync batch barcode data while online and resolve synced batch tokens offline in read-only mode.
- Barcode Printing can filter batches and print compact A4 labels with Code 128 barcode tokens.
- Defect logging works through log_defect.
- Recipe create/edit works through save_recipe and does not leave partial recipe ingredient rows.
- Image upload rejects SVG and accepts PNG/JPG/WEBP.
- Refresh Alerts creates low-stock and expiration alerts.
```
