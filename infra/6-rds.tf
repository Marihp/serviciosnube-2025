############################################
# RDS con terraform-aws-modules/rds/aws (sin KMS explícitas)
# - Sin manage_master_user_password (evita KMS/Secrets en el create)
# - Password generada y guardada en SSM SecureString
# - storage_encrypted = true (AWS usa su KMS administrada automáticamente)
############################################

# 1) Password del master
resource "random_password" "rds_master" {
  length  = 20
  special = false # evita caracteres que a veces rechaza el engine al crear
  upper   = true
  lower   = true
  numeric = true
}

# 2) Guardar la password en SSM Parameter Store (SecureString)
resource "aws_ssm_parameter" "db_master_password" {
  name  = "/${var.project}/${var.environment}/db/master_password"
  type  = "SecureString" # usa la KMS por defecto de SSM sin que la especifiques
  value = random_password.rds_master.result
  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# 3) RDS con el módulo oficial (sin KMS explícitas ni Secrets Manager en create)
module "db" {
  source  = "terraform-aws-modules/rds/aws"
  version = "6.13.1"

  # Identificador
  identifier = "${var.project}-${var.environment}"

  # Engine / versión / clase
  engine         = var.rds_engine
  engine_version = var.rds_engine_version
  instance_class = var.rds_instance_class

  # DB inicial y credenciales
  db_name  = var.rds_db_name
  username = var.rds_username
  password = random_password.rds_master.result # << SIN manage_master_user_password

  # Puerto
  port = tostring(var.rds_port)

  # Red
  publicly_accessible    = var.rds_public_access
  multi_az               = var.rds_multi_az
  vpc_security_group_ids = var.rds_vpc_security_group_ids

  # Subnet group (lo crea el módulo)
  create_db_subnet_group = true
  subnet_ids             = var.rds_subnet_ids # << IDs REALES (no CIDRs)

  # Almacenamiento
  storage_type          = "gp3"
  storage_encrypted     = true # << sin kms_key_id → usa default AWS-managed key
  allocated_storage     = var.rds_allocated_storage
  max_allocated_storage = var.rds_max_allocated_storage

  # Logs / Backups
  enabled_cloudwatch_logs_exports = var.rds_engine == "postgres" ? ["postgresql"] : ["slowquery"]
  backup_retention_period         = var.rds_backup_retention_days

  # Operativa
  deletion_protection = var.rds_deletion_protection
  skip_final_snapshot = var.rds_skip_final_snapshot
  apply_immediately   = true

  # Desactiva features que disparan KMS durante el create
  manage_master_user_password  = false
  performance_insights_enabled = false

  create_db_parameter_group = false
  create_db_option_group    = false

  tags = {
    Name        = "${var.project}-${var.environment}"
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

output "rds_endpoint" {
  value = module.db.db_instance_endpoint
}

output "rds_port" {
  value = module.db.db_instance_port
}

output "rds_arn" {
  value = module.db.db_instance_arn
}
