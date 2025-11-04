############################################
# Variables específicas de RDS que faltaban
############################################

variable "rds_engine" {
  type        = string
  default     = "postgres" # o "mysql"
  description = "Engine de RDS"
}

variable "rds_engine_version" {
  type        = string
  default     = "16.3" # ejemplo para Postgres
  description = "Versión del engine"
}

variable "rds_instance_class" {
  type        = string
  default     = "db.t4g.micro"
  description = "Clase de instancia"
}

variable "rds_db_name" {
  type        = string
  default     = "appdb"
  description = "Nombre de la base inicial"
}

variable "rds_username" {
  type        = string
  default     = "appuser"
  description = "Usuario master (password se gestiona en Secrets Manager)"
}

variable "rds_allocated_storage" {
  type        = number
  default     = 20
  description = "GB iniciales"
}

variable "rds_max_allocated_storage" {
  type        = number
  default     = 100
  description = "Auto-scaling de storage (GB máx)"
}

variable "rds_backup_retention_days" {
  type    = number
  default = 7
}

variable "rds_deletion_protection" {
  type    = bool
  default = false
}

variable "rds_skip_final_snapshot" {
  type    = bool
  default = true
}

variable "rds_port" {
  type    = number
  default = 9876
}

# IDs de subredes donde vivirá el RDS (privadas o database)
variable "rds_subnet_ids" {
  type        = list(string)
  default     = ["subnet-03ffc52709d3d217b", "subnet-0c45c353e1a36b9fb"]
  description = "Lista de subnet IDs para DB Subnet Group"
}

# SGs para el RDS (si vacío, usará el default de la VPC)
variable "rds_vpc_security_group_ids" {
  type        = list(string)
  default     = ["sg-060f0dba7c0e91d76"]
  description = "Security groups asociados al RDS"
}
