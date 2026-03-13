# Curl-pipe-to-bash installer

**Date:** 2026-03-13
**Status:** Implemented

## Problem

The install script required cloning the repo first, adding friction for regular users.

## Solution

`install.sh` works both as a local script and as a curl-piped installer:

```bash
curl -fsSL https://raw.githubusercontent.com/hsoerensen/claude-control/main/install.sh | bash
```

## Design

### Mode detection

`install.sh` auto-detects its mode:

1. **Local mode** (templates exist at `$SCRIPT_DIR/templates/`): use local templates, accept CLI args
2. **Remote mode** (no local templates): fetch the appropriate template from GitHub into a temp dir

### Interactive prompts

When no CLI args are provided (and not uninstalling), the script prompts interactively for:

- **Project directory** (required, validated as a git repo with at least one commit)
- **Project name** (default: basename of project dir)
- **Capacity** (default: 4, validated as positive integer)
- **Session name** (default: project name)

All prompts read from `/dev/tty` since stdin may be consumed by the pipe.

To skip prompts, pass `--project-dir` directly:

```bash
curl -fsSL .../install.sh | bash -s -- --project-dir .
```

### Prerequisites

- `git`, `claude` CLI, `jq` (always required)
- `curl` (checked only in remote mode)

### Template fetching

In remote mode, only the template for the detected OS is fetched into a temp directory, cleaned up via `trap` on exit.

### Install and uninstall parity

Both install and uninstall work as single curl commands:

```bash
# Install
curl -fsSL .../install.sh | bash

# Uninstall
curl -fsSL .../install.sh | bash -s -- --uninstall my-project
```

macOS uninstall also removes the log directory (`~/Library/Logs/claude-control/`).

### Design principles established

- **Uninstall must be as easy as install**
- **No elevated privileges** — everything in user space
- **Plain language** in user-facing text (technical terms OK in troubleshooting)
