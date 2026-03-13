# claude-control Implementation Plan

> **Status:** Implemented. All tasks complete.

**Goal:** Ship a ready-to-use configuration package that keeps `claude remote-control` running as a persistent service with fresh worktrees.

**Architecture:** No custom code — just service templates, a setup script, and documentation. The install script detects the OS, merges a WorktreeCreate hook into Claude settings, generates per-instance service files from templates, and enables the service.

**Tech Stack:** Bash (install script), systemd (Linux), launchd (macOS), JSON (hook config)

**Spec:** `docs/superpowers/specs/2026-03-13-claude-control-design.md`

---

## File Structure

| File | Purpose |
|------|---------|
| `templates/claude-control@.service` | systemd unit template (sed-substituted at install time) |
| `templates/com.claude-control.plist.tmpl` | launchd plist template (sed-substituted at install time) |
| `install.sh` | Setup/uninstall script for both platforms |
| `README.md` | User-facing documentation |
| `LICENSE` | MIT license |
| `.gitignore` | Excludes .env and .DS_Store |

---

## Chunk 1: Service Templates and Install Script

### Task 1: systemd Unit Template

**Files:**
- Create: `templates/claude-control@.service`

- [x] **Step 1: Create the systemd unit template**

```bash
mkdir -p templates
```

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

`%%WORKING_DIR%%`, `%%CLAUDE_BIN%%`, and `%i` are replaced by `install.sh` via `sed` to produce per-instance unit files (e.g. `claude-control-myproject.service`). `${CAPACITY}` and `${SESSION_NAME}` are resolved at runtime from the environment file.

- [x] **Step 2: Commit**

---

### Task 2: launchd Plist Template

**Files:**
- Create: `templates/com.claude-control.plist.tmpl`

- [x] **Step 1: Create the launchd plist template**

Uses `%%PLACEHOLDER%%` tokens that `install.sh` replaces with `sed`.

- [x] **Step 2: Commit**

---

### Task 3: Install Script

**Files:**
- Create: `install.sh`

The script handles install and uninstall for both platforms. It:
1. Parses CLI flags (`--project-dir`, `--project-name`, `--capacity`, `--session-name`, `--uninstall`)
2. Checks prerequisites (`git`, `claude`, `jq`)
3. Validates the project directory is a git repo with at least one commit
4. Merges WorktreeCreate hook into `~/.claude/settings.json`
5. Generates per-instance service files from templates via `sed`
6. Enables and starts the service

Key implementation details:
- Uses `command -v` (not `which`) for portable binary detection
- systemd: generates `claude-control-<name>.service` per instance (not `@` template sharing) because `WorkingDirectory` cannot use env vars
- macOS: uses `launchctl bootstrap`/`bootout` (modern API, not deprecated `load`/`unload`)
- Env file (Linux) contains only `CAPACITY` and `SESSION_NAME` — project dir and claude binary are baked into the unit file

- [x] **Steps 1-6: Implemented and committed**

---

### Task 4: README

**Files:**
- Create: `README.md`

- [x] **Step 1: Write README.md**

Covers: problem/solution, prerequisites, quick start, configuration options, multi-project setup, how it works, uninstall, troubleshooting.

- [x] **Step 2: Commit**

---

### Task 5: Final Config and Test

- [x] **Step 1: Update CLAUDE.md** — reflects config-only project
- [x] **Step 2: Create .gitignore** — `*.env`, `.DS_Store`
- [x] **Step 3: Add MIT license**
- [x] **Step 4: Test install/uninstall on Linux** — service started and stopped successfully
- [x] **Step 5: Push to origin**

## Implementation Notes

During implementation, discovered that systemd's `WorkingDirectory` directive cannot resolve variables from `EnvironmentFile`. The original plan used a shared `@` template with `WorkingDirectory=${PROJECT_DIR}`, which failed at runtime. Fixed by switching to per-instance unit files with paths baked in via `sed`, matching the launchd approach.
