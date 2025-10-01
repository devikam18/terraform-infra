############################################
# Variables
############################################
variable "bucket_name_prefix" {
  default = "my-terraform-state-bucket-demo"
}

variable "dynamodb_table_name" {
  default = "terraform-locks-demo"
}

variable "environment" {
  default = "dev"
}

############################################
# Random ID for uniqueness
############################################
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

############################################
# Provider
############################################
provider "aws" {
  region = "ap-south-2"
}

############################################
# S3 Bucket for Terraform State
############################################
resource "aws_s3_bucket" "terraform_state" {
  bucket = "${var.bucket_name_prefix}-${random_id.bucket_suffix.hex}"

  tags = {
    Name        = "terraform-state"
    Environment = var.environment
  }

  # Optional: remove if you want to allow destroy in CI/CD
  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_s3_bucket_versioning" "versioning" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "encryption" {
  bucket = aws_s3_bucket.terraform_state.bucket

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "public_access" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

############################################
# DynamoDB Table for Locking
############################################
resource "aws_dynamodb_table" "terraform_locks" {
  name         = var.dynamodb_table_name
  hash_key     = "LockID"
  billing_mode = "PAY_PER_REQUEST"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Environment = var.environment
  }
}

############################################
# Outputs
############################################
output "s3_bucket_name" {
  value = aws_s3_bucket.terraform_state.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.terraform_locks.name
}

