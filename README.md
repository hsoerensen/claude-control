# claude-control

Run Claude Code in the background on your Linux machine. Access it from the Claude mobile app or any browser — even when your server isn't reachable via SSH.

## Why claude-control?

Claude Code can connect to remote machines via SSH, but that requires SSH access from the device you're on *and* the server accepting inbound connections. Your phone or tablet can't SSH into your dev server — and your server may be behind NAT or a firewall anyway.

`claude remote-control` solves this by flipping the connection direction — your server connects *out* to Claude, so you can use it from the Claude mobile app or claude.ai in any browser. claude-control wraps it in a systemd user service so it starts on boot and restarts on failure. Each session gets its own isolated git worktree. Everything runs in user space, no `sudo` needed.

## Who is this for?

- You want to use Claude Code from the Claude mobile app or any browser via claude.ai
- Your devices don't have SSH access to your dev server
- Your server is behind a firewall, NAT, or VPN and can't accept incoming connections
- You want Claude Code always running and ready across multiple projects

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

1. **Background service** — systemd keeps `claude remote-control` running so you can access Claude Code from any device at any time. If it crashes, it restarts after 5 seconds.

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
