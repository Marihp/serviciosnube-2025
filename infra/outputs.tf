output "alb_dns_name" { value = aws_lb.alb.dns_name }
output "api_invoke_url" { value = "https://${aws_api_gateway_rest_api.api.id}.execute-api.${var.aws_region}.amazonaws.com/${aws_api_gateway_stage.prod.stage_name}" }
output "images_bucket" { value = module.images_bucket.s3_bucket_id }
output "rds_endpoint" { value = module.db.db_instance_endpoint }
output "rds_secret_arn" { value = module.db.db_instance_master_user_secret_arn }
