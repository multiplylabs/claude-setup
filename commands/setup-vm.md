---
description: Set up a fresh seahorse GPU dev VM end to end (browser-auth GitHub + AWS SSO, no pasted secrets)
allowed-tools: Bash, Read, Write, Edit
---

# Set up a fresh seahorse dev VM

You are running **on a freshly provisioned GCP dev VM** (Ubuntu 22.04, NVIDIA T4 GPU) to set up
the Multiply Labs `seahorse` project. Work through the steps below **in order**, using `Bash`.

A human is present at the keyboard and will approve the browser-based logins when you prompt them.
**Pause and wait** for them at each login — do not try to automate or skip the browser step.

## Ground rules (read first)

- **Never print or echo credentials.** Do not run bare `gh auth token`, bare
  `aws configure export-credentials`, `env`, `printenv`, or `cat` on any file under `~/.aws/`.
  When you need a secret in a variable, capture it with command substitution so it never reaches
  stdout: `export GITHUB_TOKEN=$(gh auth token)`. Feed secrets to programs via env vars or stdin,
  never as visible command arguments.
- **No permanent tokens.** GitHub and AWS are authenticated only through their browser flows.
  Nothing is pasted.
- **Each Bash call is a fresh shell.** Environment variables, `export`s, and `PATH` changes do
  **not** persist between separate Bash tool calls. So: (a) put `export PATH="$HOME/.pixi/bin:$PATH"`
  at the top of every call that uses `pixi`/`gh`/`aws`, and (b) any step that sets a credential env
  var must run the program that needs it in the **same** Bash call (see Step 5).
- **The browser logins block while you wait.** `gh auth login --web` and `aws sso login` do not
  return until the user finishes approving in their browser. Run each with a **long Bash timeout
  (~300000 ms / 5 min)** so the call isn't killed mid-login, and immediately relay the one-time code
  and URL to the user before you start waiting.
- **If a step fails, stop and fix it** before continuing — read the error, diagnose, re-run just the
  failed part. Do not blindly proceed.

## Step 1 — Install pixi and CLI tools (`gh`, `git`, `jq`)

```bash
curl -fsSL https://pixi.sh/install.sh | sh
export PATH="$HOME/.pixi/bin:$PATH"
pixi global install gh git jq
```

Then verify (re-export PATH in this call): `pixi --version && gh --version && git --version && jq --version`.
(`jq` is the statusline's runtime dependency — see Step 6.)

## Step 2 — Authenticate GitHub (browser, no token)

Start the browser device flow. This is interactive — it prints a one-time code and a URL:

```bash
export PATH="$HOME/.pixi/bin:$PATH"
gh auth login --hostname github.com --git-protocol https --web -s read:packages
```

Tell the user: **"A one-time code is shown above — open the URL on your laptop, paste the code, and
approve. I'll wait."** After it completes, run `gh auth setup-git` and confirm with `gh auth status`.

## Step 3 — Clone seahorse

```bash
export PATH="$HOME/.pixi/bin:$PATH"
if [ -d "$HOME/seahorse/.git" ]; then
  git -C "$HOME/seahorse" pull --ff-only
else
  # TEMPORARY: testing against the unmerged seahorse PR branch (scripts/vm/ reorg, PR #273).
  # After that PR merges, drop the `-- --branch ...` so this clones the default branch again.
  gh repo clone multiplylabs/seahorse "$HOME/seahorse" -- --branch worktree-update-vm-setup-instructions
fi
```

## Step 4 — Authenticate AWS via SSO (browser)

The non-secret SSO profile lives in the private repo at `~/seahorse/scripts/vm/aws_sso_profile.conf`.
Append it to `~/.aws/config` only if a `[profile Seahorse]` block isn't already present, then log in:

```bash
export PATH="$HOME/.pixi/bin:$PATH"
mkdir -p "$HOME/.aws"
touch "$HOME/.aws/config"
if ! grep -q '\[profile Seahorse\]' "$HOME/.aws/config"; then
  printf '\n' >> "$HOME/.aws/config"
  cat "$HOME/seahorse/scripts/vm/aws_sso_profile.conf" >> "$HOME/.aws/config"
fi
aws sso login --profile Seahorse
```

Tell the user: **"Approve the AWS SSO login in your browser. I'll wait."**

## Step 5 — Run the tested setup script

`~/seahorse/scripts/vm/setup_vm.sh` does the heavy lifting (Docker, NVIDIA libs, global tools, ghcr
login, `dvc pull`, `pixi install`). It expects `GITHUB_TOKEN` and AWS credentials in the environment.
Provide them from the sessions you just authenticated — **all in a single Bash call** (env vars don't
persist between calls) and **without ever printing them**:

```bash
export PATH="$HOME/.pixi/bin:$PATH"
export GITHUB_TOKEN=$(gh auth token)
eval "$(aws configure export-credentials --profile Seahorse --format env)"
bash "$HOME/seahorse/scripts/vm/setup_vm.sh"
```

Watch the output. Transient `apt`/network failures are common — if a step fails, fix it and re-run
`setup_vm.sh`. It is safe to re-run: it skips existing installs and fast-forwards the clone.

## Step 6 — Configure the Claude statusline

Install the shared statusline so this VM's `claude` shows folder / branch / model / context-usage /
rate-limit segments. The script is fetched from the public `claude-setup` repo and needs only `jq`
(installed in Step 1). Write it into the active Claude config dir, then merge the `statusLine` setting
into `settings.json` without disturbing existing keys:

```bash
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
mkdir -p "$CFG"
curl -fsSL https://raw.githubusercontent.com/multiplylabs/claude-setup/main/statusline/statusline-command.sh \
  -o "$CFG/statusline-command.sh"
python3 - "$CFG" <<'PY'
import json, os, sys
cfg = sys.argv[1]
path = os.path.join(cfg, "settings.json")
try:
    with open(path) as f:
        data = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    data = {}
data["statusLine"] = {
    "type": "command",
    "command": f"sh {os.path.join(cfg, 'statusline-command.sh')}",
}
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
print("statusLine configured in", path)
PY
```

The statusline appears the next time the user launches `claude` on the VM.

## Step 7 — Report completion

Tell the user setup is complete, and that in their SSH session they should:

- `source ~/.bashrc` (puts `pixi` and `claude` on `PATH`), then `cd ~/seahorse`.
- For rootless Docker: `newgrp docker` (this session only) or reconnect SSH (permanent).

Then they can start working — e.g. `pixi run test-visuomotor-cpu`.
