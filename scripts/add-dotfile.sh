#!/bin/bash
# add-dotfile.sh - Onboard a new dotfile into the managed dotfiles system
#
# This script takes an existing config file on your system, moves it into
# your dotfiles repo, creates a symlink in the original location, and
# registers it in dotfiles.conf so symlink-check.sh can manage it.
#
# Usage:
#   add-dotfile.sh <dotfile_path> [description]
#   add-dotfile.sh --help
#
# Examples:
#   add-dotfile.sh ~/.config/alacritty/alacritty.toml "Alacritty terminal config"
#   add-dotfile.sh ~/.tmux.conf "Tmux configuration"
#   add-dotfile.sh ~/.config/starship.toml
#
# Workflow:
#   1. Validates the file exists at the given path
#   2. Determines the destination in your dotfiles repo
#   3. Shows a preview of what will happen
#   4. Asks for confirmation before proceeding
#   5. Backs up any existing files
#   6. Moves the original file into the dotfiles repo
#   7. Creates a symlink from the original location to the repo
#   8. Adds the entry to dotfiles.conf
#   9. Verifies the symlink works

set -euo pipefail

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------
show_help() {
    cat <<EOF
Usage: $(basename "$0") <dotfile_path> [description]

Onboard a new dotfile into the managed dotfiles system.

This script will:
  1. Move the file into your dotfiles repo (\$DOTFILES_DIR)
  2. Create a symlink at the original location
  3. Register it in your dotfiles.conf

Arguments:
  dotfile_path   Path to the dotfile to onboard (e.g. ~/.config/starship.toml)
  description    Optional human-readable description (auto-generated if omitted)

Options:
  --help, -h     Show this help message

Environment variables:
  DOTFILES_DIR   Path to your dotfiles repo (default: \$HOME/.dotfiles)
  CONF_FILE      Path to your dotfiles.conf (default: \$DOTFILES_DIR/dotfiles.conf)

Examples:
  $(basename "$0") ~/.tmux.conf "Tmux configuration"
  $(basename "$0") ~/.config/alacritty/alacritty.toml "Alacritty config"
  $(basename "$0") ~/.config/starship.toml

What happens step by step:
  1. Your file is backed up (timestamped copy alongside the original)
  2. The file is moved into \$DOTFILES_DIR, mirroring its path under \$HOME
     Example: ~/.config/starship.toml -> \$DOTFILES_DIR/.config/starship.toml
  3. A symlink is created at the original location pointing to the repo copy
  4. An entry is added to dotfiles.conf for symlink-check.sh to manage
  5. The symlink is verified to work correctly
EOF
    exit 0
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
if [[ $# -lt 1 ]] || [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
    show_help
fi

DOTFILE_PATH="$(normalize_path "$1")"
DESCRIPTION="${2:-}"

# ---------------------------------------------------------------------------
# Determine the dotfiles repo path
# ---------------------------------------------------------------------------
# Mirrors the file's path relative to $HOME inside $DOTFILES_DIR.
# Example: ~/.config/ghostty/config -> $DOTFILES_DIR/.config/ghostty/config
# Example: ~/.zshrc -> $DOTFILES_DIR/.zshrc

compute_dotfiles_dest() {
    local filepath="$1"
    local home_prefix="$HOME/"

    if [[ "$filepath" == "$home_prefix"* ]]; then
        local relative="${filepath#$home_prefix}"
        printf '%s/%s' "$DOTFILES_DIR" "$relative"
    else
        log_warn "File is not under \$HOME, using basename as fallback"
        printf '%s/%s' "$DOTFILES_DIR" "$(basename "$filepath")"
    fi
}

DOTFILES_DEST="$(compute_dotfiles_dest "$DOTFILE_PATH")"

# Auto-generate description from filename if not provided
if [[ -z "$DESCRIPTION" ]]; then
    DESCRIPTION="$(basename "$DOTFILE_PATH") configuration"
fi

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------
log_header "Add Dotfile: $(basename "$DOTFILE_PATH")"

# Check: does the file exist?
if [[ ! -e "$DOTFILE_PATH" ]]; then
    log_error "File does not exist: $DOTFILE_PATH"
    log_info "Make sure the path is correct and the file exists."
    exit 1
fi

# Check: is it already a symlink pointing to dotfiles?
if [[ -L "$DOTFILE_PATH" ]]; then
    local_target="$(readlink "$DOTFILE_PATH")"
    if [[ "$local_target" == "$DOTFILES_DIR"* ]]; then
        log_warn "This file is already a symlink to the dotfiles repo:"
        log_warn "  $DOTFILE_PATH -> $local_target"
        log_info "Nothing to do. Check dotfiles.conf if it needs a registry entry."
        exit 0
    fi
fi

# Check: is the destination already occupied in dotfiles repo?
if [[ -e "$DOTFILES_DEST" ]]; then
    log_warn "Destination already exists in dotfiles repo: $DOTFILES_DEST"
    log_info "The existing file will be backed up before overwriting."
fi

# Check: is this already in dotfiles.conf?
CONF_ENTRY_EXISTS=false
if [[ -f "$CONF_FILE" ]]; then
    local_dest_tilde="${DOTFILES_DEST/#$HOME/\~}"
    if grep -qF "$local_dest_tilde" "$CONF_FILE" 2>/dev/null; then
        CONF_ENTRY_EXISTS=true
        log_warn "Entry may already exist in dotfiles.conf"
    fi
fi

# ---------------------------------------------------------------------------
# Preview
# ---------------------------------------------------------------------------
printf "\n"
printf "  ${BOLD}Plan:${NC}\n"
printf "  %-20s %s\n" "File:" "$DOTFILE_PATH"
printf "  %-20s %s\n" "Move to:" "$DOTFILES_DEST"
printf "  %-20s %s -> %s\n" "Symlink:" "$DOTFILE_PATH" "$DOTFILES_DEST"
printf "  %-20s %s\n" "Description:" "$DESCRIPTION"
printf "  %-20s %s\n" "Registry:" "$CONF_FILE"
printf "\n"

# ---------------------------------------------------------------------------
# Confirmation
# ---------------------------------------------------------------------------
if ! confirm "Proceed with adding this dotfile?"; then
    log_info "Aborted by user."
    exit 0
fi

printf "\n"

# ---------------------------------------------------------------------------
# Step 1: Backup existing files
# ---------------------------------------------------------------------------
log_info "Step 1/6: Backing up existing files..."

backup_file "$DOTFILE_PATH" || true

if [[ -e "$DOTFILES_DEST" ]]; then
    backup_file "$DOTFILES_DEST" || true
fi

# ---------------------------------------------------------------------------
# Step 2: Ensure parent directory exists in dotfiles repo
# ---------------------------------------------------------------------------
log_info "Step 2/6: Preparing dotfiles directory..."
ensure_parent_dir "$DOTFILES_DEST"

# ---------------------------------------------------------------------------
# Step 3: Move file to dotfiles repo
# ---------------------------------------------------------------------------
log_info "Step 3/6: Moving file to dotfiles repo..."

if [[ -L "$DOTFILE_PATH" ]]; then
    # If it's a symlink, copy the target content, then remove the symlink
    cp -L "$DOTFILE_PATH" "$DOTFILES_DEST"
    rm "$DOTFILE_PATH"
else
    mv "$DOTFILE_PATH" "$DOTFILES_DEST"
fi

log_ok "Moved to: $DOTFILES_DEST"

# ---------------------------------------------------------------------------
# Step 4: Create symlink
# ---------------------------------------------------------------------------
log_info "Step 4/6: Creating symlink..."

ensure_parent_dir "$DOTFILE_PATH"
ln -s "$DOTFILES_DEST" "$DOTFILE_PATH"

log_ok "Symlink: $DOTFILE_PATH -> $DOTFILES_DEST"

# ---------------------------------------------------------------------------
# Step 5: Add to dotfiles.conf
# ---------------------------------------------------------------------------
if [[ "$CONF_ENTRY_EXISTS" == false ]]; then
    log_info "Step 5/6: Adding to dotfiles.conf..."

    # Convert paths to ~ notation for the config file
    local_source="${DOTFILES_DEST/#$HOME/\~}"
    local_dest="${DOTFILE_PATH/#$HOME/\~}"

    printf '%s:%s:%s\n' "$local_source" "$DESCRIPTION" "$local_dest" >> "$CONF_FILE"

    log_ok "Added to registry: $local_source"
else
    log_info "Step 5/6: Skipping registry (entry already exists)"
fi

# ---------------------------------------------------------------------------
# Step 6: Verify
# ---------------------------------------------------------------------------
log_info "Step 6/6: Verifying..."

if [[ -L "$DOTFILE_PATH" ]] && [[ -e "$DOTFILE_PATH" ]]; then
    local_target="$(readlink "$DOTFILE_PATH")"
    log_ok "Verification passed: $DOTFILE_PATH -> $local_target"
else
    log_error "Verification FAILED: symlink is broken or missing"
    log_error "Check the output above for errors. Your original file was backed up."
    exit 1
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
printf "\n"
log_header "Done"
printf "  ${GREEN}Successfully onboarded:${NC} %s\n" "$(basename "$DOTFILE_PATH")"
printf "  Managed in: %s\n" "$DOTFILES_DEST"
printf "  Symlinked:  %s -> %s\n" "$DOTFILE_PATH" "$DOTFILES_DEST"
printf "\n"
printf "  Next steps:\n"
printf "    cd %s && git add -A && git commit -m 'Add %s'\n" "$DOTFILES_DIR" "$(basename "$DOTFILE_PATH")"
printf "\n"
