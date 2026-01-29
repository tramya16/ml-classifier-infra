# S3 Bucket for image uploads
resource "aws_s3_bucket" "images" {
  bucket = "${var.project_name}-images-${var.environment}"

  force_destroy = true

  tags = {
    Name = "${var.project_name}-images"
  }
}

#Enable encryption at rest for S3 bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "images" {
  bucket = aws_s3_bucket.images.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"  # AWS-managed encryption (free), for stricter compliance, we can use aws:kms with KMS key
    }
  }
}

# Block all public access to prevent accidental exposure
resource "aws_s3_bucket_public_access_block" "images" {
  bucket = aws_s3_bucket.images.id

  block_public_acls       = true  # Block public ACLs
  block_public_policy     = true  # Block public bucket policies
  ignore_public_acls      = true  # Ignore existing public ACLs
  restrict_public_buckets = true  # Restrict public bucket policies
}

#we enable versioning for data recovery
resource "aws_s3_bucket_versioning" "images" {
  bucket = aws_s3_bucket.images.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_cors_configuration" "images" {
  bucket = aws_s3_bucket.images.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

resource "aws_s3_bucket_policy" "images" {
  bucket = aws_s3_bucket.images.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowAllActions"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.images.arn,
          "${aws_s3_bucket.images.arn}/*"
        ]
        Condition = {
          StringEquals = {
            "aws:SourceVpc" = data.aws_vpc.main.id
          }
        }
      }
    ]
  })
}

# Auto-delete user-uploaded images after short temporary period, as we need only for inference in ML
resource "aws_s3_bucket_lifecycle_configuration" "images" {
  bucket = aws_s3_bucket.images.id

  rule {
    id     = "expire-temporary-user-uploads"
    status = "Enabled"

    expiration {
      days = 14 
    }
  }

  # Clean up failed/incomplete multipart uploads
  rule {
    id     = "abort-incomplete-multipart"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 1  # Clean up stalled uploads quickly
    }
  }
}