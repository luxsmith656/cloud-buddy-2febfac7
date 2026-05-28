# Cloud Buddy Production Checklist

- [x] Use npm only for installs and builds.
- [x] Keep only safe environment examples in Git.
- [x] Add atomic batch production with editable expiration dates.
- [x] Add unique per-batch barcode/lot codes.
- [x] Add barcode scanner and barcode printing pages.
- [x] Add label-informed seed data and clearly marked estimated placeholder products.
- [x] Show batch barcodes in batch production, defects, stock movements, dispatch, and reports.
- [ ] Apply `20260528100000_batch_barcode_system.sql` and `20260528101000_label_seed_data.sql` in Supabase/Lovable.
- [ ] Confirm Vercel has `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY`, then redeploy.
- [ ] Test with a real camera device and a USB barcode scanner.
- [ ] Add seeded Supabase integration tests for authenticated CRUD/RPC workflows.
- [ ] Add backups, monitoring, audit dashboards, import/export, low-stock/expiration notifications, barcode hardware SOPs, and inventory adjustment approvals for high-value changes.
