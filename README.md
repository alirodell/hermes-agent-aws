# Hermes Agent on AWS

Terraform and scripts for running a personal AI agent ([Hermes Agent](https://github.com/NousResearch/hermes-agent)) 24/7 on AWS: on infrastructure you own, with all durable data in your own S3 bucket and secrets in Secrets Manager.

Resource names use the `name` variable as a prefix (default `hermes-agent`); `<name>` below stands for it.

## What gets deployed (us-east-1)

| Resource | Purpose |
|---|---|
| EC2 `t3a.medium` (x86_64, 4 GiB, Amazon Linux 2023) | Runs Hermes (`hermes gateway run`: messaging + cron scheduler) and the signal-cli daemon as systemd services. x86 because signal-cli only ships its native library for x86_64 Linux. CPU credits in `standard` mode, so there are no surprise surplus charges |
| Encrypted gp3 root volume (30 GB, AWS-managed `aws/ebs` key) | Local disk; daily snapshots via Data Lifecycle Manager (keep 7) |
| S3 bucket `<name>-data-<account-id>-us-east-1` | Source of truth: versioned, SSE-S3 encryption, public access blocked, TLS-only |
| Secrets Manager `<name>/hermes-env` (AWS-managed key) | API keys as JSON, written to `~/.hermes/.env` (`chmod 600`) each time the agent starts |
| IAM instance role | Access to this bucket, this one secret, and SSM. Nothing else |
| Security group | **No inbound rules.** Outbound 80/443 only (OpenRouter, Signal, Telegram, AWS APIs all use 443) |
| AWS Budget | Email at 80% actual and 100% forecast of the monthly limit (account-wide) |

Encryption at rest uses AWS-managed keys only (SSE-S3, `aws/ebs`, `aws/secretsmanager`). There is no customer-managed key to delete, disable or misconfigure, so you can't lock yourself out through encryption. Anyone with IAM access to the bucket, volume or secret in this account can read it, and IAM is the only gate.

Access goes through **SSM Session Manager** only. There is no SSH, no key pair, and no open ports.

### Layout on the instance

```
/home/hermes/.hermes/        HERMES_HOME: config.yaml, .env, skills/, memories, sessions, cron
/home/hermes/.hermes/skills/claude-code-imports/   skills pushed from this laptop (laptop-only skills)
/home/hermes/work/           scratch/output dir for jobs (synced to S3)
/home/hermes/.local/share/signal-cli/   Signal device keys + state (synced to S3)
/opt/signal-cli/             signal-cli install (pinned version, checksum-verified)
/etc/hermes-agent/env        bucket/secret/region (non-secret)
/usr/local/sbin/hermes-sync            push | pull | pull-imports
/usr/local/sbin/hermes-fetch-secrets   Secrets Manager -> ~/.hermes/.env (+ gh login from GH_TOKEN)
/usr/local/sbin/signal-link            one-time QR device linking
/usr/local/sbin/hermes-google-oauth    Google OAuth files <-> Secrets Manager (save|restore|status|clear)
/var/log/agent-bootstrap.log           first-boot log
```

systemd units:
- `hermes-agent.service`: the agent. Restarts on failure and refreshes secrets on every start.
- `signal-cli.service`: `signal-cli daemon --http 127.0.0.1:8080` (loopback only, Java heap capped at 512 MB). It starts only once a device has been linked.
- `hermes-backup.timer`: runs `hermes-sync push` every 15 minutes. `~/.hermes`, `~/work` and signal-cli state go to S3. `.env`, sockets, the code checkout (`hermes-agent/`), runtimes (`installs/`, `tools/`), `cache/` and logs are excluded, in both directions, so a rebuild never restores a stale runtime. `aws s3 sync` exit code 2 (skipped sockets) counts as success.
- `hermes-backup-on-shutdown.service`: runs one last sync on stop or terminate, after the agent and signal-cli have exited.

**Memory caps.** The box has 4 GiB of RAM plus 2 GiB of swap. The pieces that can run away are capped, so going over the limit kills just that process. Without caps, the whole machine swaps itself into a standstill, and SSM, and with it your access, stops responding.

| Group | RAM / swap cap | Over the cap |
|---|---|---|
| `hermes-agent.service` (normal use ~450 MiB) | `agent_memory_max_mb` (1536) / 256 MiB | Killed; systemd restarts it in 30s |
| Everything you run as `hermes` via `connect.sh` (`user-<uid>.slice`), combined | `session_memory_max_mb` (1536) / 256 MiB | The biggest process in your session is killed |
| `signal-cli.service` | 768 MiB / 128 MiB | Killed and restarted |

Check usage with `systemd-cgtop -m`, or with `cat /sys/fs/cgroup/system.slice/hermes-agent.service/memory.peak`. **Don't paste large blobs** (base64 screenshots, big files) into the Hermes terminal UI. Copy files to the box instead (see [Moving files to the box](#moving-files-to-the-box)) and point Hermes at the path.

## Prerequisites

Do these once, before the first `terraform apply`.

### 1. AWS account
- Use a **personal** AWS account (not an employer one). Turn on **MFA for the root user**, store the root credentials somewhere safe, and stop using root day to day.
- Create an admin identity for deploying: either IAM Identity Center (SSO) or an IAM user with `AdministratorAccess` and MFA.
- Make sure `us-east-1` still has its **default VPC**. Check this after installing the CLI (step 2):
  ```bash
  aws ec2 describe-vpcs --region us-east-1 --filters Name=isDefault,Values=true --query 'Vpcs[].VpcId'
  ```
  If that prints `[]`, recreate it:
  ```bash
  aws ec2 create-default-vpc --region us-east-1
  ```

### 2. Laptop tools
Terraform must come from HashiCorp's tap. Homebrew's own `terraform` formula is frozen at 1.5.7, and this repo needs 1.10 or later (native S3 state locking).
```bash
brew tap hashicorp/tap
```
```bash
brew install hashicorp/tap/terraform awscli jq
```
```bash
brew install --cask session-manager-plugin
```
Optional, to render the Signal link QR code locally if the box can't:
```bash
brew install qrencode
```
Check the versions:
```bash
terraform version && aws --version && session-manager-plugin --version
```

### 3. AWS CLI credentials
SSO:
```bash
aws configure sso --profile personal
```
Or an IAM user's access keys:
```bash
aws configure --profile personal
```
Then confirm which account you're in:
```bash
aws sts get-caller-identity --profile personal
```
Set `aws_profile = "personal"` in `terraform/terraform.tfvars`, and run `export AWS_PROFILE=personal` in your shell so the scripts in `scripts/` use the same account.

### 4. Accounts and keys you'll enter after deploy
- **OpenRouter:** create an API key and **set a credit limit** on it. Token spend isn't covered by the AWS Budget.
- **Signal:** your phone with Signal installed, and its number in E.164 format (`+1212…`). The box links as a secondary device; it doesn't register a new number.
- **Telegram (optional):** a bot token from @BotFather and your numeric user ID.

## Deploy

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Edit `terraform.tfvars` and set `budget_alert_emails`.

Terraform state lives in a dedicated S3 bucket, `<name>-tfstate-<account-id>-us-east-1`. It's versioned (one year of history), encrypted, public access blocked, TLS-only, and locked natively during plan/apply via `use_lockfile`. It's kept separate from the agent's data bucket on purpose: the instance role can read and write the data bucket, so the agent must not be able to reach the state.

Create the state bucket once. It's safe to re-run. It also writes `terraform/backend.hcl` (gitignored) with the bucket name, so your account ID never lands in the repo:

```bash
NAME=hermes-agent ./scripts/bootstrap-state-bucket.sh
```

Use the same `NAME` as the `name` variable, if you changed it. If your state bucket already exists under a different name, pass it as `STATE_BUCKET=<bucket>`, so the script doesn't create a new, empty one. Then initialise, passing the backend file and your profile. Terraform remembers both in `terraform/.terraform/` for later runs:

```bash
terraform -chdir=terraform init -backend-config=backend.hcl -backend-config="profile=personal"
```

On another machine, or after deleting `terraform/.terraform/`, re-run the bootstrap script (it only regenerates `backend.hcl`) and the same `init`. The state is already in S3.

```bash
terraform -chdir=terraform apply
```

1. **Confirm the budget emails.** AWS sends a confirmation email to each address.
2. **Store your keys.** Input is hidden and the keys never touch disk. The script then restarts the agent:
   ```bash
   ./scripts/set-secrets.sh
   ```
   Until you run this, `hermes-agent` will retry every 30s and fail. That's expected. Enter your Signal number when asked if you want Signal (see below).
3. **Link Signal** (if you want it):
   ```bash
   ./scripts/link-signal.sh
   ```
4. **Check it's up:**
   ```bash
   ./scripts/connect.sh
   ```
   Then on the box:
   ```bash
   hermes doctor
   ```
   ```bash
   systemctl status hermes-agent signal-cli
   ```
   ```bash
   journalctl -u hermes-agent -f
   ```
   ```bash
   sudo cat /var/log/agent-bootstrap.log
   ```
   Also check that `~/.hermes/config.yaml` has `provider: openrouter` and the model you expect. Change the model with `hermes model`.

Bootstrap takes about 5 minutes after the instance launches. `link-signal.sh` will fail if you run it before bootstrap finishes.

## Skills

**Preferred: install from GitHub with Hermes itself.** On the box:

```bash
hermes skills install <owner>/<repo>/<path-to-skill-dir> --category productivity --yes
```

For example, `my-github-user/my-skills/skills/my-skill`. Hermes security-scans the skill and records its source in `~/.hermes/skills/.hub/lock.json`, so `hermes skills check` and `hermes skills update` work. Nothing else is needed for rebuilds: all of `~/.hermes/skills/`, including the lock file, syncs to S3 and is restored on a new instance. This covers every skill installed this way, now or later.

**Only for skills that exist solely on your laptop** (not in a GitHub repo), push them through S3:

```bash
./scripts/push-skill.sh /path/to/skills/<skill-name>
```

This syncs the directory to `s3://<bucket>/imports/skills/` and pulls it into `~/.hermes/skills/claude-code-imports/` on the box. Imports are re-pulled automatically when the instance is rebuilt. Don't use this for a skill that is also installed with `hermes skills install`, or you'll end up with two copies.

## GitHub access (optional)

The box installs a pinned, checksum-verified `gh` CLI (`gh_cli_version` / `gh_cli_sha256`) at `/usr/local/bin/gh`, and configures git to use `gh auth git-credential` for HTTPS GitHub remotes.

Authentication is not baked in. Create a **fine-grained personal access token** limited to the repos you want the agent to touch (Contents and Pull requests read/write is usually enough; add Workflows only if it should edit Actions files), then run `./scripts/set-secrets.sh` and enter it as `GH_TOKEN`. It's stored in Secrets Manager. On every service start, `hermes-fetch-secrets` runs `gh auth login --with-token` as the `hermes` user, which writes the token to `~/.config/gh/hosts.yml` (mode 600). `gh` and git over HTTPS read it from there. Verify on the box with `gh auth status`.

Why not an environment variable: Hermes classifies `GH_TOKEN` and `GITHUB_TOKEN` as Copilot provider credentials. It scrubs them from every command the agent runs and refuses to forward them even through `terminal.env_passthrough`. So `GH_TOKEN` is deliberately kept **out of** `~/.hermes/.env`. Removing `GH_TOKEN` from the secret logs `gh` out on the next restart.

Consider protecting `main` with a branch rule that requires a pull request. That way the agent's token can propose changes to repos (including this one) but never push to `main` directly.

Clone working repos into `~/work/<repo>`. That directory syncs to S3, so clones (including `.git`) survive a rebuild. Never put credentials in a repo directory.

## Moving files to the box

There's no SSH or scp. Copy files through the data bucket's `work/` prefix, which the backup also uses. Files you put there survive rebuilds:

```bash
aws s3 sync ./my-folder "s3://$(terraform -chdir=terraform output -raw bucket)/work/my-folder/"
```

Then, on the box (`./scripts/connect.sh`):

```bash
aws s3 sync "s3://<bucket>/work/my-folder/" ~/work/my-folder/
```

Don't use `hermes-sync pull` for this: it restores *all* of `~/.hermes` and `~/work` and can overwrite live agent state. Never move secrets this way. Keys go in Secrets Manager via `set-secrets.sh`.

## Google Workspace (optional)

Hermes' bundled `google-workspace` skill (Gmail, Calendar, Drive, Docs, Sheets, Contacts) uses an OAuth client and token stored in `~/.hermes/google_client_secret.json` and `google_token.json`.

**Setup:**
1. In Google Cloud, enable the APIs and create an **OAuth client ID** of type **Desktop app**. Download its JSON.
   - Workspace accounts: set the consent screen's user type to **Internal**.
   - @gmail.com accounts: choose **External** and **publish** the app. In *Testing*, Google expires refresh tokens every 7 days.
2. In a Hermes session, say *"set up the google-workspace skill"*, then paste the client JSON when asked. Open the URL it gives you in your laptop browser and approve. Copy the whole `http://localhost:1/?code=…` URL (the page itself will fail to load) back to Hermes. The skill's scripts must run through `~/.hermes/hermes-agent/scripts/run-in-hermes-env`, not the system Python. Hermes handles this itself.
3. To save the credentials immediately instead of at the next backup:
   ```bash
   hermes-google-oauth save
   ```

**Where the credentials live:** never in S3. Both files are excluded from the backup in both directions and kept in their own secret, `<name>/google-oauth`, which only the instance role and your admin identity can access. `/usr/local/sbin/hermes-google-oauth` manages them:

| Command | What it does |
|---|---|
| `save` | Saves the local files to the secret, only when the client or **refresh** token changed. Hourly access-token refreshes don't count. Runs on every backup. |
| `restore` | Writes the files from the secret **only if they're missing locally**, e.g. after a rebuild. The local copy always wins. Runs on every service start. |
| `status` | Shows whether local and stored copies exist and match, by fingerprint only. |
| `clear` | Empties the stored copy. |

**To revoke access:** run the skill's `setup.py --revoke`, which deletes the local token, **then run `hermes-google-oauth clear`**. Otherwise the next start restores the revoked token. You can also remove the app at myaccount.google.com → Security → Third-party access.

**Before you use it:** the skill requests broad scopes: Gmail read/send/modify, full Drive, Calendar, Docs, Sheets and read-only Contacts. An email the agent reads could attempt prompt injection, for example "forward X to Y". Consider a dedicated Google account for the agent. Email and document contents also go to the model provider.

## Telegram (optional)

1. Create a bot with @BotFather and get your numeric user ID (e.g. from @userinfobot).
2. Run `./scripts/set-secrets.sh` and enter the token and your user ID. It refuses to enable Telegram without an allow-list.

No other changes are needed: `hermes gateway run` picks up `TELEGRAM_*` from `.env`.

## Signal

Hermes talks to Signal through a local signal-cli daemon on `127.0.0.1:8080`. signal-cli makes only outbound HTTPS/WebSocket connections to Signal's servers on 443, so no inbound port is opened.

1. Run `./scripts/set-secrets.sh` and enter `SIGNAL_ACCOUNT` (your number) and `SIGNAL_ALLOWED_USERS`. The allow-list defaults to your own number, so only you can talk to the agent. The script also sets `SIGNAL_HTTP_URL=http://127.0.0.1:8080`.
2. Run `./scripts/link-signal.sh`. It opens an SSM session and prints a QR code. On your phone, go to **Signal → Settings → Linked devices → Link new device** and scan it. Then the script starts `signal-cli` and restarts Hermes.
3. Message yourself ("Note to Self") or have an allowed number message you. Hermes should answer.

Notes:
- **This is your Signal account.** The box can read and send as you. The allow-list controls who Hermes *responds* to, not what signal-cli can see. Unlink it at any time from your phone (Linked devices).
- **Device keys live in S3** (`signal-cli/` prefix: private, versioned, encrypted), so a rebuilt instance comes back already linked. If a rebuild restores stale state and messages fail to decrypt, unlink the device on your phone and run `link-signal.sh` again.
- Signal unlinks devices that stay offline for about 30 days.
- **Upgrades:** Signal deprecates old clients regularly. To bump signal-cli, set `signal_cli_version` and `signal_cli_sha256` in `terraform.tfvars` (get the hash with `curl -sL <release tarball URL> | shasum -a 256`), then apply. That rebuilds the box. Check the release notes for the required Java version, which is currently Java 25.

## Day-2 operations

| Task | How |
|---|---|
| Shell | `./scripts/connect.sh` (lands you as the `hermes` user) |
| Rotate keys | `./scripts/set-secrets.sh` |
| Re-link Signal | `./scripts/link-signal.sh` |
| signal-cli logs | on the box: `journalctl -u signal-cli -f` |
| Force a backup | `./scripts/backup-now.sh` |
| Install a skill | on the box: `hermes skills install <owner>/<repo>/<path>` (see [Skills](#skills)) |
| Update Hermes | on the box: `hermes update`, then `sudo systemctl restart hermes-agent` |
| New AMI / clean rebuild | `./scripts/backup-now.sh`, then `terraform -chdir=terraform apply -replace=aws_instance.agent`. The new box restores `~/.hermes`, `~/work` and signal-cli state from S3 |
| Bigger box (browser tools) | set `instance_type = "t3a.large"` and `install_browser = true`, then apply (this rebuilds the box from S3) |
| Scheduled jobs | use Hermes' built-in cron (runs inside the gateway), or add your own systemd timer |

Changing anything that feeds into user-data (model, install ref, signal-cli version, backup interval, browser flag) **replaces the instance**. That's safe because state is restored from S3. Any unsynced changes from the last ≤15 minutes are covered by the shutdown sync.

Don't run `hermes gateway install`. This repo owns the systemd unit, and Hermes warns about duplicate units.

### What survives a rebuild

| Item | Restored? | How |
|---|---|---|
| `~/.hermes` (config, memories, sessions, cron jobs, scripts, skills incl. `.hub/lock.json`) | Yes | S3 sync, every 15 min and on instance stop |
| `~/work` (including git clones) | Yes | S3 sync |
| signal-cli device keys | Yes | S3 sync |
| API keys | Yes | Secrets Manager, written to `.env` on start |
| Google Workspace OAuth (`google_*.json`) | Yes | Own secret (`<name>/google-oauth`), restored on start if missing. Never in S3 |
| `gh` login (`~/.config/gh/hosts.yml`) | Yes | Recreated from `GH_TOKEN` in Secrets Manager on every start. Never synced to S3 |
| `gh`, Java, signal-cli, Hermes itself | Yes | Reinstalled by the bootstrap (pinned versions) |
| `~/.gitconfig` | Yes | The git credential helper is set by the bootstrap |
| Anything installed ad hoc into `~/.local/bin` or elsewhere outside `~/.hermes` and `~/work` | **No** | Add it to the bootstrap, or it is lost |
| Unsynced changes from the last 15 min or less | Mostly | The final sync covers clean stops; a hard crash can lose them (EBS snapshots are the fallback) |

Cron jobs that call `gh` (for example a skill-sync job) work after a rebuild as long as `GH_TOKEN` is in the secret.

### Restore options
- **S3 object versions:** every synced file keeps 90 days of history (`aws s3api list-object-versions`).
- **EBS snapshots:** daily, 7 kept. Create a volume from a snapshot and attach it to recover anything not in S3.

SQLite files in `~/.hermes` and signal-cli are copied while live, so an S3 copy can occasionally be mid-write. Snapshots and older versions are the fallback.

## Teardown

```bash
./scripts/backup-now.sh
```

```bash
terraform -chdir=terraform destroy
```

`destroy` will **fail on the S3 bucket if it holds objects**. That's deliberate, so the data outlives the infra. To delete everything, empty the bucket (all versions) first. The secret has a 7-day recovery window. DLM snapshots that were already taken are **not** deleted by `destroy`. Remove them in the EC2 console if you no longer want them. The Terraform state bucket isn't managed by Terraform, so `destroy` leaves it, and the final empty state, in place. Delete it by hand (all versions) only once nothing is left to manage.

## Cost (us-east-1, approx.)

| Item | $/mo |
|---|---|
| t3a.medium on-demand, 24/7 | ~27.50 |
| 30 GB gp3 | ~2.40 |
| Public IPv4 | ~3.65 |
| EBS snapshots (incremental) | ~0.50–1.50 |
| Secrets Manager (1 secret) | 0.40 |
| S3 + requests (small) | <1 |
| **Infra total** | **~$35–37** |

The default budget alert is $50/mo. A 1-year Savings Plan or reserved instance cuts compute by about 35–40%. **Model tokens are billed separately by OpenRouter** and are usually the bigger cost, so set a credit limit in your OpenRouter account. The AWS Budget only covers AWS spend.

## Guardrails

- Never commit secrets. `terraform.tfvars`, `.env`, and any local state files are gitignored. Terraform state lives in the admin-only state bucket and holds no secret values.
- No public S3 and no inbound ports.
- Anything the agent reads (files, email, documents) is sent to the model provider (OpenRouter and whichever upstream it routes to). Check OpenRouter's privacy settings (disable providers that train on or retain prompts) before pointing the agent at sensitive documents.
- Don't automate logged-in LinkedIn (or similar) browsing from this box. It violates their ToS, and datacenter IPs get flagged, which puts your real account at risk. Public web search is fine.
