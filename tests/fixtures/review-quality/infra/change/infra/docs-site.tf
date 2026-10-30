# Public by design: this bucket only holds the generated public documentation site
# (docs.status.example.com). It never stores user data, logs or build artifacts.
# Decision record: docs/adr/0007-public-docs-bucket.md
resource "aws_s3_bucket" "docs_site" {
  bucket = "status-docs-public"
}

resource "aws_s3_bucket_public_access_block" "docs_site" {
  bucket = aws_s3_bucket.docs_site.id

  # ACLs stay blocked; read access is granted only through the bucket policy below.
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_website_configuration" "docs_site" {
  bucket = aws_s3_bucket.docs_site.id

  index_document {
    suffix = "index.html"
  }
}

data "aws_iam_policy_document" "docs_site_public_read" {
  statement {
    sid       = "PublicReadDocs"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.docs_site.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }
  }
}

resource "aws_s3_bucket_policy" "docs_site" {
  bucket     = aws_s3_bucket.docs_site.id
  policy     = data.aws_iam_policy_document.docs_site_public_read.json
  depends_on = [aws_s3_bucket_public_access_block.docs_site]
}
