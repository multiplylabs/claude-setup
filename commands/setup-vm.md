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
- **The browser logins block, and their code/URL won't surface until you fetch it.** `gh auth login
  --web` and `aws sso login` don't return until the user approves, and the Bash tool won't show a
  command's output until it exits. So **run each login as a background command** (prefix `aws` with
  `PYTHONUNBUFFERED=1`) and **read that background command's own output** every ~2 seconds until the
  code and URL appear (within seconds), then relay them to the user immediately. Read the background
  command's output stream directly — do **not** redirect it into a scratch/temp directory that may not
  exist yet (the redirect fails and the login never starts); if you must redirect, use a path under
  `$HOME` and `mkdir -p` its directory first. Never run a login in the foreground on a long timeout —
  that makes the user wait out the whole timeout before the code appears.
- **If a step fails, stop and fix it** before continuing — read the error, diagnose, re-run just the
  failed part. Do not blindly proceed.

## Step 1 — Install pixi and CLI tools (`gh`, `git`, `jq`)

```bash
curl -fsSL https://pixi.sh/install.sh | sh
export PATH="$HOME/.pixi/bin:$PATH"
pixi global install gh git jq awscli
```

Then verify (re-export PATH in this call): `pixi --version && gh --version && git --version && jq --version`.
(`jq` is the statusline's runtime dependency — see Step 6.)

## Step 2 — Authenticate GitHub (browser, no token)

Start the browser device flow. This is interactive — it prints a one-time code and a URL:

```bash
export PATH="$HOME/.pixi/bin:$PATH"
gh auth login --hostname github.com --git-protocol https --web -s read:org,read:packages,write:packages,workflow
```

Scopes: `repo` (default) + `read:org` for cloning and org access; `read:packages`/`write:packages`
to pull and push `ghcr` images; `workflow` to push commits that touch `.github/workflows/`.

Tell the user: **"A one-time code is shown above — open the URL on your laptop, paste the code, and
approve. I'll wait."** After it completes, run `gh auth setup-git` and confirm with `gh auth status`.

## Step 3 — Clone seahorse

```bash
export PATH="$HOME/.pixi/bin:$PATH"
if [ -d "$HOME/seahorse/.git" ]; then
  git -C "$HOME/seahorse" pull --ff-only
else
  gh repo clone multiplylabs/seahorse "$HOME/seahorse" -- --depth 1
fi
```

## Step 4 — Authenticate AWS via SSO (browser)

The non-secret SSO profile lives in the private repo at `~/seahorse/scripts/vm/aws_sso_profile.conf`.
First append it to `~/.aws/config` only if a `[profile Seahorse]` block isn't already present:

```bash
export PATH="$HOME/.pixi/bin:$PATH"
mkdir -p "$HOME/.aws"
touch "$HOME/.aws/config"
if ! grep -q '\[profile Seahorse\]' "$HOME/.aws/config"; then
  printf '\n' >> "$HOME/.aws/config"
  cat "$HOME/seahorse/scripts/vm/aws_sso_profile.conf" >> "$HOME/.aws/config"
fi
```

Then log in with the **device-code** flow (the VM is headless — no local browser to open):

```bash
export PATH="$HOME/.pixi/bin:$PATH"
PYTHONUNBUFFERED=1 aws sso login --profile Seahorse --use-device-code
```

Run that login **in the background** (per the ground rules): poll its output every ~2 seconds until the
verification URL and `XXXX-XXXX` code appear, then relay both at once — **"Open <URL>, enter code
<XXXX-XXXX>, and approve. I'll wait."** — and keep waiting until the login process exits successfully.

## Step 5 — Run the tested setup script

`~/seahorse/scripts/vm/setup_vm.sh` does the heavy lifting (Docker, NVIDIA libs, global tools, ghcr
login, `pixi install`; it verifies DVC but does not pull data). It expects `GITHUB_TOKEN` and AWS
credentials in the environment.
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
