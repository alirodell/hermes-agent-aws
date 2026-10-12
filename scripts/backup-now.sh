#!/usr/bin/env bash
# Trigger an immediate S3 sync of agent state (e.g. before `terraform apply -replace`).
source "$(dirname "$0")/_common.sh"
ssm_run "systemctl start hermes-backup.service && echo synced"
