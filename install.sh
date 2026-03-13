#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_BASE="${CLAUDE_CONTROL_REPO_BASE:-https://raw.githubusercontent.com/hsoerensen/claude-control/main}"

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

CAPACITY=8
PROJECT_DIR=""
PROJECT_NAME=""
SESSION_NAME=""
UNINSTALL=""
LIST=false
UNINSTALL_ALL=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project-dir)   PROJECT_DIR="$2"; shift 2 ;;
        --project-name)  PROJECT_NAME="$2"; shift 2 ;;
        --capacity)      CAPACITY="$2"; shift 2 ;;
        --session-name)  SESSION_NAME="$2"; shift 2 ;;
        --uninstall)     UNINSTALL="$2"; shift 2 ;;
        --list)          LIST=true; shift ;;
        --uninstall-all) UNINSTALL_ALL=true; shift ;;
        -h|--help)       usage; exit 0 ;;
        *)               echo "Unknown option: $1"; usage; exit 1 ;;
    esac
done

if [[ -z "$UNINSTALL" && "$LIST" == false && "$UNINSTALL_ALL" == false && -z "$PROJECT_DIR" ]]; then
    if [[ -d ".git" ]]; then
        PROJECT_DIR="$(pwd)"
    else
        echo "Error: not a git repository. Run from a git repo or use --project-dir." >&2
        exit 1
    fi
fi

if [[ "$(uname -s)" != "Linux" ]]; then
    echo "Error: only Linux is supported." >&2
    exit 1
fi

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
        if ! curl -fsSL "$REPO_BASE/templates/claude-control@.service" -o "$TEMPLATE_DIR/templates/claude-control@.service"; then
            echo "Error: failed to fetch template from GitHub. Check your internet connection." >&2
            exit 1
        fi
        if ! curl -fsSL "$REPO_BASE/templates/claude-control-wrapper.sh" -o "$TEMPLATE_DIR/templates/claude-control-wrapper.sh"; then
            echo "Error: failed to fetch wrapper script from GitHub. Check your internet connection." >&2
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

list_services() {
    local config_dir="$HOME/.config/claude-control"
    local found=0

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

    if [[ "$found" -eq 0 ]]; then
        echo "No claude-control services installed."
    fi
}

uninstall_all() {
    local config_dir="$HOME/.config/claude-control"
    local found=0

    for env_file in "$config_dir"/*.env; do
        [[ -f "$env_file" ]] || continue
        local name
        name="$(basename "$env_file" .env)"
        uninstall_linux "$name"
        found=1
    done

    if [[ "$found" -eq 0 ]]; then
        echo "No claude-control services found to remove."
    fi

    # Clean up config directory if empty
    if [[ -d "$config_dir" ]] && [[ -z "$(ls -A "$config_dir" 2>/dev/null)" ]]; then
        rmdir "$config_dir"
        echo "Removed empty config directory: $config_dir"
    fi
}

# Main
if [[ -n "$UNINSTALL" ]]; then
    uninstall_linux "$UNINSTALL"
    exit 0
fi

if [[ "$LIST" == true ]]; then
    list_services
    exit 0
fi

if [[ "$UNINSTALL_ALL" == true ]]; then
    uninstall_all
    exit 0
fi

# Check prerequisites
if ! command -v git > /dev/null 2>&1; then
    echo "Error: git is required. Install it first." >&2
    exit 1
fi
if ! command -v claude > /dev/null 2>&1; then
    echo "Error: Claude Code not found. Install it first." >&2
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
if ! [[ "$CAPACITY" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: capacity must be a positive integer" >&2
    exit 1
fi

echo "Installing claude-control for: $PROJECT_DIR"
echo "  Project name: $PROJECT_NAME"
echo "  Capacity: $CAPACITY"
echo "  Session name: $SESSION_NAME"
echo ""

install_linux
