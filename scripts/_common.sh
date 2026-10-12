# Shared helpers: read Terraform outputs. Sourced by the other scripts.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$REPO_ROOT/terraform"
tf_out() { terraform -chdir="$TF_DIR" output -raw "$1"; }
REGION="$(tf_out region)"
INSTANCE_ID="$(tf_out instance_id)"
BUCKET="$(tf_out bucket)"
SECRET_ID="$(tf_out secret_id)"

# Run a shell command on the instance (as root) via SSM Run Command and print its status and output.
# Waits until the command finishes (up to SSM_WAIT_SECONDS, default 900) rather than relying on
# `aws ssm wait`, which gives up after ~100s. Returns non-zero unless the command succeeded.
ssm_run() {
  local cmd_id status waited=0 limit="${SSM_WAIT_SECONDS:-900}"
  cmd_id=$(aws ssm send-command --region "$REGION" --instance-ids "$INSTANCE_ID" \
    --document-name AWS-RunShellScript \
    --parameters "$(jq -n --arg c "$1" --arg t "$limit" '{commands: [$c], executionTimeout: [$t]}')" \
    --query Command.CommandId --output text)
  while :; do
    status=$(aws ssm get-command-invocation --region "$REGION" --command-id "$cmd_id" \
      --instance-id "$INSTANCE_ID" --query Status --output text 2>/dev/null || echo Pending)
    case "$status" in Pending|InProgress|Delayed) ;; *) break ;; esac
    if [ "$waited" -ge "$limit" ]; then
      echo "Still running after ${limit}s (command $cmd_id); check later with: aws ssm get-command-invocation --command-id $cmd_id --instance-id $INSTANCE_ID" >&2
      return 1
    fi
    sleep 3; waited=$((waited + 3))
  done
  echo "$status"
  aws ssm get-command-invocation --region "$REGION" --command-id "$cmd_id" --instance-id "$INSTANCE_ID" \
    --query StandardOutputContent --output text
  local err
  err=$(aws ssm get-command-invocation --region "$REGION" --command-id "$cmd_id" --instance-id "$INSTANCE_ID" \
    --query StandardErrorContent --output text)
  [ -z "$err" ] || echo "$err" >&2
  [ "$status" = Success ]
}
