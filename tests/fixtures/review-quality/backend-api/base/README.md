# shop-api

Express 5 + PostgreSQL API for the shop.

- `npm run build` compiles TypeScript to `dist/`.
- `npm test` runs the integration tests against `DATABASE_URL` (a disposable test database).
- SQL migrations in `migrations/` are applied in file-name order by the deploy pipeline before the new
  application version starts.
