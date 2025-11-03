module "students_lambda" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 7.0"

  function_name = "${var.project}-${var.environment}-students-writer"
  handler       = "app.handler"
  runtime       = "python3.12"
  architectures = ["x86_64"]
  timeout       = 10
  memory_size   = 512

  source_path = [{
    path             = "${path.module}/lambdas/students_writer"
    pip_requirements = true # usa requirements.txt (psycopg2-binary)
    build_in_docker  = true # asegura binarios compatibles
    exclude_glob     = ["**/__pycache__/**", "**/*.pyc"]
  }]

  environment_variables = {
    DB_SECRET_ARN = module.db.db_instance_master_user_secret_arn
  }

  cloudwatch_logs_retention_in_days = 14

  vpc_subnet_ids         = module.vpc.private_subnets
  vpc_security_group_ids = [aws_security_group.lambdas.id]

  attach_policy_json = true
  policy_json = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect   = "Allow",
      Action   = ["secretsmanager:GetSecretValue"],
      Resource = module.db.db_instance_master_user_secret_arn
    }]
  })
}
