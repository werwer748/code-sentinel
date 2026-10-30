# ADR 0007: Host the public docs site in a public-read S3 bucket

Status: accepted

The documentation at docs.status.example.com is public marketing and API reference material. It is
generated from `docs/*.md` by `npm run docs:build` and contains no customer data.

We serve it straight from the S3 website endpoint of `status-docs-public`:

- read access is granted with a bucket policy limited to `s3:GetObject` on objects;
- object ACLs stay blocked (`block_public_acls`, `ignore_public_acls`);
- nothing except the docs build output is ever written to this bucket.

TLS for docs.status.example.com is terminated by the shared company CDN in front of the website
endpoint (managed outside this repository), so no CloudFront distribution is needed here.
