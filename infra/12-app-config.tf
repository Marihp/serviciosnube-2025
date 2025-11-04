############################################
# Parámetros de app / DB en SSM (vía module.db)
############################################

# Host / endpoint del RDS
resource "aws_ssm_parameter" "db_host" {
  name  = "/${var.project}/${var.environment}/db/host"
  type  = "String"
  value = module.db.db_instance_endpoint
}

# Puerto
resource "aws_ssm_parameter" "db_port" {
  name  = "/${var.project}/${var.environment}/db/port"
  type  = "String"
  value = tostring(module.db.db_instance_port)
}

# Nombre de base
resource "aws_ssm_parameter" "db_name" {
  name  = "/${var.project}/${var.environment}/db/name"
  type  = "String"
  value = var.rds_db_name
}

# Usuario
resource "aws_ssm_parameter" "db_user" {
  name  = "/${var.project}/${var.environment}/db/user"
  type  = "String"
  value = var.rds_username
}


############################################
# SSM params para URLs y API keys de la app
# - Usa tu API Gateway ya creado (mismo REST API/Stage)
############################################

# Base URL de API Gateway (mismo cálculo que tu output)
locals {
  api_base_url = "https://${aws_api_gateway_rest_api.api.id}.execute-api.${var.aws_region}.amazonaws.com/${aws_api_gateway_stage.prod.stage_name}"
}

# --- URLs a tus endpoints ---
# /images (GET) -> Lambda "images"
resource "aws_ssm_parameter" "lambda_s3_url" {
  name  = "/${var.project}/${var.environment}/lambda/s3/url"
  type  = "String"
  value = "${local.api_base_url}/images"
}

# /students (POST) -> Lambda "students"
resource "aws_ssm_parameter" "lambda_db_url" {
  name  = "/${var.project}/${var.environment}/lambda/db/url"
  type  = "String"
  value = "${local.api_base_url}/students"
}

# --- API Keys ---
# Reutilizamos TU API key existente para ambos (si quieres 2 llaves distintas, te dejo nota abajo)
resource "aws_ssm_parameter" "lambda_s3_apikey" {
  name  = "/${var.project}/${var.environment}/lambda/s3/apikey"
  type  = "SecureString"
  value = aws_api_gateway_api_key.key.value
}

resource "aws_ssm_parameter" "lambda_db_apikey" {
  name  = "/${var.project}/${var.environment}/lambda/db/apikey"
  type  = "SecureString"
  value = aws_api_gateway_api_key.key.value
}

# --- Otros parámetros usados por tu user_data ---
# Ruta para stress (ajústala si tu app usa otra)
resource "aws_ssm_parameter" "stress_path" {
  name  = "/${var.project}/${var.environment}/stress/path"
  type  = "String"
  value = "/stress"
}

# URL del ALB (si no quieres depender del recurso, pásalo vía variable)
resource "aws_ssm_parameter" "alb_url" {
  name  = "/${var.project}/${var.environment}/alb/url"
  type  = "String"
  value = "http://servicios-nube-dev-alb-467986149.us-east-1.elb.amazonaws.com"
}

