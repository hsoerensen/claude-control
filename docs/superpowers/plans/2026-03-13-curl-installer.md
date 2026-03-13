# Curl-pipe-to-bash Installer Implementation Plan

**Status:** Complete

**Goal:** Make `install.sh` work both as a local script (CLI args, local templates) and as a curl-piped installer (interactive prompts, fetched templates).

**Architecture:** Unified `install.sh` that auto-detects its mode: if `$SCRIPT_DIR/templates/` exists, use local templates; otherwise fetch from GitHub. If no CLI args are provided, prompt interactively via `/dev/tty`.

---

## Task 1: Add interactive mode and remote template fetching to install.sh

**Files:** `install.sh`

- [x] Add `REPO_BASE` constant pointing to raw GitHub URL
- [x] Add `resolve_template_dir()` — checks for local templates, falls back to fetching from GitHub into a temp dir with cleanup trap
- [x] Add interactive prompts via `/dev/tty` when no CLI args provided (project dir, name, capacity, session name with validation)
- [x] Replace `$SCRIPT_DIR` with `$TEMPLATE_DIR` in `install_linux` and `install_macos` sed commands
- [x] Add `resolve_template_dir` call after prerequisites check
- [x] Add macOS log directory cleanup to `uninstall_macos`

## Task 2: Update README.md

**Files:** `README.md`

- [x] Curl one-liner as primary quick start method
- [x] Non-interactive example with `--project-dir .`
- [x] Git-clone moved to Development subsection
- [x] Curl uninstall command as primary uninstall method
- [x] Manual uninstall instructions for Linux and macOS (including macOS log dir)
- [x] Replace `which claude` with `command -v claude`
- [x] Fix incorrect systemd unit name (`@` to `-`)
- [x] Simplify all language for non-technical readers

## Task 3: Update CLAUDE.md with design principles

**Files:** `CLAUDE.md`

- [x] Uninstall must be as easy as install
- [x] No elevated privileges
- [x] Plain language (technical OK in troubleshooting)
