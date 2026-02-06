#!/bin/bash
# migrate-dotfiles-to-xdg.sh - Migrate remaining dotfiles from $HOME to XDG locations
#
# Handles files that don't fit the directory-migration model of home-cleanup.sh.
# These are individual dotfiles (not directories) that can be relocated to
# XDG_CONFIG_HOME with env var or config-file support.
#
# Migrations:
#   .viminfo      -> .config/vim/viminfo       (VIMINIT env var)
#   .mime.types   -> .config/mime.types         (standard XDG lookup)
#   .mailcap      -> .config/mailcap            (MAILCAPS env var)
#   .claude.json  -> .config/claude/settings.json (symlink for compat)
#   .zsh_history  -> stays in place             (HISTFILE env var in .zshenv)
#
# Usage:
#   migrate-dotfiles-to-xdg.sh              # Preview (dry-run, default)
#   migrate-dotfiles-to-xdg.sh --execute    # Actually migrate
#   migrate-dotfiles-to-xdg.sh --help       # Show help
#
# Safety features:
#   - Dry-run by default (no changes without --execute)
#   - Backup before every move (.backup.YYYYMMDD_HHMMSS)
#   - Idempotent (safe to run multiple times)
#   - Creates missing directories automatically
#   - Updates env vars in .zshenv (avoids duplicates)
#   - Clear logging with color-coded output

set -euo pipefail

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

# Ensure XDG vars are available
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

ZSHENV_FILE="$HOME/.dotfiles/.zshenv"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
EXECUTE=false

usage() {
    printf "Usage: %s [--execute] [--dry-run] [--help]\n\n" "$(basename "$0")"
    printf "Migrate remaining dotfiles from HOME to XDG-compliant locations.\n\n"
    printf "Options:\n"
    printf "  --execute    Actually perform migrations (default: dry-run)\n"
    printf "  --dry-run    Show what would happen without changes (default)\n"
    printf "  --help       Show this help message\n"
    printf "\nMigrations:\n"
    printf "  .viminfo      -> .config/vim/viminfo\n"
    printf "  .mime.types   -> .config/mime.types\n"
    printf "  .mailcap      -> .config/mailcap\n"
    printf "  .claude.json  -> .config/claude/settings.json\n"
    printf "  .zsh_history  -> HISTFILE env var (file stays in place)\n"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --execute)  EXECUTE=true; shift ;;
        --dry-run)  EXECUTE=false; shift ;;
        --help|-h)  usage ;;
        *)
            log_error "Unknown option: $1"
            usage
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Counters
# ---------------------------------------------------------------------------
TOTAL=0
MIGRATED=0
SKIPPED=0
FAILED=0
ENV_VARS_ADDED=()

# ---------------------------------------------------------------------------
# Utility: add env var to .zshenv (idempotent)
# ---------------------------------------------------------------------------
add_zshenv_var() {
    local var_name="$1"
    local var_value="$2"
    local comment="${3:-Added by migrate-dotfiles-to-xdg.sh}"

    if [[ ! -f "$ZSHENV_FILE" ]]; then
        log_warn "Cannot add env var: $ZSHENV_FILE not found"
        return 1
    fi

    # Already set? Skip.
    if grep -q "^export ${var_name}=" "$ZSHENV_FILE" 2>/dev/null; then
        log_info "Env var $var_name already set in .zshenv"
        return 0
    fi

    printf '\n# %s on %s\nexport %s="%s"\n' \
        "$comment" "$(date +%Y-%m-%d)" "$var_name" "$var_value" >> "$ZSHENV_FILE"

    ENV_VARS_ADDED+=("$var_name")
    log_ok "Added $var_name to .zshenv"
    return 0
}

# ---------------------------------------------------------------------------
# Core: migrate a single dotfile
# ---------------------------------------------------------------------------
# Arguments:
#   $1 = label (human-readable name)
#   $2 = source path (e.g. ~/.viminfo)
#   $3 = destination path (e.g. ~/.config/vim/viminfo)
#   $4 = strategy: "move" | "move+symlink" | "envvar-only"
#   $5 = env var name (optional)
#   $6 = env var value (optional)
#   $7 = env var comment (optional)
#   $8 = post-migration note (optional)
migrate_dotfile() {
    local label="$1"
    local source="$2"
    local destination="$3"
    local strategy="$4"
    local env_var_name="${5:-}"
    local env_var_value="${6:-}"
    local env_var_comment="${7:-Added by migrate-dotfiles-to-xdg.sh}"
    local note="${8:-}"

    TOTAL=$((TOTAL + 1))

    local source_short="${source/#$HOME/\~}"
    local dest_short="${destination/#$HOME/\~}"

    # --- Idempotency checks ---

    # If source is a symlink pointing to destination, already done
    if [[ -L "$source" ]]; then
        local target
        target="$(readlink "$source" 2>/dev/null || true)"
        if [[ "$target" == "$destination" ]]; then
            if [[ "$EXECUTE" == true ]]; then
                log_info "Skipping $label: already migrated (symlink in place)"
            else
                printf "  ${GREEN}[x]${NC} %-25s ${GREEN}ALREADY DONE${NC} (symlink)\n" "$label"
            fi
            SKIPPED=$((SKIPPED + 1))
            return 0
        fi
    fi

    # If source doesn't exist but destination does, already done
    if [[ ! -e "$source" ]] && [[ ! -L "$source" ]] && [[ -e "$destination" ]]; then
        if [[ "$EXECUTE" == true ]]; then
            log_info "Skipping $label: already migrated (destination exists)"
        else
            printf "  ${GREEN}[x]${NC} %-25s ${GREEN}ALREADY DONE${NC} (at destination)\n" "$label"
        fi
        SKIPPED=$((SKIPPED + 1))
        return 0
    fi

    # For envvar-only strategy, check if env var is already set
    if [[ "$strategy" == "envvar-only" ]]; then
        if [[ -n "$env_var_name" ]] && grep -q "^export ${env_var_name}=" "$ZSHENV_FILE" 2>/dev/null; then
            if [[ "$EXECUTE" == true ]]; then
                log_info "Skipping $label: env var already configured"
            else
                printf "  ${GREEN}[x]${NC} %-25s ${GREEN}ALREADY DONE${NC} (env var set)\n" "$label"
            fi
            SKIPPED=$((SKIPPED + 1))
            return 0
        fi
    fi

    # Source must exist for move strategies
    if [[ "$strategy" != "envvar-only" ]]; then
        if [[ ! -e "$source" ]] && [[ ! -L "$source" ]]; then
            if [[ "$EXECUTE" == true ]]; then
                log_warn "Skipping $label: source does not exist ($source_short)"
            else
                printf "  ${YELLOW}[ ]${NC} %-25s ${YELLOW}NOT FOUND${NC} (%s)\n" "$label" "$source_short"
            fi
            SKIPPED=$((SKIPPED + 1))
            return 0
        fi
    fi

    # --- Dry-run output ---
    if [[ "$EXECUTE" != true ]]; then
        local size_human="0B"
        if [[ -f "$source" ]]; then
            local size_bytes
            size_bytes="$(stat -f%z "$source" 2>/dev/null || echo 0)"
            if [[ $size_bytes -ge 1024 ]]; then
                size_human="$(printf "%.0fK" "$(echo "scale=0; $size_bytes / 1024" | bc)")"
            else
                size_human="${size_bytes}B"
            fi
        fi

        printf "  ${BLUE}[ ]${NC} %-25s (%s)\n" "$label" "$size_human"
        printf "      ${BOLD}From:${NC}     %s\n" "$source_short"

        if [[ "$strategy" != "envvar-only" ]]; then
            printf "      ${BOLD}To:${NC}       %s\n" "$dest_short"
        fi

        printf "      ${BOLD}Strategy:${NC} %s\n" "$strategy"

        if [[ -n "$env_var_name" ]]; then
            printf "      ${BOLD}Env var:${NC}  %s=%s\n" "$env_var_name" "$env_var_value"
        fi

        if [[ -n "$note" ]]; then
            printf "      ${BOLD}Note:${NC}     %s\n" "$note"
        fi

        printf "\n"
        return 0
    fi

    # --- Execute mode ---
    log_info "Migrating $label..."

    # Step 1: Create destination directory
    if [[ "$strategy" != "envvar-only" ]]; then
        local dest_dir
        dest_dir="$(dirname "$destination")"
        if [[ ! -d "$dest_dir" ]]; then
            mkdir -p "$dest_dir"
            log_info "  Created directory: ${dest_dir/#$HOME/\~}"
        fi
    fi

    # Step 2: Backup the source
    if [[ "$strategy" != "envvar-only" ]] && [[ -e "$source" ]] && [[ ! -L "$source" ]]; then
        backup_file "$source"
    fi

    # Step 3: Copy file to destination
    if [[ "$strategy" != "envvar-only" ]]; then
        if [[ -e "$destination" ]]; then
            log_warn "  Destination already exists, creating backup of destination"
            backup_file "$destination"
        fi

        if ! cp -a "$source" "$destination"; then
            log_error "  Failed to copy $source_short to $dest_short"
            FAILED=$((FAILED + 1))
            return 1
        fi
        log_ok "  Copied: $source_short -> $dest_short"
    fi

    # Step 4: Create symlink (if move+symlink strategy)
    if [[ "$strategy" == "move+symlink" ]]; then
        rm -f "$source"
        if ! ln -s "$destination" "$source"; then
            log_error "  Failed to create symlink: $source_short -> $dest_short"
            FAILED=$((FAILED + 1))
            return 1
        fi
        log_ok "  Symlink: $source_short -> $dest_short"
    elif [[ "$strategy" == "move" ]]; then
        rm -f "$source"
        log_ok "  Removed original: $source_short"
    fi

    # Step 5: Set environment variable
    if [[ -n "$env_var_name" ]] && [[ -n "$env_var_value" ]]; then
        add_zshenv_var "$env_var_name" "$env_var_value" "$env_var_comment"
    fi

    MIGRATED=$((MIGRATED + 1))
    log_ok "Migrated $label"
    return 0
}

# ---------------------------------------------------------------------------
# Migration definitions
# ---------------------------------------------------------------------------

run_migrations() {
    # -----------------------------------------------------------------------
    # 1. .viminfo -> .config/vim/viminfo
    # -----------------------------------------------------------------------
    # Vim writes session state (marks, registers, search history, command
    # history) to .viminfo. The VIMINIT env var tells vim to use an
    # alternate vimrc location, and we set viminfofile inside that config
    # to redirect .viminfo to the XDG location.
    #
    # The VIMINIT env var makes vim source .config/vim/vimrc instead of
    # ~/.vimrc, and that vimrc should contain:
    #   set viminfofile=~/.config/vim/viminfo
    # -----------------------------------------------------------------------
    migrate_dotfile \
        ".viminfo" \
        "$HOME/.viminfo" \
        "$XDG_CONFIG_HOME/vim/viminfo" \
        "move" \
        "VIMINIT" \
        'source $XDG_CONFIG_HOME/vim/vimrc' \
        "Vim XDG compliance" \
        "Requires vimrc at ~/.config/vim/vimrc with: set viminfofile=~/.config/vim/viminfo"

    # -----------------------------------------------------------------------
    # 2. .mime.types -> .config/mime.types
    # -----------------------------------------------------------------------
    # MIME type mappings used by mailcap-aware programs. The XDG location
    # is a standard lookup path for many tools. No env var needed -- tools
    # check ~/.config/mime.types by convention when XDG_CONFIG_HOME is set.
    # -----------------------------------------------------------------------
    migrate_dotfile \
        ".mime.types" \
        "$HOME/.mime.types" \
        "$XDG_CONFIG_HOME/mime.types" \
        "move" \
        "" "" "" \
        "Standard XDG lookup path for MIME types"

    # -----------------------------------------------------------------------
    # 3. .mailcap -> .config/mailcap
    # -----------------------------------------------------------------------
    # Mailcap defines how to handle MIME types (which program opens what).
    # The MAILCAPS env var tells mailcap-aware programs where to find it.
    # Format: colon-separated list of mailcap files.
    # -----------------------------------------------------------------------
    migrate_dotfile \
        ".mailcap" \
        "$HOME/.mailcap" \
        "$XDG_CONFIG_HOME/mailcap" \
        "move" \
        "MAILCAPS" \
        '$XDG_CONFIG_HOME/mailcap' \
        "Mailcap XDG compliance" \
        "Programs using mailcap will check MAILCAPS env var"

    # -----------------------------------------------------------------------
    # 4. .claude.json -> .config/claude/settings.json
    # -----------------------------------------------------------------------
    # Claude Code CLI stores its settings in ~/.claude.json. A symlink
    # maintains backward compatibility while the actual file lives in
    # the XDG config location.
    #
    # Strategy: move+symlink because Claude CLI hardcodes ~/.claude.json
    # and does not respect XDG. The symlink ensures it keeps working.
    # -----------------------------------------------------------------------
    migrate_dotfile \
        ".claude.json" \
        "$HOME/.claude.json" \
        "$XDG_CONFIG_HOME/claude/settings.json" \
        "move+symlink" \
        "" "" "" \
        "Symlink keeps Claude CLI working (hardcoded path)"

    # -----------------------------------------------------------------------
    # 5. .zsh_history - configure HISTFILE
    # -----------------------------------------------------------------------
    # Zsh history file stays in $HOME (it's a critical file that should
    # remain accessible). We just ensure HISTFILE is explicitly set in
    # .zshenv so it's documented and controllable.
    #
    # This is "envvar-only" -- we don't move the file, just ensure the
    # env var is declared for clarity and future flexibility.
    # -----------------------------------------------------------------------
    migrate_dotfile \
        ".zsh_history" \
        "$HOME/.zsh_history" \
        "" \
        "envvar-only" \
        "HISTFILE" \
        '$HOME/.zsh_history' \
        "Zsh history location (explicit)" \
        "File stays in HOME -- HISTFILE set for explicit documentation"
}

# ---------------------------------------------------------------------------
# Vim vimrc setup helper
# ---------------------------------------------------------------------------
ensure_vim_xdg_vimrc() {
    local vimrc="$XDG_CONFIG_HOME/vim/vimrc"

    if [[ -f "$vimrc" ]]; then
        # Check if viminfofile is already set
        if grep -q "viminfofile" "$vimrc" 2>/dev/null; then
            log_info "Vim vimrc already has viminfofile setting"
            return 0
        fi

        # Append viminfofile setting
        if [[ "$EXECUTE" == true ]]; then
            printf '\n" XDG: Store viminfo in config directory\nset viminfofile=%s/vim/viminfo\n' \
                '$XDG_CONFIG_HOME' >> "$vimrc"
            log_ok "Added viminfofile setting to existing vimrc"
        else
            log_info "Would add viminfofile setting to existing vimrc"
        fi
    else
        # Create minimal vimrc
        if [[ "$EXECUTE" == true ]]; then
            mkdir -p "$(dirname "$vimrc")"
            cat > "$vimrc" << 'VIMRC'
" vimrc - XDG-compliant vim configuration
" Location: ~/.config/vim/vimrc
" Loaded via VIMINIT env var

" Store viminfo in XDG config directory
set viminfofile=$XDG_CONFIG_HOME/vim/viminfo

" Source the original vimrc if it exists (migration compatibility)
if filereadable(expand('~/.vimrc'))
    source ~/.vimrc
endif
VIMRC
            log_ok "Created XDG vimrc at ${vimrc/#$HOME/\~}"
        else
            printf "  ${BLUE}[+]${NC} %-25s Will create %s\n\n" "vim vimrc" "${vimrc/#$HOME/\~}"
        fi
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    # Header
    if [[ "$EXECUTE" == true ]]; then
        printf "\n"
        log_header "Dotfile XDG Migration - EXECUTE MODE"
        log_warn "This will modify files in your home directory!"
        printf "\n"

        if ! confirm "Proceed with dotfile migrations?"; then
            log_info "Aborted by user."
            exit 0
        fi
    else
        printf "\n"
        printf "${BOLD}Dotfile XDG Migration - DRY-RUN${NC}\n"
        printf "%s\n" "$(printf '%.0s=' {1..64})"
        printf "\n"
        printf "  ${BLUE}This preview shows what would happen with --execute.${NC}\n"
        printf "  ${BLUE}No changes will be made.${NC}\n"
        printf "\n"
    fi

    # Run all migrations
    run_migrations

    # Ensure vim has proper XDG vimrc
    if [[ "$EXECUTE" == true ]]; then
        log_header "Vim XDG Setup"
    else
        printf "${BOLD}Vim XDG vimrc:${NC}\n\n"
    fi
    ensure_vim_xdg_vimrc

    # Summary
    printf "\n"
    printf "%s\n" "$(printf '%.0s=' {1..64})"

    if [[ "$EXECUTE" != true ]]; then
        printf "${BOLD}Summary:${NC}\n"
        printf "  Items to migrate:     %d\n" "$TOTAL"
        printf "  Already migrated:     %d\n" "$SKIPPED"
        printf "  Pending:              %d\n" "$((TOTAL - SKIPPED))"
        printf "\n"
        printf "  ${BLUE}Status: DRY-RUN - no changes made${NC}\n"
        printf "  ${BOLD}Next:${NC}   Run with ${BOLD}--execute${NC} to proceed\n"
    else
        printf "${BOLD}Migration Summary:${NC}\n"
        printf "  Migrated:  %d\n" "$MIGRATED"
        printf "  Skipped:   %d\n" "$SKIPPED"
        printf "  Failed:    %d\n" "$FAILED"
        printf "  Total:     %d items\n" "$TOTAL"

        if [[ ${#ENV_VARS_ADDED[@]} -gt 0 ]]; then
            printf "\n"
            printf "  ${BOLD}Env vars added to .zshenv:${NC}\n"
            for var in "${ENV_VARS_ADDED[@]}"; do
                printf "    - %s\n" "$var"
            done
        fi

        if [[ $FAILED -gt 0 ]]; then
            printf "\n"
            log_warn "$FAILED migration(s) failed. Check output above for details."
            log_warn "Backups preserved with .backup.TIMESTAMP suffix."
        fi

        # Post-migration instructions
        printf "\n"
        log_header "Next Steps"
        printf "  1. Reload your shell:  ${BOLD}source ~/.zshenv${NC}\n"
        printf "  2. Test vim:           ${BOLD}vim +q  # should create viminfo in .config/vim/${NC}\n"
        printf "  3. Test Claude CLI:    ${BOLD}ls -la ~/.claude.json  # should be symlink${NC}\n"
        printf "  4. Verify HISTFILE:    ${BOLD}echo \$HISTFILE${NC}\n"
    fi

    # Rollback instructions
    printf "\n"
    printf "  ${BOLD}Rollback:${NC}\n"
    printf "    Backups are stored as FILENAME.backup.YYYYMMDD_HHMMSS\n"
    printf "    To undo a migration:\n"
    printf "      1. Remove the symlink/destination file\n"
    printf "      2. Rename the backup back to the original name\n"
    printf "      3. Remove the env var from .zshenv\n"

    printf "\n"
}

main
