module "db" {
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 6.13.1"

  identifier     = "${var.project}-${var.environment}"
  engine         = "postgres"
  engine_version = "16.3"
  instance_class = "db.t4g.micro"
  port           = 9876

  allocated_storage     = 20
  max_allocated_storage = 100

  multi_az            = var.rds_multi_az
  storage_encrypted   = true
  publicly_accessible = var.rds_public_access

  username                    = "appuser"
  db_name                     = "nexacloud"
  manage_master_user_password = true # secreto en Secrets Manager

  backup_retention_period      = 7
  delete_automated_backups     = true
  deletion_protection          = false
  performance_insights_enabled = true

  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = module.vpc.database_subnet_group_name
}

output "rds_endpoint" { value = module.db.db_instance_endpoint }
output "rds_secret_arn" { value = module.db.db_instance_master_user_secret_arn }
