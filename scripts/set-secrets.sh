#!/usr/bin/env bash
# Prompt for API keys and messaging settings and store them as one JSON secret in Secrets Manager,
# then restart the services so they pick them up. Hidden values never touch disk or shell history.
# Re-running replaces the whole secret — re-enter anything you want to keep.
source "$(dirname "$0")/_common.sh"

read -rsp "OPENROUTER_API_KEY: " OPENROUTER_API_KEY; echo
[ -n "$OPENROUTER_API_KEY" ] || { echo "OPENROUTER_API_KEY is required" >&2; exit 1; }

read -rsp "TELEGRAM_BOT_TOKEN (blank to skip): " TELEGRAM_BOT_TOKEN; echo
TELEGRAM_ALLOWED_USERS=""
if [ -n "$TELEGRAM_BOT_TOKEN" ]; then
  read -rp "TELEGRAM_ALLOWED_USERS (your numeric Telegram user ID, comma-separated): " TELEGRAM_ALLOWED_USERS
  [ -n "$TELEGRAM_ALLOWED_USERS" ] || { echo "Refusing to enable Telegram with no allow-list" >&2; exit 1; }
fi

read -rsp "GH_TOKEN (fine-grained GitHub token for gh/git, scoped to the repos you want; blank to skip): " GH_TOKEN; echo

read -rp "SIGNAL_ACCOUNT (the phone number you'll link, E.164 e.g. +12125550123; blank to skip): " SIGNAL_ACCOUNT
SIGNAL_ALLOWED_USERS=""
SIGNAL_HTTP_URL=""
if [ -n "$SIGNAL_ACCOUNT" ]; then
  [[ "$SIGNAL_ACCOUNT" =~ ^\+[1-9][0-9]{6,14}$ ]] || { echo "SIGNAL_ACCOUNT must be E.164, e.g. +12125550123" >&2; exit 1; }
  read -rp "SIGNAL_ALLOWED_USERS (who may message the agent: E.164 numbers or UUIDs, comma-separated) [$SIGNAL_ACCOUNT]: " SIGNAL_ALLOWED_USERS
  SIGNAL_ALLOWED_USERS="${SIGNAL_ALLOWED_USERS:-$SIGNAL_ACCOUNT}"
  SIGNAL_HTTP_URL="http://127.0.0.1:8080"
fi

export OPENROUTER_API_KEY GH_TOKEN TELEGRAM_BOT_TOKEN TELEGRAM_ALLOWED_USERS SIGNAL_ACCOUNT SIGNAL_ALLOWED_USERS SIGNAL_HTTP_URL
jq -n '{
  OPENROUTER_API_KEY: env.OPENROUTER_API_KEY,
  GH_TOKEN: env.GH_TOKEN,
  TELEGRAM_BOT_TOKEN: env.TELEGRAM_BOT_TOKEN,
  TELEGRAM_ALLOWED_USERS: env.TELEGRAM_ALLOWED_USERS,
  SIGNAL_ACCOUNT: env.SIGNAL_ACCOUNT,
  SIGNAL_ALLOWED_USERS: env.SIGNAL_ALLOWED_USERS,
  SIGNAL_HTTP_URL: env.SIGNAL_HTTP_URL
} | with_entries(select(.value != ""))' \
  | aws secretsmanager put-secret-value --region "$REGION" --secret-id "$SECRET_ID" \
      --secret-string file:///dev/stdin --query VersionId --output text

echo "Secret updated. Restarting services..."
# signal-cli is skipped automatically until a device has been linked (scripts/link-signal.sh).
ssm_run "systemctl restart signal-cli hermes-agent; sleep 5; systemctl is-active hermes-agent"
