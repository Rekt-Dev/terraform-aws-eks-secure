terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "my-terraform-state-bucket"  # Replace with actual bucket name
    key            = "eks/production/terraform.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
    kms_key_id     = "alias/terraform-state-key"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

locals {
  common_tags = {
    Environment = "production"
    ManagedBy   = "terraform"
    Repository  = "terraform-aws-eks-secure"
    Cluster     = var.cluster_name
  }
}

module "vpc" {
  source = "../../modules/vpc"

  cluster_name = var.cluster_name
  vpc_cidr     = var.vpc_cidr
  tags         = local.common_tags
}

module "eks" {
  source = "../../modules/eks"

  cluster_name        = var.cluster_name
  kubernetes_version  = var.kubernetes_version
  private_subnet_ids  = module.vpc.private_subnet_ids
  node_instance_types = var.node_instance_types
  node_desired_count  = var.node_desired_count
  node_min_count      = var.node_min_count
  node_max_count      = var.node_max_count
  tags                = local.common_tags
}

# Example IRSA: S3 read access for a backup service
module "backup_irsa" {
  source = "../../modules/irsa"

  oidc_provider_arn    = module.eks.oidc_provider_arn
  oidc_provider_url    = module.eks.oidc_provider_url
  namespace            = "production"
  service_account_name = "backup-service"
  role_name_prefix     = "${var.cluster_name}-backup"
  policy_arns          = ["arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"]
  tags                 = local.common_tags
}
