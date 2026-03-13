# claude-control

Keep `claude remote-control` running as a background service with fresh git worktrees. Linux only.

## Problem

Claude Code can connect to your machine over SSH, but that means your machine needs to accept incoming connections. If you're behind a firewall or NAT, that's difficult to set up.

## Solution

`claude remote-control` flips the direction — your machine connects out to Claude instead. claude-control wraps it in a systemd user service so it starts on boot and restarts on failure. Everything runs in user space, no `sudo` needed.

## Prerequisites

- `claude` CLI installed and logged in (`claude --version` must work)
- A Claude subscription (required for remote-control)
- `git` installed
- A git repository with at least one commit

## Quick start

Run from your project directory:

```bash
cd ~/my-project
curl -fsSL https://raw.githubusercontent.com/hsoerensen/claude-control/main/install.sh | bash
```

The installer detects the git repo you're in and picks sensible defaults.

### Development

If you want to work on claude-control itself:

```bash
git clone https://github.com/hsoerensen/claude-control
cd claude-control
./install.sh --project-dir ~/my-project
```

To test your changes on another machine, serve the repo locally and override `CLAUDE_CONTROL_REPO_BASE`:

```bash
# On your dev machine
python3 -m http.server 8080

# On the test machine
export CLAUDE_CONTROL_REPO_BASE=http://<dev-machine-ip>:8080
curl -fsSL $CLAUDE_CONTROL_REPO_BASE/install.sh | bash
```

## Configuration options

Everything has defaults. Pass flags to override:

```bash
curl -fsSL .../install.sh | bash -s -- --capacity 2 --session-name "my app"
```

| Option | Default | Description |
|--------|---------|-------------|
| `--project-dir <path>` | current directory | Path to the git repository |
| `--project-name <name>` | directory basename | Name used for the service and config files |
| `--capacity <n>` | `8` | Maximum concurrent sessions |
| `--session-name <name>` | project-name | Name shown in claude.ai/code |

### Changing settings after install

Edit `~/.config/claude-control/<project-name>.env` and restart:

```bash
systemctl --user restart claude-control-my-project.service
```

## Multi-project setup

Each project runs its own background service. Run the installer once per project directory:

```bash
cd ~/projects/express && curl -fsSL .../install.sh | bash
cd ~/projects/fastapi-app && curl -fsSL .../install.sh | bash
```

List all installed services:

```bash
./install.sh --list
```

## How it works

1. **Background service** — systemd keeps `claude remote-control` running. If it crashes, it restarts after 5 seconds.

2. **Session isolation** — each session gets its own git worktree, so multiple sessions don't interfere with each other. If worktree mode isn't available on your account yet, it falls back to single-session mode.

## Uninstall

Remove a single project:

```bash
curl -fsSL https://raw.githubusercontent.com/hsoerensen/claude-control/main/install.sh | bash -s -- --uninstall my-project
```

Remove all installed services at once:

```bash
curl -fsSL https://raw.githubusercontent.com/hsoerensen/claude-control/main/install.sh | bash -s -- --uninstall-all
```

### Manual uninstall

```bash
systemctl --user stop claude-control-my-project.service
systemctl --user disable claude-control-my-project.service
rm ~/.config/systemd/user/claude-control-my-project.service
rm ~/.config/claude-control/my-project.env
rm ~/.config/claude-control/wrapper-my-project.sh
systemctl --user daemon-reload
```

## Troubleshooting

**"Worktree mode not available, starting in single mode"**

Your account doesn't have multi-session remote control yet. It still works fine in single-session mode. Once multi-session is enabled, it'll switch to worktree mode on the next restart.

**Error: Claude Code not found**

Install Claude Code and make sure `claude --version` works, then re-run the installer.

**Error: has no commits**

Worktrees need at least one commit to work. Make an initial commit and try again.
