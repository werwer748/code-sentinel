# status-api

Public status endpoint for the platform.

- `npm test` runs the node:test suite.
- `npm run docs:build` renders `docs/*.md` into `docs/dist`.
- Pushes to `main` deploy through `.github/workflows/deploy.yml`, which copies a release tarball to the
  host and runs `scripts/deploy.sh` there.
- Infrastructure lives in `infra/` (Terraform, state in S3 with DynamoDB locking).
