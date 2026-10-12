# Encrypted with the AWS-managed aws/secretsmanager key (no kms_key_id = default).
# Container only — Terraform never sees the value. Populate with scripts/set-secrets.sh.
# The secret is a JSON object of env vars, e.g. {"OPENROUTER_API_KEY": "...", "TELEGRAM_BOT_TOKEN": "..."}.
# Every key/value pair is written into ~/.hermes/.env on the instance (chmod 600) each time the agent starts.
resource "aws_secretsmanager_secret" "hermes_env" {
  name                    = local.secret_name
  description             = "Env vars (API keys) for the Hermes agent"
  recovery_window_in_days = 7
}

# Google Workspace OAuth client + token for the google-workspace skill, as
# {"client_secret": {...}, "token": {...}}. Unlike hermes_env, the instance writes this one:
# the token is created on the box during OAuth, and hermes-google-oauth saves it here (when its
# refresh token or client changes) and restores it on start. Kept separate so set-secrets.sh,
# which replaces hermes_env wholesale, can never wipe it.
resource "aws_secretsmanager_secret" "google_oauth" {
  name                    = "${var.name}/google-oauth"
  description             = "Google Workspace OAuth client and token for the Hermes agent"
  recovery_window_in_days = 7
}
