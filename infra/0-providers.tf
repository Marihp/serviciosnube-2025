terraform {
  required_version = ">= 1.13.1"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.19.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  default_tags {
    tags = {
      Owner       = "marhernandezpa@unal.edu.co"
      ManagedBy   = "terraform"
      Project     = var.project
      Environment = var.environment
    }
  }
}
