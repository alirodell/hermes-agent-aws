#!/usr/bin/env bash
# Open a shell on the instance via SSM Session Manager (no SSH, no open ports),
# dropped straight into the hermes user. Requires the session-manager-plugin.
source "$(dirname "$0")/_common.sh"
aws ssm start-session --region "$REGION" --target "$INSTANCE_ID" \
  --document-name AWS-StartInteractiveCommand \
  --parameters 'command=["sudo -iu hermes"]'
