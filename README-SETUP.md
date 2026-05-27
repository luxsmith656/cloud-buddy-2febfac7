# Cloud Buddy Setup Notes

Use `README.md` as the primary setup guide.

Quick start:

```bash
npm ci
cp .env.example .env.local
npm run dev
```

Important:

- Use npm only.
- Apply every Supabase migration before testing production workflows.
- Create a Supabase Auth user, then insert an `admin` row into `public.user_roles`.
- Rotate the previously committed Supabase anon/JWT credentials before production use.
- Run `npm run lint`, `npm run typecheck`, `npm test`, `npm audit --audit-level=moderate`, and `npm run build` before deployment.
