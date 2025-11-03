module "images_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 5.8.2"

  bucket = "${var.project}-${var.environment}-images"

  control_object_ownership = true
  object_ownership         = "BucketOwnerEnforced"
  acl                      = null

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  force_destroy = false

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = { sse_algorithm = "AES256" }
    }
  }

  versioning = { enabled = true }

  lifecycle_rule = [
    {
      id                            = "noncurrent-tiering"
      enabled                       = true
      noncurrent_version_expiration = { noncurrent_days = 180 }
      noncurrent_version_transition = [
        { noncurrent_days = 30, storage_class = "STANDARD_IA" },
        { noncurrent_days = 90, storage_class = "GLACIER_IR" }
      ]
    }
  ]

  # Enforce TLS
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Sid       = "DenyInsecureTransport",
      Effect    = "Deny",
      Principal = "*",
      Action    = "s3:*",
      Resource = [
        "arn:aws:s3:::${var.project}-${var.environment}-images",
        "arn:aws:s3:::${var.project}-${var.environment}-images/*"
      ],
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })

  tags = { Purpose = "nexacloud-images" }
}
