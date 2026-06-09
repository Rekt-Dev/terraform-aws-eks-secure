# Bootstrap: create S3 bucket and DynamoDB table for Terraform state
# Run this once before using any other module.
# State for this bootstrap is stored locally (not in S3).
#
# Usage:
#   terraform init
#   terraform apply
#   # Note the bucket name from outputs, update backend.tf in environments/

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

resource "aws_kms_key" "state" {
  description             = "KMS key for Terraform state encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name      = "terraform-state-key"
    ManagedBy = "terraform"
  }
}

resource "aws_kms_alias" "state" {
  name          = "alias/terraform-state-key"
  target_key_id = aws_kms_key.state.key_id
}

resource "aws_s3_bucket" "state" {
  bucket        = var.bucket_name
  force_destroy = false

  tags = {
    Name      = "terraform-state"
    ManagedBy = "terraform"
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.state.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "lock" {
  name         = "terraform-state-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.state.arn
  }

  tags = {
    Name      = "terraform-state-lock"
    ManagedBy = "terraform"
  }
}

variable "aws_region" {
  type    = string
  default = "eu-west-1"
}

variable "bucket_name" {
  type        = string
  description = "S3 bucket name for Terraform state — must be globally unique"
}

output "bucket_name" {
  value = aws_s3_bucket.state.bucket
}

output "dynamodb_table" {
  value = aws_dynamodb_table.lock.name
}
