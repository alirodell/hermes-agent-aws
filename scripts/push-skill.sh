#!/usr/bin/env bash
# Upload a local Claude skill directory (one containing SKILL.md) to the bucket and
# pull it into ~/.hermes/skills/claude-code-imports/<name>/ on the instance.
#
#   scripts/push-skill.sh ~/.claude/skills/my-skill
source "$(dirname "$0")/_common.sh"

SRC="${1:?usage: push-skill.sh <skill-dir>}"
SRC="${SRC%/}"
[ -f "$SRC/SKILL.md" ] || { echo "$SRC has no SKILL.md" >&2; exit 1; }
NAME="$(basename "$SRC")"

aws s3 sync "$SRC" "s3://$BUCKET/imports/skills/$NAME/" --region "$REGION" --delete \
  --exclude ".DS_Store" --exclude ".git/*" --only-show-errors
echo "Uploaded $NAME. Pulling onto the instance..."
ssm_run "sudo -u hermes -H /usr/local/sbin/hermes-sync pull-imports && ls /home/hermes/.hermes/skills/claude-code-imports/"
