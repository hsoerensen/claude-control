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

```bash
curl -fsSL https://raw.githubusercontent.com/hsoerensen/claude-control/main/install.sh | bash
```

The installer will prompt you for your project directory, name, capacity, and session name.

To skip the prompts, run from your project directory:

```bash
curl -fsSL https://raw.githubusercontent.com/hsoerensen/claude-control/main/install.sh | bash -s -- --project-dir .
```

This uses defaults for everything else (project name from directory basename, capacity 4, session name matches project name).

### Development

If you want to modify claude-control itself:

```bash
git clone https://github.com/hsoerensen/claude-control
cd claude-control
./install.sh --project-dir ~/my-project
```

## Configuration options

| Option | Default | Description |
|--------|---------|-------------|
| `--project-dir <path>` | (required) | Path to the git repository |
| `--project-name <name>` | directory basename | Name used for the service and config files |
| `--capacity <n>` | `4` | Maximum concurrent sessions |
| `--session-name <name>` | project-name | Name shown in claude.ai/code |

On Linux, configuration is stored in `~/.config/claude-control/<project-name>.env` and can be edited directly. Restart the service after changes:

```bash
systemctl --user restart claude-control-my-project.service
```

On macOS, values are set at install time. Re-run `install.sh` to change them.

## Multi-project setup

Each project runs its own background service. Run `install.sh` once per project:

```bash
./install.sh --project-dir ~/projects/express --project-name express
./install.sh --project-dir ~/projects/fastapi-app --project-name fastapi-app --capacity 2
```

Each service pulls from its own repository automatically.

## How it works

1. **Git pull hook** — before each session starts, the service pulls the latest code from your repository so every session begins up to date.

2. **Background service** — your OS keeps `claude remote-control` running. If it stops for any reason, it restarts automatically after 5 seconds. No admin privileges needed.

3. **Session isolation** — each session gets its own copy of the code (a git worktree), so multiple sessions do not interfere with each other.

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/hsoerensen/claude-control/main/install.sh | bash -s -- --uninstall my-project
```

Stops the service and removes all related files. The git pull hook in `~/.claude/settings.json` is kept because other projects may use it.

### Manual uninstall

**Linux:**

```bash
systemctl --user stop claude-control-my-project.service
systemctl --user disable claude-control-my-project.service
rm ~/.config/systemd/user/claude-control-my-project.service
rm ~/.config/claude-control/my-project.env
systemctl --user daemon-reload
```

**macOS:**

```bash
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.claude-control.my-project.plist
rm ~/Library/LaunchAgents/com.claude-control.my-project.plist
rm -rf ~/Library/Logs/claude-control
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

**Error: claude CLI not found**

The installer checks for `claude` before proceeding. Install the Claude Code CLI and make sure it works in your terminal, then re-run the installer.

**Error: has no commits**

The service needs at least one commit in your repository. Create an initial commit before installing.
