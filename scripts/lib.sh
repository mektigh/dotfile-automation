#!/bin/bash
# lib.sh - Shared utilities for dotfile-automation scripts
#
# Source this file from other scripts:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPT_DIR/lib.sh"
#
# This file provides:
#   - Color constants for terminal output
#   - Logging functions (log_ok, log_error, log_warn, log_info, log_header)
#   - Path utilities (normalize_path)
#   - Symlink checks (is_symlink, is_broken, symlink_target)
#   - Interactive helpers (confirm)
#   - File operations (backup_file, ensure_parent_dir)
#   - Config file parsing (parse_dotfiles_conf)
#   - Environment loading (load_env)

set -euo pipefail

# ---------------------------------------------------------------------------
# Resolve DOTFILE_AUTOMATION_DIR (the repo root, one level above scripts/)
# ---------------------------------------------------------------------------
if [[ -z "${DOTFILE_AUTOMATION_DIR:-}" ]]; then
    DOTFILE_AUTOMATION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

# ---------------------------------------------------------------------------
# Environment loading
# ---------------------------------------------------------------------------

# load_env - Source the .env file if it exists
# Searches: $DOTFILE_AUTOMATION_DIR/.env, then falls back to defaults
load_env() {
    local env_file="${DOTFILE_AUTOMATION_DIR}/.env"

    if [[ -f "$env_file" ]]; then
        # Source the .env file, but only export lines that start with valid var names
        set -a
        # shellcheck disable=SC1090
        source "$env_file"
        set +a
    fi

    # Apply defaults for anything not set
    DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
    CONF_FILE="${CONF_FILE:-$DOTFILES_DIR/dotfiles.conf}"
    SHELL_ENV_FILE="${SHELL_ENV_FILE:-$HOME/.zshenv}"

    export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
    export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
    export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
    export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
}

# Load environment on source
load_env

# ---------------------------------------------------------------------------
# Colors (disabled automatically when output is not a terminal)
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    BOLD=''
    NC=''
fi

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

# log_ok - Print a success message (green [OK] prefix)
log_ok() {
    printf "${GREEN}  [OK]${NC} %s\n" "$*"
}

# log_error - Print an error message to stderr (red [ERROR] prefix)
log_error() {
    printf "${RED}  [ERROR]${NC} %s\n" "$*" >&2
}

# log_warn - Print a warning message (yellow [WARN] prefix)
log_warn() {
    printf "${YELLOW}  [WARN]${NC} %s\n" "$*"
}

# log_info - Print an informational message (blue [INFO] prefix)
log_info() {
    printf "${BLUE}  [INFO]${NC} %s\n" "$*"
}

# log_header - Print a section header with a decorative underline
log_header() {
    printf "\n${BOLD}${BLUE}%s${NC}\n" "$*"
    printf "${BLUE}%s${NC}\n" "$(printf '%.0s-' {1..60})"
}

# ---------------------------------------------------------------------------
# Path utilities
# ---------------------------------------------------------------------------

# normalize_path - Expand ~ to $HOME and return the logical path
# Usage: normalized=$(normalize_path "~/some/path")
# Note: Does NOT resolve symlinks (we want logical paths, not physical)
normalize_path() {
    local path="$1"

    # Expand leading ~ to $HOME
    if [[ "$path" == "~/"* ]]; then
        path="${HOME}/${path#\~/}"
    elif [[ "$path" == "~" ]]; then
        path="$HOME"
    fi

    printf '%s' "$path"
}

# ---------------------------------------------------------------------------
# Symlink checks
# ---------------------------------------------------------------------------

# is_symlink - Check if target is a symlink
# Usage: if is_symlink "/path/to/file"; then ...
is_symlink() {
    [[ -L "$1" ]]
}

# is_broken - Check if a symlink exists but its target does not
# Usage: if is_broken "/path/to/symlink"; then ...
is_broken() {
    [[ -L "$1" ]] && [[ ! -e "$1" ]]
}

# symlink_target - Read where a symlink points
# Usage: target=$(symlink_target "/path/to/symlink")
symlink_target() {
    readlink "$1" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Interactive helpers
# ---------------------------------------------------------------------------

# confirm - Ask yes/no question, default to no
# Usage: if confirm "Delete this file?"; then ...
# Returns 0 (true) for yes, 1 (false) for no
confirm() {
    local prompt="${1:-Continue?}"
    local answer

    printf "${YELLOW}%s [y/N]: ${NC}" "$prompt"
    read -r answer

    case "$answer" in
        [yY]|[yY][eE][sS]) return 0 ;;
        *) return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# File operations
# ---------------------------------------------------------------------------

# backup_file - Create a timestamped backup of a file or symlink
# Usage: backup_file "/path/to/file"
# Creates: /path/to/file.backup.20260206_193000
# Returns 0 on success, 1 if source doesn't exist
backup_file() {
    local filepath="$1"
    local timestamp
    timestamp="$(date +%Y%m%d_%H%M%S)"
    local backup_path="${filepath}.backup.${timestamp}"

    if [[ ! -e "$filepath" ]] && [[ ! -L "$filepath" ]]; then
        log_warn "Cannot backup '$filepath': does not exist"
        return 1
    fi

    cp -a "$filepath" "$backup_path"

    log_info "Backed up: $filepath -> $backup_path"
    return 0
}

# ensure_parent_dir - Create parent directories if they don't exist
# Usage: ensure_parent_dir "/path/to/new/file"
ensure_parent_dir() {
    local filepath="$1"
    local parent
    parent="$(dirname "$filepath")"

    if [[ ! -d "$parent" ]]; then
        mkdir -p "$parent"
        log_info "Created directory: $parent"
    fi
}

# ---------------------------------------------------------------------------
# Config file parsing
# ---------------------------------------------------------------------------

# parse_dotfiles_conf - Read dotfiles.conf and call a callback for each entry
# Usage: parse_dotfiles_conf "/path/to/dotfiles.conf" callback_function
#
# The callback receives three arguments:
#   callback source description destination
#
# All paths are normalized (~ expanded).
# File format: source:description:destination (colon-delimited)
# Lines starting with # are comments. Empty lines are ignored.
parse_dotfiles_conf() {
    local conf_file="$1"
    local callback="$2"

    if [[ ! -f "$conf_file" ]]; then
        log_error "Config file not found: $conf_file"
        return 1
    fi

    local line_num=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        line_num=$((line_num + 1))

        # Skip empty lines and comments
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        # Parse colon-delimited fields
        local source description destination
        IFS=':' read -r source description destination <<< "$line"

        # Validate we got all three fields
        if [[ -z "$source" ]] || [[ -z "$description" ]] || [[ -z "$destination" ]]; then
            log_warn "Skipping malformed line $line_num: $line"
            continue
        fi

        # Trim whitespace
        source="$(echo "$source" | xargs)"
        description="$(echo "$description" | xargs)"
        destination="$(echo "$destination" | xargs)"

        # Normalize paths
        source="$(normalize_path "$source")"
        destination="$(normalize_path "$destination")"

        # Call the callback
        "$callback" "$source" "$description" "$destination"
    done < "$conf_file"
}

# ---------------------------------------------------------------------------
# Version
# ---------------------------------------------------------------------------
DOTFILE_AUTOMATION_VERSION="1.0.0"
