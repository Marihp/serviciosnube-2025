# ALB
resource "aws_security_group" "alb" {
  name   = "${var.project}-${var.environment}-alb-sg"
  vpc_id = module.vpc.vpc_id

  # HTTP
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Public HTTP"
  }

  # HTTPS (opcional si tienes cert en el ALB)
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Public HTTPS"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project}-${var.environment}-alb-sg"
    Project     = var.project
    Environment = var.environment
  }
}

# EC2 web (detrás del ALB, app en 3000)
resource "aws_security_group" "web" {
  name   = "${var.project}-${var.environment}-web-sg"
  vpc_id = module.vpc.vpc_id

  # Solo el ALB puede llegar al puerto 3000
  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
    description     = "Traffic from ALB to app port 3000"
  }

  # Sin SSH (usa SSM)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project}-${var.environment}-web-sg"
    Project     = var.project
    Environment = var.environment
  }
}

# Lambdas en VPC
resource "aws_security_group" "lambdas" {
  name   = "${var.project}-${var.environment}-lambda-sg"
  vpc_id = module.vpc.vpc_id

  # Egresos abiertos (la SG de destino controla el ingreso)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project}-${var.environment}-lambda-sg"
    Project     = var.project
    Environment = var.environment
  }
}

# RDS (puerto tomado de var.rds_port) - recibe de Lambdas y EC2 web
resource "aws_security_group" "rds" {
  name   = "${var.project}-${var.environment}-rds-sg"
  vpc_id = module.vpc.vpc_id

  # Interno desde lambdas y web
  ingress {
    from_port       = var.rds_port
    to_port         = var.rds_port
    protocol        = "tcp"
    security_groups = [aws_security_group.lambdas.id, aws_security_group.web.id]
    description     = "DB access from Lambdas and Web"
  }

  # Opcional: acceso externo restringido si rds_public_access=true
  dynamic "ingress" {
    for_each = var.rds_public_access ? var.db_allowed_cidrs : []
    content {
      from_port   = var.rds_port
      to_port     = var.rds_port
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
      description = "External allowed CIDR to RDS"
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project}-${var.environment}-rds-sg"
    Project     = var.project
    Environment = var.environment
  }
}
