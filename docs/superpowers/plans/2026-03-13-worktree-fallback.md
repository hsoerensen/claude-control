# Worktree Fallback Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the service try worktree mode first and automatically fall back to single mode when the server-side gate blocks it, plus add `--list` and `--uninstall-all` commands.

**Architecture:** A per-project wrapper script replaces the direct `claude` invocation in service templates. The wrapper tries `--spawn worktree`, checks stderr for the gate error, and falls back to single mode. The install script generates the wrapper and the templates invoke it.

**Tech Stack:** Bash, systemd, launchd

**Spec:** `docs/superpowers/specs/2026-03-13-worktree-fallback-design.md`

**Validation:** `bash -n install.sh` for syntax checking. No test framework.

---

## Chunk 1: Wrapper Script and Service Templates

### Task 1: Create the wrapper script template

**Files:**
- Create: `templates/claude-control-wrapper.sh`

The wrapper is a template with no install-time substitutions — it reads everything from environment variables set by the service/plist.

- [ ] **Step 1: Create `templates/claude-control-wrapper.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

# Wrapper for claude remote-control that tries worktree mode first,
# falling back to single mode if the feature gate is not enabled.

stderr_file="$(mktemp)"
trap 'rm -f "$stderr_file"' EXIT

# Try worktree mode
set +e
"$CLAUDE_BIN" remote-control \
    --spawn worktree \
    --capacity "$CAPACITY" \
    --name "$SESSION_NAME" \
    --no-create-session-in-dir \
    2>"$stderr_file"
exit_code=$?
set -e

# Success — worktree mode worked
if [[ "$exit_code" -eq 0 ]]; then
    exit 0
fi

# Check if worktree mode was gated
if grep -q "not yet enabled" "$stderr_file"; then
    echo "Worktree mode not available, starting in single mode" >&2
    exec "$CLAUDE_BIN" remote-control --name "$SESSION_NAME"
fi

# Some other error — print captured stderr and exit with original code
cat "$stderr_file" >&2
exit "$exit_code"
```

- [ ] **Step 2: Validate syntax**

Run: `bash -n templates/claude-control-wrapper.sh`
Expected: no output (clean syntax)

- [ ] **Step 3: Commit**

```bash
git add templates/claude-control-wrapper.sh
git commit -m 'add wrapper script template with worktree fallback'
```

---

### Task 2: Update the systemd service template

**Files:**
- Modify: `templates/claude-control@.service`

Change `ExecStart` from direct claude invocation to the wrapper. Remove `%%CLAUDE_BIN%%` substitution since the wrapper reads it from the env file.

- [ ] **Step 1: Update `templates/claude-control@.service`**

Replace the entire file with:

```ini
[Unit]
Description=Claude Code Remote Control (%i)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=%h/.config/claude-control/%i.env
WorkingDirectory=%%WORKING_DIR%%
ExecStart=/bin/bash %h/.config/claude-control/wrapper-%i.sh
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
```

Key changes:
- `ExecStart` now runs the per-project wrapper script
- `%%CLAUDE_BIN%%` removed from template — the wrapper reads `CLAUDE_BIN` from the env file

- [ ] **Step 2: Validate syntax visually** (systemd units don't have a syntax checker beyond `systemd-analyze verify` which needs a running system)

- [ ] **Step 3: Commit**

```bash
git add templates/claude-control@.service
git commit -m 'update systemd template to use wrapper script'
```

---

### Task 3: Update the launchd plist template

**Files:**
- Modify: `templates/com.claude-control.plist.tmpl`

Change `ProgramArguments` to invoke bash with the wrapper. Move `CLAUDE_BIN`, `CAPACITY`, and `SESSION_NAME` into `EnvironmentVariables`.

- [ ] **Step 1: Update `templates/com.claude-control.plist.tmpl`**

Replace the entire file with:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.claude-control.%%PROJECT_NAME%%</string>

    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>%%WRAPPER_PATH%%</string>
    </array>

    <key>WorkingDirectory</key>
    <string>%%PROJECT_DIR%%</string>

    <key>KeepAlive</key>
    <true/>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>%%PATH%%</string>
        <key>CLAUDE_BIN</key>
        <string>%%CLAUDE_BIN%%</string>
        <key>CAPACITY</key>
        <string>%%CAPACITY%%</string>
        <key>SESSION_NAME</key>
        <string>%%SESSION_NAME%%</string>
    </dict>

    <key>StandardOutPath</key>
    <string>%%LOG_DIR%%/%%PROJECT_NAME%%.log</string>

    <key>StandardErrorPath</key>
    <string>%%LOG_DIR%%/%%PROJECT_NAME%%.log</string>
</dict>
</plist>
```

Key changes:
- `ProgramArguments` reduced to `["/bin/bash", "<wrapper-path>"]`
- `CLAUDE_BIN`, `CAPACITY`, `SESSION_NAME` moved to `EnvironmentVariables`
- New `%%WRAPPER_PATH%%` placeholder

- [ ] **Step 2: Commit**

```bash
git add templates/com.claude-control.plist.tmpl
git commit -m 'update launchd template to use wrapper script'
```

---

## Chunk 2: Install Script Changes

### Task 4: Update `install_linux()` to generate the wrapper and env file

**Files:**
- Modify: `install.sh:128-158` (the `install_linux` function)

Add `CLAUDE_BIN` to the env file. Copy the wrapper template to `~/.config/claude-control/wrapper-<project>.sh`. Remove `%%CLAUDE_BIN%%` sed substitution from the service template (no longer needed). Keep `%%WORKING_DIR%%` and `%i` substitutions.

- [ ] **Step 1: Update `install_linux()` in `install.sh`**

Replace the function with:

```bash
install_linux() {
    local unit_dir="$HOME/.config/systemd/user"
    local config_dir="$HOME/.config/claude-control"
    local unit_name="claude-control-${PROJECT_NAME}.service"
    local unit_file="$unit_dir/$unit_name"
    local env_file="$config_dir/${PROJECT_NAME}.env"
    local wrapper_file="$config_dir/wrapper-${PROJECT_NAME}.sh"
    local claude_bin
    claude_bin="$(command -v claude)"

    mkdir -p "$unit_dir" "$config_dir"

    cat > "$env_file" <<ENV
CLAUDE_BIN=$claude_bin
CAPACITY=$CAPACITY
SESSION_NAME=$SESSION_NAME
ENV

    cp "$TEMPLATE_DIR/templates/claude-control-wrapper.sh" "$wrapper_file"

    sed \
        -e "s|%%WORKING_DIR%%|${PROJECT_DIR}|g" \
        -e "s|%i|${PROJECT_NAME}|g" \
        "$TEMPLATE_DIR/templates/claude-control@.service" > "$unit_file"

    systemctl --user daemon-reload
    systemctl --user enable "$unit_name"
    systemctl --user start "$unit_name"

    echo "Service installed and started: $unit_name"
    echo "Config: $env_file"
    echo "Status: systemctl --user status $unit_name"
}
```

Key changes:
- `CLAUDE_BIN` added to env file
- Wrapper script copied to per-project path
- `%%CLAUDE_BIN%%` sed substitution removed (not in template anymore)

- [ ] **Step 2: Validate syntax**

Run: `bash -n install.sh`
Expected: no output

- [ ] **Step 3: Commit**

```bash
git add install.sh
git commit -m 'update install_linux to generate wrapper and add CLAUDE_BIN to env'
```

---

### Task 5: Update `install_macos()` to generate the wrapper

**Files:**
- Modify: `install.sh:176-202` (the `install_macos` function)

Add wrapper script copy. Add `%%WRAPPER_PATH%%` substitution to the plist sed command.

- [ ] **Step 1: Update `install_macos()` in `install.sh`**

Replace the function with:

```bash
install_macos() {
    local plist_dir="$HOME/Library/LaunchAgents"
    local config_dir="$HOME/.config/claude-control"
    local log_dir="$HOME/Library/Logs/claude-control"
    local plist_name="com.claude-control.${PROJECT_NAME}.plist"
    local plist_file="$plist_dir/$plist_name"
    local wrapper_file="$config_dir/wrapper-${PROJECT_NAME}.sh"
    local claude_bin
    claude_bin="$(command -v claude)"
    local current_path="$PATH"

    mkdir -p "$plist_dir" "$config_dir" "$log_dir"

    cp "$TEMPLATE_DIR/templates/claude-control-wrapper.sh" "$wrapper_file"

    sed \
        -e "s|%%PROJECT_NAME%%|${PROJECT_NAME}|g" \
        -e "s|%%PROJECT_DIR%%|${PROJECT_DIR}|g" \
        -e "s|%%CAPACITY%%|${CAPACITY}|g" \
        -e "s|%%SESSION_NAME%%|${SESSION_NAME}|g" \
        -e "s|%%CLAUDE_BIN%%|${claude_bin}|g" \
        -e "s|%%WRAPPER_PATH%%|${wrapper_file}|g" \
        -e "s|%%PATH%%|${current_path}|g" \
        -e "s|%%LOG_DIR%%|${log_dir}|g" \
        "$TEMPLATE_DIR/templates/com.claude-control.plist.tmpl" > "$plist_file"

    launchctl bootstrap "gui/$(id -u)" "$plist_file"

    echo "Service installed and started: $plist_name"
    echo "Logs: $log_dir/${PROJECT_NAME}.log"
    echo "Status: launchctl list | grep claude-control"
}
```

Key changes:
- Wrapper script copied to per-project path
- `%%WRAPPER_PATH%%` substitution added
- `config_dir` created for wrapper storage

- [ ] **Step 2: Validate syntax**

Run: `bash -n install.sh`
Expected: no output

- [ ] **Step 3: Commit**

```bash
git add install.sh
git commit -m 'update install_macos to generate wrapper'
```

---

### Task 6: Update `resolve_template_dir()` for remote installs

**Files:**
- Modify: `install.sh:61-81` (the `resolve_template_dir` function)

Also fetch the wrapper script template when installing remotely via curl.

- [ ] **Step 1: Update `resolve_template_dir()` in `install.sh`**

Add a second curl fetch for the wrapper script after the platform-specific template fetch. Replace lines 71-79 with:

```bash
        mkdir -p "$TEMPLATE_DIR/templates"
        case "$OS" in
            linux) TEMPLATE="templates/claude-control@.service" ;;
            macos) TEMPLATE="templates/com.claude-control.plist.tmpl" ;;
        esac
        if ! curl -fsSL "$REPO_BASE/$TEMPLATE" -o "$TEMPLATE_DIR/$TEMPLATE"; then
            echo "Error: failed to fetch template from GitHub. Check your internet connection." >&2
            exit 1
        fi
        if ! curl -fsSL "$REPO_BASE/templates/claude-control-wrapper.sh" -o "$TEMPLATE_DIR/templates/claude-control-wrapper.sh"; then
            echo "Error: failed to fetch wrapper script from GitHub. Check your internet connection." >&2
            exit 1
        fi
```

- [ ] **Step 2: Validate syntax**

Run: `bash -n install.sh`
Expected: no output

- [ ] **Step 3: Commit**

```bash
git add install.sh
git commit -m 'fetch wrapper script in remote install path'
```

---

## Chunk 3: Uninstall Updates, --list, and --uninstall-all

### Task 7: Update `uninstall_linux()` and `uninstall_macos()` to remove wrapper

**Files:**
- Modify: `install.sh:160-174` (`uninstall_linux`)
- Modify: `install.sh:204-214` (`uninstall_macos`)

Add wrapper script removal to both uninstall functions.

- [ ] **Step 1: Update `uninstall_linux()` in `install.sh`**

Replace the function with:

```bash
uninstall_linux() {
    local name="$1"
    local unit_dir="$HOME/.config/systemd/user"
    local config_dir="$HOME/.config/claude-control"

    local unit_name="claude-control-${name}.service"

    systemctl --user stop "$unit_name" 2>/dev/null || true
    systemctl --user disable "$unit_name" 2>/dev/null || true
    rm -f "$unit_dir/$unit_name"
    rm -f "$config_dir/${name}.env"
    rm -f "$config_dir/wrapper-${name}.sh"

    systemctl --user daemon-reload
    echo "Service removed: $unit_name"
}
```

- [ ] **Step 2: Update `uninstall_macos()` in `install.sh`**

Replace the function with:

```bash
uninstall_macos() {
    local name="$1"
    local config_dir="$HOME/.config/claude-control"
    local plist_dir="$HOME/Library/LaunchAgents"
    local log_dir="$HOME/Library/Logs/claude-control"
    local plist_name="com.claude-control.${name}.plist"
    local plist_file="$plist_dir/$plist_name"

    launchctl bootout "gui/$(id -u)" "$plist_file" 2>/dev/null || true
    rm -f "$plist_file"
    rm -f "$config_dir/wrapper-${name}.sh"
    rm -f "$log_dir/${name}.log"
    echo "Service removed: $plist_name"
}
```

Note: changed from `rm -rf` of entire log directory to `rm -f` of the per-project log file. Full log directory cleanup happens in `uninstall_all()` (via repeated per-project removal, then directory cleanup if empty).

- [ ] **Step 3: Validate syntax**

Run: `bash -n install.sh`
Expected: no output

- [ ] **Step 4: Commit**

```bash
git add install.sh
git commit -m 'clean up wrapper script during uninstall'
```

---

### Task 8: Add `--list` and `--uninstall-all` commands

**Files:**
- Modify: `install.sh` — add flag variables, functions, and deferred dispatch

**Important:** `--list` and `--uninstall-all` need `OS` (set after the parser) and the `uninstall_linux`/`uninstall_macos` functions (defined after the parser). Use deferred flags — same pattern as `--uninstall` already uses. Set a variable in the parser, dispatch after `OS` is resolved.

- [ ] **Step 1: Add flag variables to the declarations block**

After the existing `UNINSTALL=""` line, add:

```bash
LIST=false
UNINSTALL_ALL=false
```

- [ ] **Step 2: Add flag parsing to the `case` block**

Add these lines to the argument parser `case`:

```bash
        --list)          LIST=true; shift ;;
        --uninstall-all) UNINSTALL_ALL=true; shift ;;
```

- [ ] **Step 3: Add `list_services()` function**

Add after the `uninstall_macos()` function:

```bash
list_services() {
    local config_dir="$HOME/.config/claude-control"
    local found=0

    case "$OS" in
        linux)
            for env_file in "$config_dir"/*.env; do
                [[ -f "$env_file" ]] || continue
                local name
                name="$(basename "$env_file" .env)"
                local unit_name="claude-control-${name}.service"
                local status
                if systemctl --user is-active "$unit_name" > /dev/null 2>&1; then
                    status="running"
                else
                    status="stopped"
                fi
                printf "%-30s %s\n" "$name" "$status"
                found=1
            done
            ;;
        macos)
            local plist_dir="$HOME/Library/LaunchAgents"
            for plist_file in "$plist_dir"/com.claude-control.*.plist; do
                [[ -f "$plist_file" ]] || continue
                local name
                name="$(basename "$plist_file" .plist)"
                name="${name#com.claude-control.}"
                local label="com.claude-control.${name}"
                local status
                if launchctl list "$label" > /dev/null 2>&1; then
                    status="running"
                else
                    status="stopped"
                fi
                printf "%-30s %s\n" "$name" "$status"
                found=1
            done
            ;;
    esac

    if [[ "$found" -eq 0 ]]; then
        echo "No claude-control services installed."
    fi
}
```

- [ ] **Step 4: Add `uninstall_all()` function**

Add after `list_services()`:

```bash
uninstall_all() {
    local config_dir="$HOME/.config/claude-control"
    local found=0

    case "$OS" in
        linux)
            for env_file in "$config_dir"/*.env; do
                [[ -f "$env_file" ]] || continue
                local name
                name="$(basename "$env_file" .env)"
                uninstall_linux "$name"
                found=1
            done
            ;;
        macos)
            local plist_dir="$HOME/Library/LaunchAgents"
            for plist_file in "$plist_dir"/com.claude-control.*.plist; do
                [[ -f "$plist_file" ]] || continue
                local name
                name="$(basename "$plist_file" .plist)"
                name="${name#com.claude-control.}"
                uninstall_macos "$name"
                found=1
            done
            ;;
    esac

    if [[ "$found" -eq 0 ]]; then
        echo "No claude-control services found to remove."
    fi

    # Clean up config directory if empty
    if [[ -d "$config_dir" ]] && [[ -z "$(ls -A "$config_dir" 2>/dev/null)" ]]; then
        rmdir "$config_dir"
        echo "Removed empty config directory: $config_dir"
    fi
}
```

- [ ] **Step 5: Add deferred dispatch in the main section**

In the `# Main` section, after the existing `--uninstall` block and before the prerequisites check, add:

```bash
if [[ "$LIST" == true ]]; then
    list_services
    exit 0
fi

if [[ "$UNINSTALL_ALL" == true ]]; then
    uninstall_all
    exit 0
fi
```

- [ ] **Step 6: Validate syntax**

Run: `bash -n install.sh`
Expected: no output

- [ ] **Step 7: Commit**

```bash
git add install.sh
git commit -m 'add --list and --uninstall-all commands'
```

---

## Chunk 4: Usage Update

### Task 9: Update usage text

**Files:**
- Modify: `install.sh` (the `usage` function)

- [ ] **Step 1: Replace the `usage()` function**

```bash
usage() {
    cat <<'USAGE'
Usage: install.sh [OPTIONS]
       install.sh --uninstall <project-name>
       install.sh --uninstall-all
       install.sh --list

Run from a git repository to install with defaults, or use flags to override.

Options:
  --project-dir <path>    Path to the git repo (default: current directory)
  --project-name <name>   Name for the service (default: directory basename)
  --capacity <n>          Max concurrent sessions (default: 4)
  --session-name <name>   Name shown in claude.ai/code (default: project-name)
  --uninstall <name>      Remove service for the named project
  --uninstall-all         Remove all installed services
  --list                  List installed services and their status
  -h, --help              Show this help
USAGE
}
```

- [ ] **Step 2: Validate syntax**

Run: `bash -n install.sh`
Expected: no output

- [ ] **Step 3: Commit**

```bash
git add install.sh
git commit -m 'update usage text with new commands'
```
