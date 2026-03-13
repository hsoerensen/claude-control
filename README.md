# claude-control

Keep `claude remote-control` running as a background service with fresh git worktrees. No SSH setup needed. Linux only.

## Problem

Claude Code's desktop and mobile apps can connect to your machine over SSH, but that requires your machine to accept incoming connections. This does not work if your machine is behind a firewall.

## Solution

`claude remote-control` connects out to Claude instead of waiting for incoming connections. claude-control wraps it in a systemd user service that starts on boot and restarts on failure.

No custom binary. No admin privileges required.

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

That's it. The installer detects the current git repository and uses sensible defaults for everything.

### Development

If you want to modify claude-control itself:

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

All options have defaults. Pass flags to override:

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

1. **Background service** — systemd keeps `claude remote-control` running. If it stops for any reason, it restarts automatically after 5 seconds. No admin privileges needed.

2. **Session isolation** — each session gets its own copy of the code (a git worktree), so multiple sessions do not interfere with each other. If worktree mode is not available on your account yet, the service falls back to single-session mode automatically.

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

This means your account does not have multi-session Remote Control enabled yet. The service works normally in single-session mode. When multi-session becomes available on your account, the service will switch to worktree mode automatically on the next restart.

**Error: Claude Code not found**

The installer checks for `claude` before proceeding. Install Claude Code and make sure it works in your terminal, then re-run the installer.

**Error: has no commits**

The service needs at least one commit in your repository. Create an initial commit before installing.
