##############################
# App config (SSM + Secrets) #
##############################

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  ssm_path     = "/${var.project}/${var.environment}"
  api_base_url = "https://${aws_api_gateway_rest_api.api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.prod.stage_name}"
}

# Password aleatorio para el usuario de app (no usar master)
resource "random_password" "db_app" {
  length  = 20
  special = true
}

# Secreto JSON con credenciales y API keys
resource "aws_secretsmanager_secret" "app" {
  name = "${var.project}/${var.environment}/app"
}

resource "aws_secretsmanager_secret_version" "app" {
  secret_id = aws_secretsmanager_secret.app.id
  secret_string = jsonencode({
    DB_USER              = "appuser"
    DB_PASSWORD          = random_password.db_app.result
    AWS_S3_LAMBDA_APIKEY = aws_api_gateway_api_key.key.value
    AWS_DB_LAMBDA_APIKEY = aws_api_gateway_api_key.key.value
  })
}

# SSM parameters (valores no sensibles y endpoints)
resource "aws_ssm_parameter" "company_name" {
  name  = "${local.ssm_path}/COMPANY_NAME"
  type  = "String"
  value = "NexaCloud" # cámbialo si quieres
}

resource "aws_ssm_parameter" "db_host" {
  name  = "${local.ssm_path}/DB_HOST"
  type  = "String"
  value = module.db.db_instance_endpoint
}

resource "aws_ssm_parameter" "db_database" {
  name  = "${local.ssm_path}/DB_DATABASE"
  type  = "String"
  value = "nexacloud"
}

resource "aws_ssm_parameter" "s3_lambda_url" {
  name  = "${local.ssm_path}/AWS_S3_LAMBDA_URL"
  type  = "String"
  value = "${local.api_base_url}/images"
}

resource "aws_ssm_parameter" "db_lambda_url" {
  name  = "${local.ssm_path}/AWS_DB_LAMBDA_URL"
  type  = "String"
  value = "${local.api_base_url}/students"
}

resource "aws_ssm_parameter" "stress_path" {
  name  = "${local.ssm_path}/STRESS_PATH"
  type  = "String"
  value = "/usr/bin/stress"
}

resource "aws_ssm_parameter" "lb_url" {
  name  = "${local.ssm_path}/LOAD_BALANCER_URL"
  type  = "String"
  value = "http://${aws_lb.alb.dns_name}"
}

# --- Permisos para que EC2 lea estos valores ---
data "aws_iam_policy_document" "ec2_app_read" {
  statement {
    sid     = "ReadSSMParameters"
    effect  = "Allow"
    actions = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
    resources = [
      "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/${var.project}/${var.environment}/*"
    ]
  }
  statement {
    sid       = "ReadAppSecret"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.app.arn]
  }
}

resource "aws_iam_policy" "ec2_app_read" {
  name   = "${var.project}-${var.environment}-ec2-app-read"
  policy = data.aws_iam_policy_document.ec2_app_read.json
}

# Lo atachamos al rol de EC2 (definido en 9-alb-asg.tf)
resource "aws_iam_role_policy_attachment" "ec2_app_read_attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.ec2_app_read.arn
}
