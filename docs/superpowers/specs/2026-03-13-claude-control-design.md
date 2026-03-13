# claude-control Design Spec

## Problem

Claude Code's desktop and mobile apps can create inbound SSH connections, but this fails when:
- SSH requires biometric authentication (Touch ID, YubiKey)
- The machine is behind a firewall
- The machine is on a Tailscale network without public ingress

## Solution

Use `claude remote-control` (which creates outbound connections) as a persistent service, so Claude Code is always available without inbound SSH. The `--spawn worktree` flag isolates each session in its own git worktree, and a `WorktreeCreate` hook ensures each worktree starts from the latest `origin/main`.

No custom binary is needed. The OS service manager (systemd on Linux, launchd on macOS) handles process supervision.

## Components

### 1. WorktreeCreate Hook

Configured in the user-level `~/.claude/settings.json` so it applies to all projects. The hook must be merged into the existing settings file (which may already contain `PreToolUse`, `PostToolUse`, etc.) — never overwrite.

WorktreeCreate does not support matchers — the hook fires on every worktree creation.

```json
{
  "hooks": {
    "WorktreeCreate": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "git pull --rebase >&2"
          }
        ]
      }
    ]
  }
}
```

Runs `git pull --rebase` on the main repo before each worktree is created. Assumes the main branch has no local changes (it serves only as a base for worktrees).

**Multi-project support:** The hook runs in the working directory of the `claude remote-control` process that triggered it. Each project runs its own `claude remote-control` instance (separate systemd/launchd service), so the hook naturally targets the correct repo.

**Git authentication:** The service process must have access to git credentials (SSH key or credential helper). For systemd, set `SSH_AUTH_SOCK` in the environment file or use a deploy key. For launchd, the user's SSH agent is typically available.

### 2. systemd Unit Template (Linux)

File: `templates/claude-control@.service`

The template uses `%%PLACEHOLDER%%` tokens that `install.sh` replaces with `sed` to generate **per-instance unit files** (e.g. `claude-control-myproject.service`). This is necessary because systemd cannot resolve `EnvironmentFile` variables in `WorkingDirectory`.

Installed as **user-level** units in `~/.config/systemd/user/` — no root required, inherits the user's environment.

```ini
[Unit]
Description=Claude Code Remote Control (%i)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=%h/.config/claude-control/%i.env
WorkingDirectory=%%WORKING_DIR%%
ExecStart=%%CLAUDE_BIN%% remote-control --spawn worktree --capacity ${CAPACITY} --name ${SESSION_NAME} --no-create-session-in-dir
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
```

At install time, `%%WORKING_DIR%%`, `%%CLAUDE_BIN%%`, and `%i` are replaced with actual values. The remaining `${CAPACITY}` and `${SESSION_NAME}` are resolved at runtime from the environment file.

`--no-create-session-in-dir` is used because the main repo directory is only a base for worktrees — sessions should not run directly in it.

### 3. launchd Plist Template (macOS)

File: `templates/com.claude-control.plist.tmpl`

Installed as a **user agent** in `~/Library/LaunchAgents/` — runs in the user's session with access to their SSH agent and shell environment.

Since launchd does not support instance parameterization like systemd, each project gets its own plist file with all values baked in. The install script generates these from the template using `sed`.

launchd does not inherit the user's shell `PATH`. The install script captures the current `PATH` at install time and bakes it into the plist.

Logs go to `~/Library/Logs/claude-control/<project>.log`.

### 4. Setup Script

File: `install.sh`

Detects the OS and installs the appropriate service file:
- Validates that the project directory is a git repo with at least one commit
- Checks prerequisites (`git`, `claude`, `jq`)
- Accepts project directory, capacity, session name as CLI flags
- Merges the WorktreeCreate hook into `~/.claude/settings.json` (preserving existing hooks)
- Generates per-instance service files from templates via `sed`
- Enables and starts the service
- Works on Linux (systemd) and macOS (launchd)

**Uninstall:** `install.sh --uninstall <project>` stops the service, removes the service file, and removes the environment/config file. Does not remove the WorktreeCreate hook (it may be shared across projects).

### 5. README

Documents:
- The problem and solution
- Prerequisites (Claude Code CLI, git, jq, account with subscription, git credentials accessible to the service)
- Installation steps
- Configuration options
- Multi-project setup
- Troubleshooting (common issues: git auth, PATH, Claude CLI not found, empty repo)

## Configuration

### systemd (Linux)

Environment file at `~/.config/claude-control/<project>.env`:

```bash
CAPACITY=4
SESSION_NAME=my-project
```

The project directory and claude binary path are baked into the unit file at install time, not in the env file.

### launchd (macOS)

All values are baked into the plist at install time. To change, re-run `install.sh` for the project.

### Configuration reference

| Setting | Default | Description |
|---------|---------|-------------|
| `PROJECT_DIR` | (required) | Path to the git repo |
| `CAPACITY` | `4` | Max concurrent sessions |
| `SESSION_NAME` | project name | Name shown in claude.ai/code |

### Permission mode

`claude remote-control` uses its default permission mode. For unattended operation, consider `--permission-mode bypassPermissions` or `--permission-mode dontAsk` — but understand that `bypassPermissions` allows Claude to execute any tool without confirmation. The install script does not set this by default; users who want it can add it to the environment file or plist.

## Build Targets

No compilation needed. The project ships plain text files:
- Service templates (systemd unit, launchd plist)
- Shell script (install.sh)
- Hook configuration (JSON)
- Documentation (README)

Target platforms: linux/amd64, linux/arm64, darwin/arm64. The install script has no architecture-dependent logic.

## Assumptions

- The main branch of the target repo has no local uncommitted changes
- `claude` CLI is installed and authenticated
- The user has a Claude subscription (required for remote-control)
- Git is installed and the target directory is a git repository with at least one commit (`--spawn worktree` fails on empty repos because `HEAD` cannot be resolved)
- Git credentials (SSH key or credential helper) are accessible to the service process

## Out of Scope

- Custom process management or pool logic (handled by `claude remote-control`)
- Worktree cleanup logic (handled by `claude remote-control`)
- Log rotation (handled by systemd journal / launchd, or standard log rotation tools)
- Permission mode recommendations beyond documenting the options
