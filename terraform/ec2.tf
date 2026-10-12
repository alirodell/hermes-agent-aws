data "aws_ssm_parameter" "al2023_x86_64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_instance" "agent" {
  ami                         = data.aws_ssm_parameter.al2023_x86_64.value
  instance_type               = var.instance_type
  subnet_id                   = sort(data.aws_subnets.default.ids)[0]
  vpc_security_group_ids      = [aws_security_group.instance.id]
  iam_instance_profile        = aws_iam_instance_profile.instance.name
  associate_public_ip_address = true

  # Burstable "standard" mode: CPU is throttled at baseline when credits run out instead of
  # silently billing for surplus credits ("unlimited" is the t3/t3a default).
  credit_specification {
    cpu_credits = "standard"
  }

  metadata_options {
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 1
    http_endpoint               = "enabled"
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_gb
    encrypted             = true # AWS-managed aws/ebs key; snapshots inherit it
    delete_on_termination = true # S3 + DLM snapshots are the backups
    tags = {
      Name     = "${var.name}-root"
      Snapshot = var.name
    }
  }

  # Gzipped: the rendered script exceeds EC2's 16 KB raw user-data limit. cloud-init on AL2023
  # detects and decompresses gzip user-data transparently.
  user_data_base64 = base64gzip(templatefile("${path.module}/templates/user-data.sh.tftpl", {
    region                = var.region
    bucket                = aws_s3_bucket.data.id
    secret_id             = aws_secretsmanager_secret.hermes_env.arn
    google_secret_id      = aws_secretsmanager_secret.google_oauth.arn
    openrouter_model      = var.openrouter_model
    install_browser       = var.install_browser
    install_ref           = var.hermes_install_ref
    backup_interval       = var.backup_interval
    signal_version        = var.signal_cli_version
    signal_sha256         = var.signal_cli_sha256
    gh_version            = var.gh_cli_version
    gh_sha256             = var.gh_cli_sha256
    agent_memory_max_mb   = var.agent_memory_max_mb
    session_memory_max_mb = var.session_memory_max_mb
  }))

  # Changing user-data rebuilds the box from S3 state. Safe by design; see README.
  user_data_replace_on_change = true

  tags = {
    Name = var.name
  }

  lifecycle {
    # Don't replace the instance every time AWS publishes a new AMI. Run `terraform apply -replace=aws_instance.agent` to pick one up.
    ignore_changes = [ami]
  }

  depends_on = [aws_iam_role_policy.instance]
}
