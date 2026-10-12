output "instance_id" {
  value = aws_instance.agent.id
}

output "bucket" {
  value = aws_s3_bucket.data.id
}

output "secret_id" {
  value = aws_secretsmanager_secret.hermes_env.arn
}

output "google_secret_id" {
  value = aws_secretsmanager_secret.google_oauth.arn
}

output "region" {
  value = var.region
}

output "connect" {
  value = "aws ssm start-session --region ${var.region} --target ${aws_instance.agent.id}"
}
