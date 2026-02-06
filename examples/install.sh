#!/bin/bash
# install.sh - Install dotfile-automation on your system
#
# This script:
#   1. Detects or creates your dotfiles directory
#   2. Copies scripts to ~/.local/share/dotfile-automation
#   3. Creates symlinks in ~/.local/bin for easy access
#   4. Creates a .env config from .env.example
#   5. Creates a starter dotfiles.conf if none exists
#   6. Verifies the installation
#
# Usage:
#   ./examples/install.sh              # Interactive install
#   ./examples/install.sh --help       # Show help
#
# Requirements:
#   - macOS 11+ (Big Sur or later)
#   - bash 3.2+ (ships with macOS)
#   - rsync (ships with macOS)
#   - python3 (ships with macOS 12.3+)

set -euo pipefail

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

log_ok()    { printf "${GREEN}  [OK]${NC} %s\n" "$*"; }
log_error() { printf "${RED}  [ERROR]${NC} %s\n" "$*" >&2; }
log_warn()  { printf "${YELLOW}  [WARN]${NC} %s\n" "$*"; }
log_info()  { printf "${BLUE}  [INFO]${NC} %s\n" "$*"; }

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Install dotfile-automation on your system.

Options:
  --help, -h     Show this help message

What this does:
  1. Copies scripts to ~/.local/share/dotfile-automation/
  2. Creates symlinks in ~/.local/bin/ for each script
  3. Creates .env configuration from .env.example
  4. Copies example dotfiles.conf to your dotfiles directory
  5. Verifies everything works

After installation, you can run:
  symlink-check.sh        # Check your dotfile symlinks
  add-dotfile.sh           # Add a new dotfile to management
  home-cleanup.sh          # Clean up your HOME directory

Requirements:
  - macOS 11+ (Big Sur or later)
  - bash 3.2+
  - python3 (for home-cleanup manifest generation)
EOF
    exit 0
fi

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_DIR="$HOME/.local/share/dotfile-automation"
BIN_DIR="$HOME/.local/bin"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------
printf "\n"
printf "${BOLD}${BLUE}dotfile-automation installer${NC}\n"
printf "${BLUE}%s${NC}\n\n" "$(printf '%.0s-' {1..40})"

# Check macOS version
if [[ "$(uname)" != "Darwin" ]]; then
    log_warn "This tool is designed for macOS. It may work on Linux but is untested."
fi

# Check python3
if ! command -v python3 &>/dev/null; then
    log_error "python3 is required but not found."
    log_info "On macOS, install Xcode Command Line Tools: xcode-select --install"
    exit 1
fi

# Check rsync
if ! command -v rsync &>/dev/null; then
    log_error "rsync is required but not found."
    exit 1
fi

log_ok "Prerequisites met"

# ---------------------------------------------------------------------------
# Step 1: Create installation directory
# ---------------------------------------------------------------------------
printf "\n"
log_info "Step 1/5: Installing scripts..."

mkdir -p "$INSTALL_DIR/scripts"
mkdir -p "$INSTALL_DIR/examples"

# Copy scripts
cp "$REPO_DIR/scripts/lib.sh" "$INSTALL_DIR/scripts/"
cp "$REPO_DIR/scripts/symlink-check.sh" "$INSTALL_DIR/scripts/"
cp "$REPO_DIR/scripts/add-dotfile.sh" "$INSTALL_DIR/scripts/"
cp "$REPO_DIR/scripts/home-cleanup.sh" "$INSTALL_DIR/scripts/"

# Copy examples
cp "$REPO_DIR/examples/dotfiles.conf.example" "$INSTALL_DIR/examples/"

# Copy .env.example
cp "$REPO_DIR/.env.example" "$INSTALL_DIR/"

# Make scripts executable
chmod +x "$INSTALL_DIR/scripts/"*.sh

log_ok "Scripts installed to: $INSTALL_DIR"

# ---------------------------------------------------------------------------
# Step 2: Create .env configuration
# ---------------------------------------------------------------------------
printf "\n"
log_info "Step 2/5: Creating configuration..."

ENV_FILE="$INSTALL_DIR/.env"

if [[ -f "$ENV_FILE" ]]; then
    log_warn ".env already exists, keeping current configuration"
else
    cp "$INSTALL_DIR/.env.example" "$ENV_FILE"

    # Try to detect the user's dotfiles directory
    if [[ -d "$HOME/.dotfiles" ]]; then
        DOTFILES_DIR="$HOME/.dotfiles"
    elif [[ -d "$HOME/dotfiles" ]]; then
        DOTFILES_DIR="$HOME/dotfiles"
    fi

    # Update the .env with the detected dotfiles directory
    if [[ "$(uname)" == "Darwin" ]]; then
        sed -i '' "s|DOTFILES_DIR=\"\$HOME/.dotfiles\"|DOTFILES_DIR=\"$DOTFILES_DIR\"|" "$ENV_FILE"
    else
        sed -i "s|DOTFILES_DIR=\"\$HOME/.dotfiles\"|DOTFILES_DIR=\"$DOTFILES_DIR\"|" "$ENV_FILE"
    fi

    # Detect shell and set SHELL_ENV_FILE
    local_shell="$(basename "$SHELL")"
    case "$local_shell" in
        zsh)  shell_env="$HOME/.zshenv" ;;
        bash) shell_env="$HOME/.bashrc" ;;
        *)    shell_env="$HOME/.profile" ;;
    esac

    if [[ "$(uname)" == "Darwin" ]]; then
        sed -i '' "s|SHELL_ENV_FILE=\"\$HOME/.zshenv\"|SHELL_ENV_FILE=\"$shell_env\"|" "$ENV_FILE"
    else
        sed -i "s|SHELL_ENV_FILE=\"\$HOME/.zshenv\"|SHELL_ENV_FILE=\"$shell_env\"|" "$ENV_FILE"
    fi

    log_ok "Configuration created: $ENV_FILE"
    log_info "Dotfiles directory: $DOTFILES_DIR"
    log_info "Shell env file: $shell_env"
fi

# ---------------------------------------------------------------------------
# Step 3: Create symlinks in ~/.local/bin
# ---------------------------------------------------------------------------
printf "\n"
log_info "Step 3/5: Creating command symlinks..."

mkdir -p "$BIN_DIR"

for script in symlink-check.sh add-dotfile.sh home-cleanup.sh; do
    local_link="$BIN_DIR/$script"
    local_target="$INSTALL_DIR/scripts/$script"

    if [[ -L "$local_link" ]]; then
        rm -f "$local_link"
    elif [[ -e "$local_link" ]]; then
        log_warn "File exists at $local_link (not a symlink), skipping"
        continue
    fi

    ln -s "$local_target" "$local_link"
    log_ok "  $script -> $local_target"
done

# Check if ~/.local/bin is in PATH
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    log_warn "$BIN_DIR is not in your PATH"
    log_info "Add this to your shell config:"
    printf "\n"
    printf "    export PATH=\"\$HOME/.local/bin:\$PATH\"\n"
    printf "\n"
fi

# ---------------------------------------------------------------------------
# Step 4: Initialize dotfiles.conf
# ---------------------------------------------------------------------------
printf "\n"
log_info "Step 4/5: Setting up dotfiles registry..."

CONF_FILE="$DOTFILES_DIR/dotfiles.conf"

if [[ -f "$CONF_FILE" ]]; then
    log_ok "dotfiles.conf already exists: $CONF_FILE"
else
    if [[ -d "$DOTFILES_DIR" ]]; then
        cp "$INSTALL_DIR/examples/dotfiles.conf.example" "$CONF_FILE"
        log_ok "Created starter dotfiles.conf: $CONF_FILE"
        log_info "Edit this file to match your actual dotfiles."
    else
        log_warn "Dotfiles directory not found: $DOTFILES_DIR"
        log_info "Create it first, then copy the example:"
        printf "    mkdir -p %s\n" "$DOTFILES_DIR"
        printf "    cp %s %s\n" "$INSTALL_DIR/examples/dotfiles.conf.example" "$CONF_FILE"
    fi
fi

# ---------------------------------------------------------------------------
# Step 5: Verify installation
# ---------------------------------------------------------------------------
printf "\n"
log_info "Step 5/5: Verifying installation..."

VERIFY_OK=true

# Check scripts exist and are executable
for script in lib.sh symlink-check.sh add-dotfile.sh home-cleanup.sh; do
    if [[ -x "$INSTALL_DIR/scripts/$script" ]]; then
        log_ok "  $script is executable"
    else
        log_error "  $script is missing or not executable"
        VERIFY_OK=false
    fi
done

# Check symlinks
for script in symlink-check.sh add-dotfile.sh home-cleanup.sh; do
    if [[ -L "$BIN_DIR/$script" ]] && [[ -e "$BIN_DIR/$script" ]]; then
        log_ok "  $BIN_DIR/$script symlink OK"
    else
        log_warn "  $BIN_DIR/$script symlink missing or broken"
    fi
done

# Check .env
if [[ -f "$INSTALL_DIR/.env" ]]; then
    log_ok "  .env configuration exists"
else
    log_warn "  .env configuration missing"
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
printf "\n"
printf "${BOLD}${BLUE}Installation complete!${NC}\n"
printf "${BLUE}%s${NC}\n\n" "$(printf '%.0s-' {1..40})"

if [[ "$VERIFY_OK" == true ]]; then
    printf "  ${GREEN}All checks passed.${NC}\n\n"
else
    printf "  ${YELLOW}Some checks had warnings. See above.${NC}\n\n"
fi

printf "  ${BOLD}Quick start:${NC}\n"
printf "    symlink-check.sh           # Check your dotfile symlinks\n"
printf "    symlink-check.sh --fix     # Fix broken symlinks\n"
printf "    add-dotfile.sh ~/.vimrc    # Add a file to management\n"
printf "    home-cleanup.sh            # Preview HOME cleanup\n"
printf "\n"
printf "  ${BOLD}Configuration:${NC}\n"
printf "    Edit: %s\n" "$INSTALL_DIR/.env"
printf "    Registry: %s\n" "$CONF_FILE"
printf "\n"
printf "  ${BOLD}Documentation:${NC}\n"
printf "    README.md, INSTALL.md, USAGE.md in the repo\n"
printf "\n"
