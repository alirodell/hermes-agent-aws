terraform {
  required_version = ">= 1.10" # use_lockfile (native S3 state locking)

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
  }

  # Remote state in a dedicated, admin-only bucket (created by scripts/bootstrap-state-bucket.sh),
  # not the agent's data bucket. State holds resource IDs/ARNs only, no secret values (the secret's
  # value is set out-of-band by scripts/set-secrets.sh). use_lockfile = native S3 locking.
  # Backend blocks can't read variables, so bucket and key come from the gitignored backend.hcl
  # (written by the bootstrap script) and the AWS profile is passed once at init:
  #   terraform -chdir=terraform init -backend-config=backend.hcl -backend-config="profile=personal"
  backend "s3" {
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region  = var.region
  profile = var.aws_profile

  default_tags {
    tags = {
      Project   = var.name
      ManagedBy = "terraform"
      Owner     = "personal"
    }
  }
}
