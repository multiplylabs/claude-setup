---
description: Set up a fresh seahorse dev MacBook end to end (browser-auth GitHub + AWS SSO, no pasted secrets)
allowed-tools: Bash, Read, Write, Edit
---

# Set up a fresh seahorse dev MacBook

You are running **on a fresh Mac** (Apple Silicon, latest macOS) to set up the Multiply
Labs `seahorse` project. Work through the steps below **in order**, using `Bash`.

A human is present at the keyboard and will approve the browser logins **and the macOS GUI
prompts** (Command Line Tools in Step 0, OrbStack in Step 7) when you prompt them.
**Pause and wait** for them at each — do not try to automate or skip these.

## Ground rules (read first)

- **Never print or echo credentials.** Do not run bare `gh auth token`, bare
  `aws configure export-credentials`, `env`, `printenv`, or `cat` on any file under
  `~/.aws/`. When you need a secret in a variable, capture it with command substitution so
  it never reaches stdout: `export GITHUB_TOKEN=$(gh auth token)`. Feed secrets to programs
  via env vars or stdin, never as visible command arguments.
- **No permanent tokens.** GitHub and AWS are authenticated only through their browser
  flows. Nothing is pasted.
- **Each Bash call is a fresh shell.** Environment variables, `export`s, and `PATH` changes
  do **not** persist between separate Bash tool calls. So: (a) put
  `export PATH="$HOME/.pixi/bin:$PATH"` at the top of every call that uses
  `pixi`/`gh`/`aws`, and (b) any step that sets a credential env var must run the program
  that needs it in the **same** Bash call (see Step 7).
- **The browser logins block, and their code/URL won't surface until you fetch it.**
  `gh auth login --web` and `aws sso login` don't return until the user approves, and the
  Bash tool won't show a command's output until it exits. So **run each login as a
  background command** (prefix `aws` with `PYTHONUNBUFFERED=1`) and **read that background
  command's own output** every ~2 seconds until the code and URL appear, then relay them to
  the user immediately. On a Mac the browser usually opens on its own too, but the user
  still needs the one-time code from the terminal. Read the background command's output
  stream directly — do **not** redirect it into a scratch/temp directory that may not exist
  yet; if you must redirect, use a path under `$HOME` and `mkdir -p` its directory first.
  Never run a login in the foreground on a long timeout.
- **If a step fails, stop and fix it** before continuing — read the error, diagnose, re-run
  just the failed part. Do not blindly proceed.

## Step 0 — Ensure Xcode Command Line Tools

A fresh Mac ships neither `python3` (used by Step 1) nor `git` (used by Step 2) until the
Command Line Tools are present. Trigger the install if they're missing:

```bash
xcode-select -p >/dev/null 2>&1 || xcode-select --install
```

If they were already installed this is a no-op and you can move on. Otherwise a macOS
dialog appears — tell the user: **"Click 'Install' in the Command Line Tools dialog and let
it finish (a few minutes). I'll wait."** Then poll `xcode-select -p` (re-running it every
~15 seconds) until it prints a path; do not proceed until it does.

## Step 1 — Install the Claude statusline

Do this first so `claude` shows folder / branch / model / context-usage / rate-limit
segments from the very next launch. The script is fetched from the public `claude-setup`
repo and needs only `python3` (from Step 0); its runtime dependency `jq` is installed in
Step 3. Write it into the active Claude config dir, then merge the `statusLine` setting into
`settings.json` without disturbing existing keys:

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

## Step 2 — Install oh-my-zsh and the shared shell config

zsh is already the default shell on macOS. Install oh-my-zsh non-interactively (without
letting it change the shell, launch zsh, or write its own `~/.zshrc`), clone the two
external plugins, then install the shared `~/.zshrc` (backing up any existing one). The
`.zshrc` is self-adapting and carries **no secrets** — machine-local settings and personal
aliases belong in `~/.zshrc.local`, which it sources if present.

```bash
RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
git clone --depth 1 https://github.com/zsh-users/zsh-autosuggestions \
  "$ZSH_CUSTOM/plugins/zsh-autosuggestions" 2>/dev/null || true
git clone --depth 1 https://github.com/zsh-users/zsh-syntax-highlighting \
  "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" 2>/dev/null || true

[ -f "$HOME/.zshrc" ] && cp "$HOME/.zshrc" "$HOME/.zshrc.bak.$(date +%Y%m%d%H%M%S)"
curl -fsSL https://raw.githubusercontent.com/multiplylabs/claude-setup/main/zsh/zshrc \
  -o "$HOME/.zshrc"

# Make zsh the login shell if it somehow isn't (a no-op on a standard Mac).
case "$SHELL" in */zsh) : ;; *) chsh -s "$(command -v zsh)" ;; esac
```

## Step 3 — Install pixi and CLI tools (`gh`, `git`, `jq`)

```bash
curl -fsSL https://pixi.sh/install.sh | sh
export PATH="$HOME/.pixi/bin:$PATH"
pixi global install gh git jq awscli
```

Then verify (re-export PATH in this call): `pixi --version && gh --version && git --version && jq --version`.
(The full project tool set is installed later by `setup_mac.sh` in Step 7.)

## Step 4 — Authenticate GitHub (browser, no token)

Start the browser flow. It prints a one-time code and, on a Mac, opens the browser for you:

```bash
export PATH="$HOME/.pixi/bin:$PATH"
gh auth login --hostname github.com --git-protocol https --web -s read:org,read:packages,write:packages,workflow
```

Scopes: `repo` (default) + `read:org` for cloning and org access; `read:packages`/`write:packages`
to pull and push `ghcr` images; `workflow` to push commits that touch `.github/workflows/`.

Tell the user: **"A one-time code is shown above — the browser should open; paste the code
and approve. I'll wait."** After it completes, run `gh auth setup-git` and confirm with
`gh auth status`.

## Step 5 — Clone seahorse

```bash
export PATH="$HOME/.pixi/bin:$PATH"
if [ -d "$HOME/seahorse/.git" ]; then
  git -C "$HOME/seahorse" pull --ff-only
else
  gh repo clone multiplylabs/seahorse "$HOME/seahorse" -- --depth 1
fi
```

## Step 6 — Authenticate AWS via SSO (browser)

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

Then log in. Unlike the headless VM, a Mac has a local browser, so **omit `--use-device-code`** —
`aws sso login` opens the approval page directly:

```bash
export PATH="$HOME/.pixi/bin:$PATH"
PYTHONUNBUFFERED=1 aws sso login --profile Seahorse
```

Run that login **in the background** (per the ground rules): poll its output every ~2 seconds
until the verification URL and `XXXX-XXXX` code appear, then relay both — **"Your browser should
open; confirm the code is <XXXX-XXXX> and approve. I'll wait."** — and keep waiting until the
login process exits successfully.

## Step 7 — Run the tested setup script

`~/seahorse/scripts/vm/setup_mac.sh` does the heavy lifting (OrbStack, global tools, ghcr
login, `pixi install`; it verifies DVC but does not pull data). It expects `GITHUB_TOKEN` and
AWS credentials in the environment. Provide them from the sessions you just authenticated —
**all in a single Bash call** (env vars don't persist between calls) and **without ever
printing them**:

```bash
export PATH="$HOME/.pixi/bin:$PATH"
export GITHUB_TOKEN=$(gh auth token)
eval "$(aws configure export-credentials --profile Seahorse --format env)"
bash "$HOME/seahorse/scripts/vm/setup_mac.sh"
```

**OrbStack first-run:** the script installs OrbStack and launches it, then waits for the
Docker daemon. On first launch OrbStack shows a macOS permission dialog — tell the user:
**"Approve the OrbStack prompt (it asks for admin to install its helper). I'll wait for the
Docker daemon to come up."**

Watch the output. Transient network failures are common — if a step fails, fix it and re-run
`setup_mac.sh`. It is safe to re-run: it skips existing installs and fast-forwards the clone.

## Step 8 — Report completion

Tell the user setup is complete, and that they should:

- Open a new terminal (or `source ~/.zshrc`) to pick up pixi, `claude`, and the new
  oh-my-zsh shell, then `cd ~/seahorse`.
- Docker works immediately via OrbStack — no group/`newgrp` step needed (that's VM-only).

Then they can start working — e.g. `pixi run test-visuomotor-cpu`.
