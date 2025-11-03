module "images_lambda" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 7.0"

  function_name = "${var.project}-${var.environment}-images-handler"
  handler       = "app.handler"
  runtime       = "python3.12"
  timeout       = 10
  memory_size   = 256

  source_path = [{
    path             = "${path.module}/lambdas/images_handler"
    pip_requirements = false
    exclude_glob     = ["**/__pycache__/**", "**/*.pyc"]
  }]

  environment_variables = {
    BUCKET = module.images_bucket.s3_bucket_id
  }

  cloudwatch_logs_retention_in_days = 14

  attach_policy_json = true
  policy_json = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect   = "Allow",
      Action   = ["s3:GetObject", "s3:ListBucket"],
      Resource = [module.images_bucket.s3_bucket_arn, "${module.images_bucket.s3_bucket_arn}/images/*"]
    }]
  })

  vpc_subnet_ids         = module.vpc.private_subnets
  vpc_security_group_ids = [aws_security_group.lambdas.id]
}
