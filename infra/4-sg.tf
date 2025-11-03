# ALB
resource "aws_security_group" "alb" {
  name   = "${var.project}-${var.environment}-alb-sg"
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# EC2 web (detrás del ALB)
resource "aws_security_group" "web" {
  name   = "${var.project}-${var.environment}-web-sg"
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # Sin SSH abierto (se usa SSM). Nota del enunciado. 
  # :contentReference[oaicite:16]{index=16}

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Lambdas en VPC
resource "aws_security_group" "lambdas" {
  name   = "${var.project}-${var.environment}-lambda-sg"
  vpc_id = module.vpc.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# RDS Postgres (puerto 9876) - recibe de Lambdas y EC2 web
resource "aws_security_group" "rds" {
  name   = "${var.project}-${var.environment}-rds-sg"
  vpc_id = module.vpc.vpc_id

  # Interno desde lambdas y web
  ingress {
    from_port       = 9876
    to_port         = 9876
    protocol        = "tcp"
    security_groups = [aws_security_group.lambdas.id, aws_security_group.web.id]
  }

  # Opcional: acceso externo restringido si lo pides
  dynamic "ingress" {
    for_each = var.rds_public_access ? var.db_allowed_cidrs : []
    content {
      from_port   = 9876
      to_port     = 9876
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
      description = "External allowed CIDR to RDS:9876"
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
