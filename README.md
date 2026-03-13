# claude-control

Keep `claude remote-control` running as a background service with fresh git worktrees. No SSH setup needed.

## Problem

Claude Code's desktop and mobile apps can connect to your machine over SSH, but that requires your machine to accept incoming connections. This does not work if your machine is behind a firewall.

## Solution

`claude remote-control` connects out to Claude instead of waiting for incoming connections. claude-control wraps it in a background service that starts on boot, restarts on failure, and pulls the latest code before each session.

No custom binary. No admin privileges required.

## Prerequisites

- `claude` CLI installed and logged in (`claude --version` must work)
- A Claude subscription (required for remote-control)
- `git` installed
- `jq` installed (used by the installer to set up hooks)
- A git repository with at least one commit
- Git credentials (SSH key or token) that the background service can access

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

## Configuration options

All options have defaults. Pass flags to override:

```bash
curl -fsSL .../install.sh | bash -s -- --capacity 2 --session-name "my app"
```

| Option | Default | Description |
|--------|---------|-------------|
| `--project-dir <path>` | current directory | Path to the git repository |
| `--project-name <name>` | directory basename | Name used for the service and config files |
| `--capacity <n>` | `4` | Maximum concurrent sessions |
| `--session-name <name>` | project-name | Name shown in claude.ai/code |

### Changing settings after install

**Linux:** Edit `~/.config/claude-control/<project-name>.env` and restart:

```bash
systemctl --user restart claude-control-my-project.service
```

**macOS:** Re-run the installer with the new values. The plist is at `~/Library/LaunchAgents/com.claude-control.<project-name>.plist`.

## Multi-project setup

Each project runs its own background service. Run the installer once per project directory:

```bash
cd ~/projects/express && curl -fsSL .../install.sh | bash
cd ~/projects/fastapi-app && curl -fsSL .../install.sh | bash
```

List all installed services:

```bash
curl -fsSL .../install.sh | bash -s -- --list
```

## How it works

1. **Git pull hook** — before each session starts, the service pulls the latest code from your repository so every session begins up to date.

2. **Background service** — your OS keeps `claude remote-control` running. If it stops for any reason, it restarts automatically after 5 seconds. No admin privileges needed.

3. **Session isolation** — each session gets its own copy of the code (a git worktree), so multiple sessions do not interfere with each other. If worktree mode is not available on your account yet, the service falls back to single-session mode automatically.

## Uninstall

Remove a single project:

```bash
curl -fsSL https://raw.githubusercontent.com/hsoerensen/claude-control/main/install.sh | bash -s -- --uninstall my-project
```

Remove all installed services at once:

```bash
curl -fsSL https://raw.githubusercontent.com/hsoerensen/claude-control/main/install.sh | bash -s -- --uninstall-all
```

The git pull hook in `~/.claude/settings.json` is kept because other projects may use it.

### Manual uninstall

**Linux:**

```bash
systemctl --user stop claude-control-my-project.service
systemctl --user disable claude-control-my-project.service
rm ~/.config/systemd/user/claude-control-my-project.service
rm ~/.config/claude-control/my-project.env
rm ~/.config/claude-control/wrapper-my-project.sh
systemctl --user daemon-reload
```

**macOS:**

```bash
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.claude-control.my-project.plist
rm ~/Library/LaunchAgents/com.claude-control.my-project.plist
rm ~/.config/claude-control/wrapper-my-project.sh
rm ~/Library/Logs/claude-control/my-project.log
```

The git pull hook in `~/.claude/settings.json` is kept because other projects may use it.

## Troubleshooting

**Git authentication fails in the service**

The background service needs access to your git credentials. On Linux, the SSH agent is not automatically available to background services. Add it to the config file:

```bash
# Find your current socket
echo $SSH_AUTH_SOCK
# Add to ~/.config/claude-control/my-project.env
SSH_AUTH_SOCK=/run/user/1000/ssh-agent.socket
```

Alternatively, use `gh auth setup-git` or a stored credential so the service can access git without the SSH agent.

**claude not found on macOS**

On macOS, background services do not see the same programs as your terminal. The installer saves your `PATH` at install time. If `claude` was not available when you ran the installer, re-run it after making sure `command -v claude` works in your terminal.

**"Worktree mode not available, starting in single mode"**

This means your account does not have multi-session Remote Control enabled yet. The service works normally in single-session mode. When multi-session becomes available on your account, the service will switch to worktree mode automatically on the next restart.

**Error: Claude Code not found**

The installer checks for `claude` before proceeding. Install Claude Code and make sure it works in your terminal, then re-run the installer.

**Error: has no commits**

The service needs at least one commit in your repository. Create an initial commit before installing.
