# claude-setup

Internal [Claude Code](https://claude.com/claude-code) plugins for Multiply Labs.

## `seahorse-vm-setup`

Sets up a fresh GCP GPU dev VM for the [`seahorse`](https://github.com/multiplylabs/seahorse)
project with a single command — **no SCP, no pasted secrets**. GitHub and AWS are authenticated
entirely through browser flows; only short-lived, browser-derived credentials ever touch the VM.

### Prerequisites

- A running GCP dev VM (see `seahorse/scripts/vm/Readme.md` for provisioning), SSH'd in.
- A laptop browser for the login approvals.
- Access to the `Seahorse` AWS SSO account and the `multiplylabs/seahorse` repo.

### Usage

On the VM:

```sh
curl -fsSL https://claude.ai/install.sh | bash   # install Claude Code
claude                                            # authenticate (browser)
```

Then, inside Claude:

```
/plugin marketplace add multiplylabs/claude-setup
/plugin install seahorse-vm-setup@multiplylabs
/setup-vm
```

`/setup-vm` will:

1. Install pixi, `gh`, and `jq`.
2. Prompt you to authenticate **GitHub** via `gh auth login --web` (browser, no token).
3. Clone `seahorse`.
4. Prompt you to authenticate **AWS** via `aws sso login` (browser).
5. Run the tested `seahorse/scripts/vm/setup_vm.sh` (Docker, NVIDIA, `dvc pull`, `pixi install`),
   fixing any transient failures along the way.
6. Install the shared Claude statusline.

When it finishes: `source ~/.bashrc`, `cd ~/seahorse`, and start working.

### Security

- **No permanent tokens.** GitHub → OAuth device flow (token stored in the system credential
  store). AWS → SSO. Credentials are never pasted, never printed, and never committed.
- **No org identifiers in this public repo.** The AWS SSO profile is read from the private
  `seahorse` clone (`scripts/vm/aws_sso_profile.conf`) at setup time.

### Layout

```
.claude-plugin/marketplace.json   # marketplace catalog
.claude-plugin/plugin.json        # plugin manifest
commands/setup-vm.md              # the /setup-vm runbook
statusline/statusline-command.sh  # Claude statusline installed on the VM
```
