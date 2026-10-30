# ADR 0004: Serve product images directly from the partner CDN

Status: accepted

Product photos are uploaded by merchants to the partner CDN, which already stores every image as
pre-sized WebP renditions (96px thumbnails and 800px detail images) with long-lived cache headers.

Routing them through `next/image` would make our Next.js server download and re-encode each image and
would double the egress bill without improving quality. We therefore render plain `<img>` elements with
explicit `width`/`height` (no layout shift) for CDN URLs and disable `@next/next/no-img-element` on those
lines with a reason that points to this ADR.
