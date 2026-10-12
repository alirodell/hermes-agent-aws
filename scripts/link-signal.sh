#!/usr/bin/env bash
# Link the instance to your Signal account as a secondary device (one time; survives rebuilds via S3).
# Run scripts/set-secrets.sh with SIGNAL_ACCOUNT first. Shows a QR code — scan it from
# Signal on your phone: Settings > Linked devices > Link new device.
source "$(dirname "$0")/_common.sh"
aws ssm start-session --region "$REGION" --target "$INSTANCE_ID" \
  --document-name AWS-StartInteractiveCommand \
  --parameters 'command=["sudo /usr/local/sbin/signal-link HermesAgent"]'
