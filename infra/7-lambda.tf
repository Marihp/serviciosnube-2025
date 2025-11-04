############################################
# Lambdas con AWS Provider (archivo único)
############################################

#########################
# Variables
#########################

variable "lambda_runtime" {
  type        = string
  default     = "python3.12"
  description = "Runtime de las Lambdas (p. ej. python3.12 o python3.13)"
}

variable "lambda_architectures" {
  type    = list(string)
  default = ["x86_64"]
}

variable "lambda_timeout" {
  type    = number
  default = 30
}

variable "lambda_memory" {
  type    = number
  default = 256
}

variable "log_retention_in_days" {
  type    = number
  default = 14
}

# Desactiva si tu principal no tiene lambda:TagResource
variable "enable_lambda_tags" {
  type    = bool
  default = true
}

# Empaquetado opcional con Docker (instala requirements.txt dentro de cada carpeta)
variable "use_docker_packaging" {
  type        = bool
  default     = false
  description = "Instala requirements.txt dentro de cada lambda usando Docker (imagen SAM)."
}

# Si YA tienes un IAM Role para ejecución de Lambda, pásalo aquí y NO se creará uno nuevo
variable "lambda_exec_role_arn" {
  type        = string
  default     = ""
  description = "ARN de un IAM Role existente para Lambda. Si vacío, se crea uno nuevo."
}

# Variables de entorno por función (extra)
variable "images_env" {
  type    = map(string)
  default = {}
}
variable "students_env" {
  type    = map(string)
  default = {}
}
variable "db_init_env" {
  type    = map(string)
  default = {}
}

# Tags extra (se mezclan con Project/Environment/ManagedBy)
variable "lambda_tags_extra" {
  type    = map(string)
  default = {}
}

# Bucket S3 donde están las imágenes
variable "images_bucket" {
  type        = string
  description = "Bucket S3 donde están las imágenes"
  default     = "servicios-nube-dev-images"
}

#########################
# Locals
#########################

locals {
  # Requiere que en tu repo existan var.project / var.environment
  name_prefix = "${var.project}-${var.environment}"

  tags = merge({
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "Terraform"
  }, var.lambda_tags_extra)

  # Imagen SAM para el empaquetado Docker (si activas use_docker_packaging)
  sam_image = var.lambda_runtime == "python3.13" ? "public.ecr.aws/sam/build-python3.13:latest" : "public.ecr.aws/sam/build-python3.12:latest"
}

#########################
# IAM role (condicional)
#########################

data "aws_iam_policy_document" "assume_lambda" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_exec" {
  count              = var.lambda_exec_role_arn == "" ? 1 : 0
  name               = "${local.name_prefix}-lambda-exec"
  assume_role_policy = data.aws_iam_policy_document.assume_lambda.json
  tags               = var.enable_lambda_tags ? local.tags : {}
}

# Logging básico
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  count      = var.lambda_exec_role_arn == "" ? 1 : 0
  role       = aws_iam_role.lambda_exec[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Acceso a VPC (ENABLED siempre que usemos vpc_config)
resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  count      = var.lambda_exec_role_arn == "" ? 1 : 0
  role       = aws_iam_role.lambda_exec[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Política mínima para que la Lambda de imágenes lea el bucket
resource "aws_iam_role_policy" "images_s3_access" {
  count = var.lambda_exec_role_arn == "" ? 1 : 0

  name = "${local.name_prefix}-images-s3"
  role = aws_iam_role.lambda_exec[0].name

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid      = "ListBucket",
        Effect   = "Allow",
        Action   = ["s3:ListBucket"],
        Resource = "arn:aws:s3:::${var.images_bucket}"
      },
      {
        Sid      = "ReadObjects",
        Effect   = "Allow",
        Action   = ["s3:GetObject"],
        Resource = "arn:aws:s3:::${var.images_bucket}/*"
      }
    ]
  })
}

# ARN efectivo del role (si no se creó, usa el pasado por variable)
locals {
  lambda_role_arn = element(concat(aws_iam_role.lambda_exec[*].arn, [var.lambda_exec_role_arn]), 0)
}

#########################
# Empaquetado (zip) y build opcional con Docker
#########################

# Crea carpeta build/
resource "null_resource" "ensure_build_dir" {
  provisioner "local-exec" {
    command = "mkdir -p ${path.module}/build"
  }
  triggers = { always = timestamp() }
}

# Instala requirements.txt dentro de cada carpeta (opcional con Docker SAM)
resource "null_resource" "images_pip" {
  triggers = { use = tostring(var.use_docker_packaging) }
  provisioner "local-exec" {
    when    = create
    command = var.use_docker_packaging ? "docker run --rm -v ${path.module}/lambdas/images_handler:/var/task ${local.sam_image} /bin/bash -lc 'if [ -f requirements.txt ]; then pip install -r requirements.txt -t /var/task; fi'" : "echo skip"
  }
}

resource "null_resource" "students_pip" {
  triggers = { use = tostring(var.use_docker_packaging) }
  provisioner "local-exec" {
    when    = create
    command = var.use_docker_packaging ? "docker run --rm -v ${path.module}/lambdas/students_writer:/var/task ${local.sam_image} /bin/bash -lc 'if [ -f requirements.txt ]; then pip install -r requirements.txt -t /var/task; fi'" : "echo skip"
  }
}

resource "null_resource" "db_init_pip" {
  triggers = { use = tostring(var.use_docker_packaging) }
  provisioner "local-exec" {
    when    = create
    command = var.use_docker_packaging ? "docker run --rm -v ${path.module}/lambdas/db_init:/var/task ${local.sam_image} /bin/bash -lc 'if [ -f requirements.txt ]; then pip install -r requirements.txt -t /var/task; fi'" : "echo skip"
  }
}

# Zips
data "archive_file" "images_zip" {
  depends_on  = [null_resource.ensure_build_dir, null_resource.images_pip]
  type        = "zip"
  source_dir  = "${path.module}/lambdas/images_handler"
  output_path = "${path.module}/build/images_handler.zip"
}

data "archive_file" "students_zip" {
  depends_on  = [null_resource.ensure_build_dir, null_resource.students_pip]
  type        = "zip"
  source_dir  = "${path.module}/lambdas/students_writer"
  output_path = "${path.module}/build/students_writer.zip"
}

data "archive_file" "db_init_zip" {
  depends_on  = [null_resource.ensure_build_dir, null_resource.db_init_pip]
  type        = "zip"
  source_dir  = "${path.module}/lambdas/db_init"
  output_path = "${path.module}/build/db_init.zip"
}

#########################
# Log groups
#########################

resource "aws_cloudwatch_log_group" "images" {
  name              = "/aws/lambda/${local.name_prefix}-images-handler"
  retention_in_days = var.log_retention_in_days
  tags              = var.enable_lambda_tags ? local.tags : {}
}

resource "aws_cloudwatch_log_group" "students" {
  name              = "/aws/lambda/${local.name_prefix}-students-writer"
  retention_in_days = var.log_retention_in_days
  tags              = var.enable_lambda_tags ? local.tags : {}
}

resource "aws_cloudwatch_log_group" "dbinit" {
  name              = "/aws/lambda/${local.name_prefix}-db-init"
  retention_in_days = var.log_retention_in_days
  tags              = var.enable_lambda_tags ? local.tags : {}
}

#########################
# Lambdas (handler = app.handler)
#########################

# Helper para VPC config (usa tus subnets privadas y el SG de lambdas)
locals {
  lambda_subnets = module.vpc.private_subnets
  lambda_sg_ids  = [aws_security_group.lambdas.id]
}

# Images Handler
resource "aws_lambda_function" "images" {
  function_name = "${local.name_prefix}-images-handler"
  role          = local.lambda_role_arn
  handler       = "app.handler"
  runtime       = var.lambda_runtime
  architectures = var.lambda_architectures
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory

  filename         = data.archive_file.images_zip.output_path
  source_code_hash = data.archive_file.images_zip.output_base64sha256

  dynamic "vpc_config" {
    for_each = length(local.lambda_subnets) > 0 ? [1] : []
    content {
      subnet_ids         = local.lambda_subnets
      security_group_ids = local.lambda_sg_ids
    }
  }

  # Publica bucket/prefijo por defecto + permite overrides con var.images_env
  environment {
    variables = merge(
      {
        S3_BUCKET = var.images_bucket
        S3_PREFIX = "images" # tus objetos están en s3://bucket/images/ (ajusta si cambiaste)
      },
      var.images_env
    )
  }

  tags       = var.enable_lambda_tags ? local.tags : {}
  depends_on = [aws_cloudwatch_log_group.images]
  publish    = true
}

# Students Writer
resource "aws_lambda_function" "students" {
  function_name = "${local.name_prefix}-students-writer"
  role          = local.lambda_role_arn
  handler       = "app.handler"
  runtime       = var.lambda_runtime
  architectures = var.lambda_architectures
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory

  filename         = data.archive_file.students_zip.output_path
  source_code_hash = data.archive_file.students_zip.output_base64sha256

  dynamic "vpc_config" {
    for_each = length(local.lambda_subnets) > 0 ? [1] : []
    content {
      subnet_ids         = local.lambda_subnets
      security_group_ids = local.lambda_sg_ids
    }
  }

  environment { variables = var.students_env }

  tags       = var.enable_lambda_tags ? local.tags : {}
  depends_on = [aws_cloudwatch_log_group.students]
  publish    = true
}

# DB Init
resource "aws_lambda_function" "db_init" {
  function_name = "${local.name_prefix}-db-init"
  role          = local.lambda_role_arn
  handler       = "app.handler"
  runtime       = var.lambda_runtime
  architectures = var.lambda_architectures
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory

  filename         = data.archive_file.db_init_zip.output_path
  source_code_hash = data.archive_file.db_init_zip.output_base64sha256

  dynamic "vpc_config" {
    for_each = length(local.lambda_subnets) > 0 ? [1] : []
    content {
      subnet_ids         = local.lambda_subnets
      security_group_ids = local.lambda_sg_ids
    }
  }

  environment { variables = var.db_init_env }

  tags       = var.enable_lambda_tags ? local.tags : {}
  depends_on = [aws_cloudwatch_log_group.dbinit]
  publish    = true
}

#########################
# Outputs
#########################

output "lambda_arns" {
  value = {
    images   = aws_lambda_function.images.arn
    students = aws_lambda_function.students.arn
    db_init  = aws_lambda_function.db_init.arn
  }
}
