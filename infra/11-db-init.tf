variable "enable_db_seed" {
  type    = bool
  default = true
}

module "db_init_lambda" {
  count   = var.enable_db_seed ? 1 : 0
  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 7.0"

  function_name = "${var.project}-${var.environment}-db-init"
  handler       = "app.handler"
  runtime       = "python3.12"
  architectures = ["x86_64"]
  timeout       = 45
  memory_size   = 256

  source_path = [{
    path             = "${path.module}/lambdas/db_init"
    pip_requirements = true
    build_in_docker  = true
  }]

  environment_variables = {
    DB_SECRET_ARN  = module.db.db_instance_master_user_secret_arn
    APP_SECRET_ARN = aws_secretsmanager_secret.app.arn
  }

  vpc_subnet_ids         = module.vpc.private_subnets
  vpc_security_group_ids = [aws_security_group.lambdas.id]

  attach_policy_json = true
  policy_json = jsonencode({
    Version = "2012-10-17",
    Statement = [
      { Effect : "Allow", Action : ["secretsmanager:GetSecretValue"], Resource : module.db.db_instance_master_user_secret_arn },
      { Effect : "Allow", Action : ["secretsmanager:GetSecretValue"], Resource : aws_secretsmanager_secret.app.arn }
    ]
  })
}

data "aws_lambda_invocation" "db_init_run" {
  count         = var.enable_db_seed ? 1 : 0
  function_name = module.db_init_lambda[0].lambda_function_name
  input         = jsonencode({ "action" : "seed" })
  depends_on    = [module.db]
}

output "db_seed_result" {
  value       = var.enable_db_seed ? try(jsondecode(data.aws_lambda_invocation.db_init_run[0].result)["body"], null) : null
  description = "Resultado de la ejecución de seed"
}
