#!/bin/bash
# cleanup-migration-backups.sh - Safe removal of post-home-cleanup.sh backup files
#
# After running home-cleanup.sh --execute, backup files remain in $HOME:
#   - *.pre-migration directories (safety copies of migrated data)
#   - .local/state/home-cleanup/manifest.json (migration state)
#   - rollback-home-cleanup.sh (auto-generated rollback script)
#   - .*.backup.* files (old config backups)
#
# This script finds all of them, verifies migrated tools still work,
# and optionally removes or archives them.
#
# Usage:
#   cleanup-migration-backups.sh              # Dry-run: show what would be deleted
#   cleanup-migration-backups.sh --execute    # Delete after confirmation
#   cleanup-migration-backups.sh --archive    # Archive backups first, then delete
#   cleanup-migration-backups.sh --force      # Skip confirmation (combine with --execute)
#
# Options:
#   --dry-run    (default) Show what would be deleted, change nothing
#   --execute    Actually delete backup files after confirmation
#   --archive    Archive all backups to a tarball before deleting
#   --force      Skip the interactive confirmation prompt
#   --keep-manifest  Keep manifest.json (useful for historical reference)
#   --help       Show this help message

set -euo pipefail

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

# XDG defaults
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

STATE_DIR="$XDG_STATE_HOME/home-cleanup"
MANIFEST_FILE="$STATE_DIR/manifest.json"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
EXECUTE=false
ARCHIVE=false
FORCE=false
KEEP_MANIFEST=false

usage() {
    printf "Usage: %s [--execute] [--archive] [--force] [--keep-manifest] [--help]\n" "$(basename "$0")"
    printf "\n"
    printf "Safe removal of post-home-cleanup.sh backup files.\n"
    printf "\n"
    printf "Options:\n"
    printf "  --dry-run        Show what would be deleted (default)\n"
    printf "  --execute        Actually delete backup files\n"
    printf "  --archive        Archive backups to tarball before deleting\n"
    printf "  --force          Skip confirmation prompt\n"
    printf "  --keep-manifest  Preserve manifest.json for historical reference\n"
    printf "  --help           Show this help message\n"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --execute)        EXECUTE=true; shift ;;
        --dry-run)        EXECUTE=false; shift ;;
        --archive)        ARCHIVE=true; EXECUTE=true; shift ;;
        --force)          FORCE=true; shift ;;
        --keep-manifest)  KEEP_MANIFEST=true; shift ;;
        --help|-h)        usage ;;
        *)
            log_error "Unknown option: $1"
            usage
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Reuse human_size and dir_size_bytes from home-cleanup.sh
# (These are defined inline since lib.sh doesn't include them)
# ---------------------------------------------------------------------------
human_size() {
    local bytes="$1"
    if [[ $bytes -ge 1073741824 ]]; then
        printf "%.1fG" "$(echo "scale=1; $bytes / 1073741824" | bc)"
    elif [[ $bytes -ge 1048576 ]]; then
        printf "%.0fM" "$(echo "scale=0; $bytes / 1048576" | bc)"
    elif [[ $bytes -ge 1024 ]]; then
        printf "%.0fK" "$(echo "scale=0; $bytes / 1024" | bc)"
    else
        printf "%dB" "$bytes"
    fi
}

dir_size_bytes() {
    local path="$1"
    if [[ -d "$path" ]]; then
        du -sk "$path" 2>/dev/null | awk '{print $1 * 1024}'
    elif [[ -f "$path" ]]; then
        stat -f%z "$path" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# ---------------------------------------------------------------------------
# Phase 1: Discover all backup files
# ---------------------------------------------------------------------------
BACKUP_ITEMS=()       # Full paths of items to remove
BACKUP_LABELS=()      # Human-readable labels
BACKUP_SIZES=()       # Size in bytes per item
TOTAL_SIZE_BYTES=0
TOTAL_ITEMS=0

discover_backups() {
    log_header "Scanning for backup files"

    # 1. Find *.pre-migration directories in $HOME
    while IFS= read -r -d '' dir; do
        local name
        name="$(basename "$dir")"
        local size
        size="$(dir_size_bytes "$dir")"
        BACKUP_ITEMS+=("$dir")
        BACKUP_LABELS+=("$name")
        BACKUP_SIZES+=("$size")
        TOTAL_SIZE_BYTES=$((TOTAL_SIZE_BYTES + size))
        TOTAL_ITEMS=$((TOTAL_ITEMS + 1))
    done < <(find "$HOME" -maxdepth 1 -name "*.pre-migration" -print0 2>/dev/null | sort -z)

    # 2. Find rollback-home-cleanup.sh (in script dir, not $HOME)
    local rollback_script="$SCRIPT_DIR/rollback-home-cleanup.sh"
    if [[ -f "$rollback_script" ]]; then
        local size
        size="$(dir_size_bytes "$rollback_script")"
        BACKUP_ITEMS+=("$rollback_script")
        BACKUP_LABELS+=("rollback-home-cleanup.sh")
        BACKUP_SIZES+=("$size")
        TOTAL_SIZE_BYTES=$((TOTAL_SIZE_BYTES + size))
        TOTAL_ITEMS=$((TOTAL_ITEMS + 1))
    fi

    # 3. Find manifest.json and state directory
    if [[ -d "$STATE_DIR" ]]; then
        local size
        size="$(dir_size_bytes "$STATE_DIR")"
        if [[ "$KEEP_MANIFEST" == true ]]; then
            BACKUP_LABELS+=("home-cleanup state dir (KEPT - --keep-manifest)")
        else
            BACKUP_LABELS+=("home-cleanup state dir")
        fi
        BACKUP_ITEMS+=("$STATE_DIR")
        BACKUP_SIZES+=("$size")
        TOTAL_SIZE_BYTES=$((TOTAL_SIZE_BYTES + size))
        TOTAL_ITEMS=$((TOTAL_ITEMS + 1))
    fi

    # 4. Find .*.backup.* files in $HOME (e.g., .zshenv.backup.20260206, .claude.json.backup.*)
    while IFS= read -r -d '' file; do
        local name
        name="$(basename "$file")"
        local size
        size="$(dir_size_bytes "$file")"
        BACKUP_ITEMS+=("$file")
        BACKUP_LABELS+=("$name")
        BACKUP_SIZES+=("$size")
        TOTAL_SIZE_BYTES=$((TOTAL_SIZE_BYTES + size))
        TOTAL_ITEMS=$((TOTAL_ITEMS + 1))
    done < <(find "$HOME" -maxdepth 1 -name ".*.backup.*" -print0 2>/dev/null | sort -z)
}

# ---------------------------------------------------------------------------
# Phase 2: Display found items
# ---------------------------------------------------------------------------
display_findings() {
    if [[ $TOTAL_ITEMS -eq 0 ]]; then
        printf "\n"
        log_ok "No backup files found. Home directory is already clean."
        exit 0
    fi

    printf "\n"
    printf "  ${BOLD}%-45s %10s${NC}\n" "File/Directory" "Size"
    printf "  %s\n" "$(printf '%.0s-' {1..56})"

    local i
    for i in "${!BACKUP_ITEMS[@]}"; do
        local path="${BACKUP_ITEMS[$i]}"
        local label="${BACKUP_LABELS[$i]}"
        local size="${BACKUP_SIZES[$i]}"
        local size_human
        size_human="$(human_size "$size")"
        local path_short="${path/#$HOME/~}"

        # Color based on type
        if [[ "$label" == *"KEPT"* ]]; then
            printf "  ${YELLOW}%-45s %10s${NC}\n" "$path_short" "$size_human"
        elif [[ "$label" == *.pre-migration ]]; then
            printf "  ${RED}%-45s %10s${NC}\n" "$path_short" "$size_human"
        else
            printf "  ${BLUE}%-45s %10s${NC}\n" "$path_short" "$size_human"
        fi
    done

    local total_human
    total_human="$(human_size "$TOTAL_SIZE_BYTES")"
    printf "  %s\n" "$(printf '%.0s-' {1..56})"
    printf "  ${BOLD}%-45s %10s${NC}\n" "Total ($TOTAL_ITEMS items)" "$total_human"
}

# ---------------------------------------------------------------------------
# Phase 3: Safety verification - test that migrated tools still work
# ---------------------------------------------------------------------------
SAFETY_PASS=0
SAFETY_FAIL=0
SAFETY_SKIP=0

run_safety_check() {
    local name="$1"
    local cmd="$2"

    # Check if command exists first
    local base_cmd
    base_cmd="$(echo "$cmd" | awk '{print $1}')"

    if ! command -v "$base_cmd" >/dev/null 2>&1; then
        printf "  ${YELLOW}%-25s %-30s -- Not installed${NC}\n" "$name" "$cmd"
        SAFETY_SKIP=$((SAFETY_SKIP + 1))
        return 0
    fi

    if eval "$cmd" >/dev/null 2>&1; then
        printf "  ${GREEN}%-25s %-30s OK${NC}\n" "$name" "$cmd"
        SAFETY_PASS=$((SAFETY_PASS + 1))
    else
        printf "  ${RED}%-25s %-30s FAILED${NC}\n" "$name" "$cmd"
        SAFETY_FAIL=$((SAFETY_FAIL + 1))
    fi
}

safety_verification() {
    printf "\n"
    log_header "Safety Verification"
    printf "  ${BOLD}Testing that migrated tools still work...${NC}\n\n"

    printf "  ${BOLD}%-25s %-30s %s${NC}\n" "Tool" "Command" "Status"
    printf "  %s\n" "$(printf '%.0s-' {1..62})"

    # Test commands matching what home-cleanup.sh used
    run_safety_check "npm"      "npm --version"
    run_safety_check "gem"      "gem env 2>/dev/null | head -1"
    run_safety_check "docker"   "docker version"
    run_safety_check "bun"      "bun --version"
    run_safety_check "vim"      "vim --version"
    run_safety_check "node"     "node --version"
    run_safety_check "dotnet"   "dotnet --info"
    run_safety_check "zsh"      "zsh --version"

    printf "  %s\n" "$(printf '%.0s-' {1..62})"
    printf "  ${BOLD}Results:${NC} ${GREEN}%d passed${NC}  ${RED}%d failed${NC}  ${YELLOW}%d skipped${NC}\n" \
        "$SAFETY_PASS" "$SAFETY_FAIL" "$SAFETY_SKIP"

    if [[ $SAFETY_FAIL -gt 0 ]]; then
        printf "\n"
        log_warn "Some tools are failing. This might mean migrations are broken."
        log_warn "Consider running rollback-home-cleanup.sh before deleting backups."

        if [[ "$EXECUTE" == true ]] && [[ "$FORCE" != true ]]; then
            printf "\n"
            if ! confirm "Safety checks have failures. Continue anyway?"; then
                log_info "Aborted by user."
                exit 1
            fi
        fi
    fi
}

# ---------------------------------------------------------------------------
# Phase 4: Archive backups
# ---------------------------------------------------------------------------
archive_backups() {
    local timestamp
    timestamp="$(date +%Y%m%d-%H%M%S)"
    local archive_path="$HOME/dotfiles-migration-backups-${timestamp}.tar.gz"

    printf "\n"
    log_header "Archiving Backups"
    log_info "Creating archive: ${archive_path/#$HOME/~}"

    # Build list of paths that actually exist
    local archive_paths=()
    for item in "${BACKUP_ITEMS[@]}"; do
        if [[ -e "$item" ]] || [[ -L "$item" ]]; then
            # Keep manifest if requested
            if [[ "$KEEP_MANIFEST" == true ]] && [[ "$item" == "$STATE_DIR" ]]; then
                continue
            fi
            archive_paths+=("$item")
        fi
    done

    if [[ ${#archive_paths[@]} -eq 0 ]]; then
        log_warn "No files to archive."
        return 0
    fi

    # Create tar archive with progress indication
    log_info "Compressing ${#archive_paths[@]} items..."

    if tar czf "$archive_path" "${archive_paths[@]}" 2>/dev/null; then
        local archive_size
        archive_size="$(dir_size_bytes "$archive_path")"
        local archive_human
        archive_human="$(human_size "$archive_size")"
        log_ok "Archive created: ${archive_path/#$HOME/~} ($archive_human)"
    else
        log_error "Failed to create archive"
        log_error "Aborting to prevent data loss"
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Phase 5: Delete backup files
# ---------------------------------------------------------------------------
delete_backups() {
    printf "\n"
    log_header "Deleting Backup Files"

    local deleted=0
    local failed=0

    for i in "${!BACKUP_ITEMS[@]}"; do
        local path="${BACKUP_ITEMS[$i]}"
        local label="${BACKUP_LABELS[$i]}"
        local path_short="${path/#$HOME/~}"

        # Skip manifest if --keep-manifest
        if [[ "$KEEP_MANIFEST" == true ]] && [[ "$path" == "$STATE_DIR" ]]; then
            log_info "Keeping: $path_short (--keep-manifest)"
            continue
        fi

        # Check if it still exists (idempotency)
        if [[ ! -e "$path" ]] && [[ ! -L "$path" ]]; then
            log_info "Already gone: $path_short"
            continue
        fi

        # Delete
        if rm -rf "$path" 2>/dev/null; then
            log_ok "Deleted: $path_short"
            deleted=$((deleted + 1))
        else
            log_error "Failed to delete: $path_short"
            failed=$((failed + 1))
        fi
    done

    printf "\n"
    printf "  ${BOLD}Deleted:${NC} %d items\n" "$deleted"
    if [[ $failed -gt 0 ]]; then
        printf "  ${RED}Failed:${NC}  %d items${NC}\n" "$failed"
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    # Header
    printf "\n"
    if [[ "$EXECUTE" == true ]]; then
        if [[ "$ARCHIVE" == true ]]; then
            log_header "Migration Backup Cleanup - ARCHIVE + DELETE MODE"
        else
            log_header "Migration Backup Cleanup - EXECUTE MODE"
        fi
    else
        printf "${BOLD}Migration Backup Cleanup - DRY-RUN${NC}\n"
        printf "%s\n" "$(printf '%.0s=' {1..64})"
        printf "\n"
        printf "  ${BLUE}This preview shows what would be cleaned up.${NC}\n"
        printf "  ${BLUE}No changes will be made.${NC}\n"
    fi

    # Phase 1 + 2: Find and display
    discover_backups
    display_findings

    # Phase 3: Safety checks
    safety_verification

    # Dry-run: show summary and exit
    if [[ "$EXECUTE" != true ]]; then
        local total_human
        total_human="$(human_size "$TOTAL_SIZE_BYTES")"

        printf "\n"
        printf "%s\n" "$(printf '%.0s=' {1..64})"
        printf "${BOLD}Summary:${NC}\n"
        printf "  Items found:  %d\n" "$TOTAL_ITEMS"
        printf "  Total size:   %s\n" "$total_human"
        printf "\n"
        printf "  ${BLUE}Status: DRY-RUN - no changes made${NC}\n"
        printf "\n"
        printf "  ${BOLD}Next steps:${NC}\n"
        printf "    %s --execute           ${BLUE}# Delete backups${NC}\n" "$(basename "$0")"
        printf "    %s --archive           ${BLUE}# Archive first, then delete${NC}\n" "$(basename "$0")"
        printf "    %s --execute --force   ${BLUE}# Delete without confirmation${NC}\n" "$(basename "$0")"
        printf "    %s --keep-manifest     ${BLUE}# Preserve manifest.json${NC}\n" "$(basename "$0")"
        printf "\n"
        exit 0
    fi

    # Execute mode: confirm
    if [[ "$FORCE" != true ]]; then
        local total_human
        total_human="$(human_size "$TOTAL_SIZE_BYTES")"
        printf "\n"
        log_warn "This will permanently delete $TOTAL_ITEMS items ($total_human)."

        if [[ "$ARCHIVE" == true ]]; then
            log_info "Backups will be archived first."
        fi

        printf "\n"
        if ! confirm "Proceed with deletion?"; then
            log_info "Aborted by user."
            exit 0
        fi
    fi

    # Phase 4: Archive (if requested)
    if [[ "$ARCHIVE" == true ]]; then
        archive_backups
    fi

    # Phase 5: Delete
    delete_backups

    # Final summary
    printf "\n"
    printf "%s\n" "$(printf '%.0s=' {1..64})"
    log_ok "Migration backup cleanup complete."

    if [[ "$ARCHIVE" == true ]]; then
        printf "\n"
        log_info "Archive saved in home directory."
        log_info "You can safely delete it once you are confident everything works."
    fi

    if [[ "$KEEP_MANIFEST" == true ]]; then
        printf "\n"
        log_info "Manifest preserved at: $MANIFEST_FILE"
    fi

    printf "\n"
}

main
