############################################
# API Gateway REST -> Lambda (recursos directos)
# - Usa var.aws_region (evita atributo deprecado)
############################################

resource "aws_api_gateway_rest_api" "api" {
  name        = "${var.project}-${var.environment}-api"
  description = "NexaCloud intranet pilot REST API"

  api_key_source = "HEADER"
  endpoint_configuration { types = ["REGIONAL"] }
}

# ----- /images GET -> aws_lambda_function.images -----
resource "aws_api_gateway_resource" "images" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "images"
}

resource "aws_api_gateway_method" "images_get" {
  rest_api_id      = aws_api_gateway_rest_api.api.id
  resource_id      = aws_api_gateway_resource.images.id
  http_method      = "GET"
  authorization    = "NONE"
  api_key_required = true
}

resource "aws_api_gateway_integration" "images_get" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.images.id
  http_method             = aws_api_gateway_method.images_get.http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.images.arn}/invocations"
  depends_on              = [aws_lambda_function.images]
}

# ----- /students POST -> aws_lambda_function.students -----
resource "aws_api_gateway_resource" "students" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "students"
}

resource "aws_api_gateway_method" "students_post" {
  rest_api_id      = aws_api_gateway_rest_api.api.id
  resource_id      = aws_api_gateway_resource.students.id
  http_method      = "POST"
  authorization    = "NONE"
  api_key_required = true
}

resource "aws_api_gateway_integration" "students_post" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.students.id
  http_method             = aws_api_gateway_method.students_post.http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.students.arn}/invocations"
  depends_on              = [aws_lambda_function.students]
}

# Permisos para que API GW invoque las lambdas
resource "aws_lambda_permission" "allow_apigw_images" {
  statement_id  = "AllowAPIGWInvokeImages"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.images.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*/images"
}

resource "aws_lambda_permission" "allow_apigw_students" {
  statement_id  = "AllowAPIGWInvokeStudents"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.students.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*/students"
}

# Logging a CloudWatch (rol de cuenta)
resource "aws_iam_role" "apigw_cw_role" {
  name = "${var.project}-${var.environment}-apigw-cw"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [{ Effect = "Allow", Principal = { Service = "apigateway.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}
resource "aws_iam_role_policy_attachment" "apigw_cw_attach" {
  role       = aws_iam_role.apigw_cw_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}
resource "aws_api_gateway_account" "account" {
  cloudwatch_role_arn = aws_iam_role.apigw_cw_role.arn
}

# Despliegue y stage
resource "aws_cloudwatch_log_group" "apigw_logs" {
  name              = "/apigw/${var.project}-${var.environment}"
  retention_in_days = 14
}

resource "aws_api_gateway_deployment" "deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  triggers = {
    redeploy = sha1(jsonencode({
      resources = [aws_api_gateway_resource.images.id, aws_api_gateway_resource.students.id]
      methods   = [aws_api_gateway_method.images_get.id, aws_api_gateway_method.students_post.id]
      integrs   = [aws_api_gateway_integration.images_get.id, aws_api_gateway_integration.students_post.id]
    }))
  }
  lifecycle { create_before_destroy = true }
  depends_on = [
    aws_api_gateway_integration.images_get,
    aws_api_gateway_integration.students_post
  ]
}

resource "aws_api_gateway_stage" "prod" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.deployment.id
  stage_name    = "prod"

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.apigw_logs.arn
    format = jsonencode({
      requestId   = "$context.requestId",
      ip          = "$context.identity.sourceIp",
      requestTime = "$context.requestTime",
      httpMethod  = "$context.httpMethod",
      resource    = "$context.resourcePath",
      status      = "$context.status",
      protocol    = "$context.protocol"
    })
  }
}

# API Key + Usage Plan
resource "aws_api_gateway_api_key" "key" {
  name    = "${var.project}-${var.environment}-api-key"
  enabled = true
}

resource "aws_api_gateway_usage_plan" "plan" {
  name = "${var.project}-${var.environment}-plan"
  api_stages {
    api_id = aws_api_gateway_rest_api.api.id
    stage  = aws_api_gateway_stage.prod.stage_name
  }
}

resource "aws_api_gateway_usage_plan_key" "bind" {
  key_id        = aws_api_gateway_api_key.key.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.plan.id
}

output "api_invoke_url" {
  value = "https://${aws_api_gateway_rest_api.api.id}.execute-api.${var.aws_region}.amazonaws.com/${aws_api_gateway_stage.prod.stage_name}"
}
