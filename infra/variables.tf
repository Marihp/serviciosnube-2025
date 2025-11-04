variable "aws_region" {
  type        = string
  description = "AWS Region"
  default     = "us-east-1"
}

variable "aws_profile" {
  type        = string
  description = "AWS named profile"
  default     = "terraform-prod"
}

variable "project" {
  type    = string
  default = "servicios-nube"
}

variable "environment" {
  type    = string
  default = "dev"
}

# -------- VPC --------
variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "azs" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b"]
}

variable "public_subnets" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnets" {
  type    = list(string)
  default = ["10.0.101.0/24", "10.0.102.0/24"]
}

variable "database_subnets" {
  type    = list(string)
  default = ["10.0.201.0/24", "10.0.202.0/24"]
}

# NAT cost optimization
variable "single_nat_gateway" {
  type    = bool
  default = true
}

# -------- RDS --------
variable "rds_multi_az" {
  type    = bool
  default = false
}

variable "rds_public_access" {
  type    = bool
  default = false # actívalo solo si necesitas conectar DBeaver desde tu IP
}

variable "db_allowed_cidrs" {
  description = "CIDRs permitidos a RDS si rds_public_access=true (e.g. tu IP /32)"
  type        = list(string)
  default     = []
}

# -------- ALB/ASG --------
variable "instance_type" {
  type    = string
  default = "t3.small"
}

variable "asg_desired" {
  type    = number
  default = 2
}
variable "asg_max" {
  type    = number
  default = 5
}

variable "alb_health_check_path" {
  type    = string
  default = "/"
}

# -------- Observability --------
variable "alert_email" {
  type        = string
  description = "Email para suscripción SNS (alarmas)"
  default     = "marhernandezpa@unal.edu.co"
}

# -------- General --------
variable "tags_extra" {
  type    = map(string)
  default = {}
}

