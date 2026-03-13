#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_BASE="https://raw.githubusercontent.com/hsoerensen/claude-control/main"

usage() {
    cat <<'USAGE'
Usage: install.sh [OPTIONS]
       install.sh --uninstall <project-name>

Options:
  --project-dir <path>    Path to the git repo (required)
  --project-name <name>   Name for the service (default: directory basename)
  --capacity <n>          Max concurrent sessions (default: 4)
  --session-name <name>   Name shown in claude.ai/code (default: project-name)
  --uninstall <name>      Remove service for the named project
  -h, --help              Show this help
USAGE
}

CAPACITY=4
PROJECT_DIR=""
PROJECT_NAME=""
SESSION_NAME=""
UNINSTALL=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project-dir)   PROJECT_DIR="$2"; shift 2 ;;
        --project-name)  PROJECT_NAME="$2"; shift 2 ;;
        --capacity)      CAPACITY="$2"; shift 2 ;;
        --session-name)  SESSION_NAME="$2"; shift 2 ;;
        --uninstall)     UNINSTALL="$2"; shift 2 ;;
        -h|--help)       usage; exit 0 ;;
        *)               echo "Unknown option: $1"; usage; exit 1 ;;
    esac
done

if [[ -z "$UNINSTALL" && -z "$PROJECT_DIR" ]]; then
    if [[ -d ".git" ]]; then
        PROJECT_DIR="$(pwd)"
    fi

    echo "claude-control installer"
    echo ""
    read -rp "Project directory [${PROJECT_DIR:-(none)}]: " input < /dev/tty
    PROJECT_DIR="${input:-$PROJECT_DIR}"
    if [[ -z "$PROJECT_DIR" ]]; then
        echo "Error: project directory is required" >&2
        exit 1
    fi
    PROJECT_DIR="${PROJECT_DIR/#\~/$HOME}"

    DEFAULT_NAME="$(basename "$(cd "$PROJECT_DIR" 2>/dev/null && pwd || echo "$PROJECT_DIR")")"
    read -rp "Project name [$DEFAULT_NAME]: " PROJECT_NAME < /dev/tty
    PROJECT_NAME="${PROJECT_NAME:-$DEFAULT_NAME}"

    read -rp "Capacity [4]: " CAPACITY < /dev/tty
    CAPACITY="${CAPACITY:-4}"
    if ! [[ "$CAPACITY" =~ ^[1-9][0-9]*$ ]]; then
        echo "Error: capacity must be a positive integer" >&2
        exit 1
    fi

    read -rp "Session name [$PROJECT_NAME]: " SESSION_NAME < /dev/tty
    SESSION_NAME="${SESSION_NAME:-$PROJECT_NAME}"
fi

detect_os() {
    case "$(uname -s)" in
        Linux)  echo "linux" ;;
        Darwin) echo "macos" ;;
        *)      echo "Unsupported OS: $(uname -s)" >&2; exit 1 ;;
    esac
}

OS="$(detect_os)"

resolve_template_dir() {
    if [[ -d "$SCRIPT_DIR/templates" ]]; then
        TEMPLATE_DIR="$SCRIPT_DIR"
    else
        if ! command -v curl > /dev/null 2>&1; then
            echo "Error: curl is required for remote install. Install it first." >&2
            exit 1
        fi
        TEMPLATE_DIR="$(mktemp -d)"
        trap 'rm -rf "$TEMPLATE_DIR"' EXIT
        mkdir -p "$TEMPLATE_DIR/templates"
        case "$OS" in
            linux) TEMPLATE="templates/claude-control@.service" ;;
            macos) TEMPLATE="templates/com.claude-control.plist.tmpl" ;;
        esac
        if ! curl -fsSL "$REPO_BASE/$TEMPLATE" -o "$TEMPLATE_DIR/$TEMPLATE"; then
            echo "Error: failed to fetch template from GitHub. Check your internet connection." >&2
            exit 1
        fi
    fi
}

validate_project_dir() {
    if [[ -z "$PROJECT_DIR" ]]; then
        echo "Error: --project-dir is required" >&2
        usage
        exit 1
    fi
    if [[ ! -d "$PROJECT_DIR/.git" ]]; then
        echo "Error: $PROJECT_DIR is not a git repository" >&2
        exit 1
    fi
    if ! git -C "$PROJECT_DIR" rev-parse HEAD > /dev/null 2>&1; then
        echo "Error: $PROJECT_DIR has no commits. Worktree mode requires at least one commit." >&2
        exit 1
    fi
    PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
}

merge_worktree_hook() {
    local settings_file="$HOME/.claude/settings.json"
    local hook_command="git pull --rebase >&2"

    if [[ ! -f "$settings_file" ]]; then
        mkdir -p "$HOME/.claude"
        echo '{}' > "$settings_file"
    fi

    if jq -e '.hooks.WorktreeCreate' "$settings_file" > /dev/null 2>&1; then
        if jq -e ".hooks.WorktreeCreate[].hooks[] | select(.command == \"$hook_command\")" "$settings_file" > /dev/null 2>&1; then
            echo "WorktreeCreate hook already configured"
            return
        fi
        local tmp
        tmp="$(mktemp)"
        jq ".hooks.WorktreeCreate += [{\"hooks\": [{\"type\": \"command\", \"command\": \"$hook_command\"}]}]" "$settings_file" > "$tmp"
        mv "$tmp" "$settings_file"
        echo "Added WorktreeCreate hook to existing hooks"
    else
        local tmp
        tmp="$(mktemp)"
        jq ".hooks.WorktreeCreate = [{\"hooks\": [{\"type\": \"command\", \"command\": \"$hook_command\"}]}]" "$settings_file" > "$tmp"
        mv "$tmp" "$settings_file"
        echo "Added WorktreeCreate hook"
    fi
}

install_linux() {
    local unit_dir="$HOME/.config/systemd/user"
    local config_dir="$HOME/.config/claude-control"
    local unit_name="claude-control-${PROJECT_NAME}.service"
    local unit_file="$unit_dir/$unit_name"
    local env_file="$config_dir/${PROJECT_NAME}.env"
    local claude_bin
    claude_bin="$(command -v claude)"

    mkdir -p "$unit_dir" "$config_dir"

    cat > "$env_file" <<ENV
CAPACITY=$CAPACITY
SESSION_NAME=$SESSION_NAME
ENV

    # Generate per-instance unit file from template with baked-in paths
    sed \
        -e "s|%%WORKING_DIR%%|${PROJECT_DIR}|g" \
        -e "s|%%CLAUDE_BIN%%|${claude_bin}|g" \
        -e "s|%i|${PROJECT_NAME}|g" \
        "$TEMPLATE_DIR/templates/claude-control@.service" > "$unit_file"

    systemctl --user daemon-reload
    systemctl --user enable "$unit_name"
    systemctl --user start "$unit_name"

    echo "Service installed and started: $unit_name"
    echo "Config: $env_file"
    echo "Status: systemctl --user status $unit_name"
}

uninstall_linux() {
    local name="$1"
    local unit_dir="$HOME/.config/systemd/user"
    local config_dir="$HOME/.config/claude-control"

    local unit_name="claude-control-${name}.service"

    systemctl --user stop "$unit_name" 2>/dev/null || true
    systemctl --user disable "$unit_name" 2>/dev/null || true
    rm -f "$unit_dir/$unit_name"
    rm -f "$config_dir/${name}.env"

    systemctl --user daemon-reload
    echo "Service removed: $unit_name"
}

install_macos() {
    local plist_dir="$HOME/Library/LaunchAgents"
    local log_dir="$HOME/Library/Logs/claude-control"
    local plist_name="com.claude-control.${PROJECT_NAME}.plist"
    local plist_file="$plist_dir/$plist_name"
    local claude_bin
    claude_bin="$(command -v claude)"
    local current_path="$PATH"

    mkdir -p "$plist_dir" "$log_dir"

    sed \
        -e "s|%%PROJECT_NAME%%|${PROJECT_NAME}|g" \
        -e "s|%%PROJECT_DIR%%|${PROJECT_DIR}|g" \
        -e "s|%%CAPACITY%%|${CAPACITY}|g" \
        -e "s|%%SESSION_NAME%%|${SESSION_NAME}|g" \
        -e "s|%%CLAUDE_BIN%%|${claude_bin}|g" \
        -e "s|%%PATH%%|${current_path}|g" \
        -e "s|%%LOG_DIR%%|${log_dir}|g" \
        "$TEMPLATE_DIR/templates/com.claude-control.plist.tmpl" > "$plist_file"

    launchctl bootstrap "gui/$(id -u)" "$plist_file"

    echo "Service installed and started: $plist_name"
    echo "Logs: $log_dir/${PROJECT_NAME}.log"
    echo "Status: launchctl list | grep claude-control"
}

uninstall_macos() {
    local name="$1"
    local plist_dir="$HOME/Library/LaunchAgents"
    local plist_name="com.claude-control.${name}.plist"
    local plist_file="$plist_dir/$plist_name"

    launchctl bootout "gui/$(id -u)" "$plist_file" 2>/dev/null || true
    rm -f "$plist_file"
    rm -rf "$HOME/Library/Logs/claude-control"
    echo "Service removed: $plist_name"
}

# Main
if [[ -n "$UNINSTALL" ]]; then
    case "$OS" in
        linux) uninstall_linux "$UNINSTALL" ;;
        macos) uninstall_macos "$UNINSTALL" ;;
    esac
    exit 0
fi

# Check prerequisites
if ! command -v git > /dev/null 2>&1; then
    echo "Error: git is required. Install it first." >&2
    exit 1
fi
if ! command -v claude > /dev/null 2>&1; then
    echo "Error: claude CLI not found. Install it first." >&2
    exit 1
fi
if ! command -v jq > /dev/null 2>&1; then
    echo "Error: jq is required for hook configuration. Install it first." >&2
    exit 1
fi

resolve_template_dir

validate_project_dir

if [[ -z "$PROJECT_NAME" ]]; then
    PROJECT_NAME="$(basename "$PROJECT_DIR")"
fi
if [[ -z "$SESSION_NAME" ]]; then
    SESSION_NAME="$PROJECT_NAME"
fi

echo "Installing claude-control for: $PROJECT_DIR"
echo "  Project name: $PROJECT_NAME"
echo "  Capacity: $CAPACITY"
echo "  Session name: $SESSION_NAME"
echo "  OS: $OS"
echo ""

merge_worktree_hook

case "$OS" in
    linux) install_linux ;;
    macos) install_macos ;;
esac
