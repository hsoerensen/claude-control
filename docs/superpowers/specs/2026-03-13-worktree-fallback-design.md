# Worktree Fallback Design

## Problem

`claude remote-control --spawn worktree` requires a server-side feature gate ("Multi-session Remote Control"). Accounts without the gate get an error, and the systemd service enters a restart loop.

The gate is not account-level — it can differ between machines on the same account. There is no way to detect it ahead of time. Both the gate error and other errors return exit code 1, so we must match stderr to distinguish.

## Design

Replace the direct `claude` invocation in service templates with a wrapper script that tries worktree mode first and falls back to single mode when gated.

### Wrapper script: `claude-control-wrapper.sh`

One wrapper per project, installed to `~/.config/claude-control/wrapper-<project-name>.sh` on both Linux and macOS. Per-project files avoid uninstall conflicts — removing one project's service does not affect others. Using `~/.config/` on macOS is intentional — keeps install/uninstall logic simple across platforms.

**Environment variables** (read from env file on Linux, set in plist EnvironmentVariables on macOS):
- `CLAUDE_BIN` — path to the claude binary
- `CAPACITY` — max concurrent sessions (worktree mode only)
- `SESSION_NAME` — name shown in claude.ai/code

All three are written to the env file (Linux) or plist EnvironmentVariables (macOS) at install time.

**Logic:**

1. Try: `$CLAUDE_BIN remote-control --spawn worktree --capacity $CAPACITY --name $SESSION_NAME --no-create-session-in-dir`, capturing stderr to a temp file (text only, cleaned up via `trap`).
2. If stderr contains `"not yet enabled"` (substring match via `grep -q`), log `"Worktree mode not available, starting in single mode"` to stderr and exec: `$CLAUDE_BIN remote-control --name $SESSION_NAME`
3. Otherwise, exit with whatever code `claude` returned (systemd/launchd handles restarts).

**Fallback behavior:**
- `--capacity` and `--no-create-session-in-dir` are omitted in single mode — they are worktree-only flags with no meaning in single mode.
- The fallback decision is not cached. Each service restart re-attempts worktree mode first. This is correct because the gate could be enabled at any time. The gate error returns near-instantly (no network delay), so the overhead is negligible.
- On success, log `"Started in worktree mode"` so users can verify which mode is running.

**Stderr capture:** Use a temp file (`mktemp`), cleaned up on exit via `trap`. The temp file approach avoids issues with `set -e` and process substitution portability. The file contains only text.

**Known risk:** The error string `"not yet enabled"` is owned by Anthropic. If it changes, the fallback silently breaks (restart loop). This is accepted — the string is a stable user-facing message unlikely to change without a broader API change.

### Service template changes

**Linux (`claude-control@.service`):**
- `ExecStart` changes from direct `claude` invocation to: `bash %h/.config/claude-control/wrapper-%i.sh`
- `EnvironmentFile` still provides `CAPACITY`, `SESSION_NAME`, and now also `CLAUDE_BIN`.
- `WorkingDirectory` remains unchanged — the wrapper inherits it from the service.

**macOS (`com.claude-control.plist.tmpl`):**
- `ProgramArguments` changes from the current 9-element array (claude path + all flags) to: `["/bin/bash", "~/.config/claude-control/wrapper-<project>.sh"]`
- Add `CLAUDE_BIN`, `CAPACITY`, and `SESSION_NAME` to the `EnvironmentVariables` dict (currently only `PATH` is set there). `CLAUDE_BIN` moves from a baked-in program argument to an environment variable.
- `WorkingDirectory` remains unchanged — the wrapper inherits it from launchd.

### Install script changes

- Generate a per-project wrapper script to `~/.config/claude-control/wrapper-<project-name>.sh`.
- Add `CLAUDE_BIN` to the env file (Linux) and plist EnvironmentVariables (macOS).
- Update `resolve_template_dir` to also fetch the wrapper script template for remote (curl) installs.
- `--capacity` and `--session-name` flags still work as before.
- No new flags needed.

### Uninstall changes

**`--uninstall <name>`** (existing, updated):
- Remove the per-project wrapper script alongside the service and env file (both platforms).

**`--uninstall-all`** (new):
- Discovers all installed claude-control services by scanning for artifacts:
  - Linux: env files in `~/.config/claude-control/*.env` and service units in `~/.config/systemd/user/claude-control-*.service`
  - macOS: plist files in `~/Library/LaunchAgents/com.claude-control.*.plist`
- Extracts the project name from each artifact filename and runs the existing per-project uninstall for each.
- Removes the `~/.config/claude-control/` directory if empty after all projects are uninstalled.
- Prints each project name as it is removed.

**`--list`** (new):
- Lists all installed claude-control projects with their status (running/stopped).
  - Linux: scans `~/.config/claude-control/*.env`, checks `systemctl --user is-active` for each.
  - macOS: scans `~/Library/LaunchAgents/com.claude-control.*.plist`, checks `launchctl list` for each.
- Output format: one line per project, e.g. `cre-cli  running` or `my-project  stopped`.

### What stays the same

- `--capacity`, `--session-name`, `--project-dir`, `--project-name` install flags unchanged.
- WorktreeCreate hook still installed (needed when worktree mode works).
- Restart behavior (systemd `Restart=always`, launchd `KeepAlive`) unchanged.
