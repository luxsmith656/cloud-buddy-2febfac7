# Cloud Buddy Production Checklist

- [x] Use npm only for installs and builds.
- [x] Keep only safe environment examples in Git.
- [x] Add atomic batch production with editable expiration dates.
- [x] Add unique per-batch barcode/lot codes.
- [x] Add barcode scanner and barcode printing pages.
- [x] Add label-informed seed data and clearly marked estimated placeholder products.
- [x] Show batch barcodes in batch production, defects, stock movements, dispatch, and reports.
- [x] Add PWA manifest, service worker, update status, and read-only offline barcode cache sync.
- [x] Remove hardcoded Supabase fallback config and keep npm as the only package manager.
- [ ] Apply latest Supabase migrations through `20260603090000_security_pwa_hardening.sql` in Supabase/Lovable.
- [ ] Confirm Vercel has `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY`, then redeploy.
- [ ] Test with a real camera device and a USB barcode scanner.
- [ ] Run Lighthouse/PWA audit on the final Vercel deployment.
- [ ] Add seeded Supabase integration tests for authenticated CRUD/RPC workflows.
- [ ] Add backups, monitoring, audit dashboards, import/export, low-stock/expiration notifications, barcode hardware SOPs, and inventory adjustment approvals for high-value changes.
