module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.5.0"

  name = "${var.project}-${var.environment}-vpc"
  cidr = var.vpc_cidr

  azs              = var.azs
  public_subnets   = var.public_subnets   # ALB
  private_subnets  = var.private_subnets  # Lambdas/EC2
  database_subnets = var.database_subnets # RDS

  create_database_subnet_group = true

  enable_dns_support   = true
  enable_dns_hostnames = true

  create_igw         = true
  enable_nat_gateway = true
  single_nat_gateway = var.single_nat_gateway

  # Etiquetas
  tags = merge({
    "Component" = "networking"
  }, var.tags_extra)
}
