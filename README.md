# claude-setup

Internal [Claude Code](https://claude.com/claude-code) plugins for Multiply Labs.

## `seahorse-setup`

Sets up a fresh dev machine for the [`seahorse`](https://github.com/multiplylabs/seahorse)
project with a single command — **no SCP, no pasted secrets**. GitHub and AWS are
authenticated entirely through browser flows; only short-lived, browser-derived credentials
ever touch the machine.

Two commands share the plugin:

- **`/setup-vm`** — a headless GCP GPU dev VM (Ubuntu 22.04, NVIDIA T4). Installs Docker +
  NVIDIA libraries via the tested `setup_vm.sh`.
- **`/setup-mac`** — an Apple Silicon MacBook (latest macOS). Installs OrbStack instead of
  Docker + NVIDIA via `setup_mac.sh`; no GPU stack.

Both also install the shared **Claude statusline** and **oh-my-zsh** shell config up front.

### Prerequisites

- **VM:** a running GCP dev VM (see `seahorse/scripts/vm/Readme.md` for provisioning), SSH'd in.
- **Mac:** an Apple Silicon Mac on the latest macOS.
- A browser for the login approvals (the VM uses your laptop's browser; the Mac uses its own).
- Access to the `Seahorse` AWS SSO account and the `multiplylabs/seahorse` repo.

### Usage

First install and authenticate Claude Code on the machine:

```sh
curl -fsSL https://claude.ai/install.sh | bash   # installs into ~/.local/bin
export PATH="$HOME/.local/bin:$PATH"
claude                                            # authenticate (browser)
```

Then, inside Claude:

```
/plugin marketplace add multiplylabs/claude-setup
/plugin install seahorse-setup@multiplylabs
/reload-plugins
/setup-vm      # on a VM
# or
/setup-mac     # on a Mac
```

`/reload-plugins` loads the just-installed commands into the current session.

### What it does

Both commands run the same steps in order (VM vs Mac differences noted); on a fresh Mac,
`/setup-mac` first ensures the Xcode Command Line Tools:

1. **Install the Claude statusline** — folder / branch / model / context / rate-limit segments.
2. **Install oh-my-zsh** + the shared, secret-free `~/.zshrc` (theme, plugins, keybindings).
   On the VM this also installs zsh and makes it the login shell.
3. **Install pixi** and CLI tools (`gh`, `git`, `jq`, `awscli`).
4. **Authenticate GitHub** via `gh auth login --web` (browser, no token).
5. **Clone seahorse**.
6. **Authenticate AWS** via `aws sso login` (browser).
7. **Run the tested setup script** — `setup_vm.sh` (Docker, NVIDIA, `pixi install`) or
   `setup_mac.sh` (OrbStack, `pixi install`); DVC is verified but not pulled.
8. **Report completion**.

When it finishes: open a new shell (or `source ~/.zshrc`), `cd ~/seahorse`, and start working.

### Security

- **No permanent tokens.** GitHub → OAuth device/browser flow (token stored in the system
  credential store). AWS → SSO. Credentials are never pasted, never printed, and never committed.
- **No secrets in the shell config.** The shared `~/.zshrc` is public and secret-free;
  machine-local secrets and personal aliases go in an un-committed `~/.zshrc.local`.
- **No org identifiers in this public repo.** The AWS SSO profile is read from the private
  `seahorse` clone (`scripts/vm/aws_sso_profile.conf`) at setup time.

### Layout

```
.claude-plugin/marketplace.json   # marketplace catalog
.claude-plugin/plugin.json        # plugin manifest
commands/setup-vm.md              # the /setup-vm runbook (GPU VM)
commands/setup-mac.md             # the /setup-mac runbook (Apple Silicon Mac)
zsh/zshrc                         # shared, self-adapting oh-my-zsh config
statusline/statusline-command.sh  # Claude statusline installed on the machine
```

The heavy-lift setup scripts (`setup_vm.sh`, `setup_mac.sh`) live in the private `seahorse`
repo under `scripts/vm/`, alongside the shared `aws_sso_profile.conf`.
