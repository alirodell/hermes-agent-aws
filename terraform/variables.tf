variable "name" {
  description = "Prefix for all resource names."
  type        = string
  default     = "hermes-agent"
}

variable "region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "AWS CLI profile to deploy with (null = default credential chain)."
  type        = string
  default     = null
}

variable "instance_type" {
  description = "x86_64 instance type (signal-cli only ships its native lib for x86_64 Linux). 4 GiB covers Hermes + the signal-cli JVM."
  type        = string
  default     = "t3a.medium"
}

variable "root_volume_gb" {
  description = "Encrypted gp3 root volume size."
  type        = number
  default     = 30
}

variable "install_browser" {
  description = "Install Hermes' Playwright/Chromium browser tooling. Adds memory pressure alongside signal-cli; consider t3a.large."
  type        = bool
  default     = false
}

variable "openrouter_model" {
  description = "Default OpenRouter model ID written to config.yaml on first boot (must have >=64K context)."
  type        = string
  default     = "~anthropic/claude-sonnet-latest"
}

variable "hermes_install_ref" {
  description = "Git branch of hermes-agent to install. Pin to a tag/commit for reproducible rebuilds."
  type        = string
  default     = "main"
}

variable "signal_cli_version" {
  description = "signal-cli release to install (JVM build). Requires Java 25."
  type        = string
  default     = "0.14.9"
}

variable "signal_cli_sha256" {
  description = "SHA-256 of signal-cli-<version>.tar.gz. Update together with signal_cli_version."
  type        = string
  default     = "c32b87f587198cbd277c9d71228716ee6047ee2b63e8e88728e8280d9407d65a"
}

variable "gh_cli_version" {
  description = "GitHub CLI (gh) release to install."
  type        = string
  default     = "2.102.0"
}

variable "gh_cli_sha256" {
  description = "SHA-256 of gh_<version>_linux_amd64.tar.gz (from the release's checksums.txt). Update together with gh_cli_version."
  type        = string
  default     = "bb766f710eef8ede859c18578c72c327597cd4c8a85b06001b1f3843c6019386"
}

variable "agent_memory_max_mb" {
  description = "Memory cap (MiB) for the hermes-agent service. Over it, the service is OOM-killed and restarted rather than swapping the box to a halt. Normal use is ~450 MiB."
  type        = number
  default     = 1536
}

variable "session_memory_max_mb" {
  description = "Combined memory cap (MiB) for everything the hermes user runs interactively (connect.sh sessions). A runaway session is OOM-killed; SSM and the agent stay up."
  type        = number
  default     = 1536
}

variable "backup_interval" {
  description = "systemd OnCalendar expression for syncing agent state to S3."
  type        = string
  default     = "*:0/15"
}

variable "snapshot_retain_count" {
  description = "Number of daily EBS snapshots to keep."
  type        = number
  default     = 7
}

variable "noncurrent_version_days" {
  description = "Days to keep old S3 object versions before expiring them."
  type        = number
  default     = 90
}

variable "monthly_budget_usd" {
  description = "AWS Budgets monthly limit (account-wide)."
  type        = number
  default     = 50
}

variable "budget_alert_emails" {
  description = "Emails that receive budget alerts."
  type        = list(string)
}
