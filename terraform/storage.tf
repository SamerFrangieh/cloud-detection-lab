data "aws_caller_identity" "me" {}

resource "aws_s3_bucket" "data" {
  bucket        = "${var.name}-company-data-${data.aws_caller_identity.me.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "data" {
  bucket                  = aws_s3_bucket.data.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "customers" {
  bucket  = aws_s3_bucket.data.id
  key     = "exports/customers.csv"
  content = "id,name,email\n1,Jane Doe,jane@example.com\n2,John Roe,john@example.com\n"
}