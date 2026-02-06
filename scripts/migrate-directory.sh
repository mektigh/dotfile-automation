#!/bin/bash
# migrate-directory.sh - Generic directory migration tool
#
# Migrates ANY directory from one location to another with:
#   - Automatic backups before any changes
#   - Fallback symlinks for backward compatibility
#   - Safe dry-run mode (default)
#   - Rollback capability
#
# Usage:
#   migrate-directory.sh SOURCE DESTINATION [--dry-run|--execute|--rollback]
#
# Examples:
#   # Preview migration
#   migrate-directory.sh ~/.myapp ~/.config/myapp
#
#   # Execute migration
#   migrate-directory.sh ~/.myapp ~/.config/myapp --execute
#
#   # Rollback to backup
#   migrate-directory.sh ~/.myapp ~/.config/myapp --rollback
#
# How it works:
#   1. SOURCE must exist and be a directory
#   2. DESTINATION parent must exist (creates destination if needed)
#   3. Creates timestamped backup: SOURCE.backup.YYYYMMDD_HHMMSS
#   4. Moves SOURCE contents to DESTINATION
#   5. Creates symlink: SOURCE → DESTINATION (fallback)
#   6. Generates rollback script for easy reversal
#
# Safety:
#   - Dry-run by default (no changes without --execute)
#   - All backups kept until explicitly removed
#   - Fallback symlinks prevent application breakage
#   - Rollback script tracks exact backup location

set -euo pipefail

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILE_AUTOMATION_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source shared utilities
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------

SOURCE="${1:-}"
DESTINATION="${2:-}"
MODE="${3:-}"

# Default to dry-run
DRY_RUN=true
ROLLBACK=false

case "$MODE" in
    --dry-run)
        DRY_RUN=true
        ;;
    --execute)
        DRY_RUN=false
        ;;
    --rollback)
        DRY_RUN=false
        ROLLBACK=true
        ;;
    *)
        DRY_RUN=true
        ;;
esac

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

validate_inputs() {
    if [[ -z "$SOURCE" ]] || [[ -z "$DESTINATION" ]]; then
        log_error "Usage: migrate-directory.sh SOURCE DESTINATION [--dry-run|--execute|--rollback]"
        log_info ""
        log_info "Example:"
        log_info "  migrate-directory.sh ~/.myapp ~/.config/myapp --execute"
        return 1
    fi

    SOURCE="$(normalize_path "$SOURCE")"
    DESTINATION="$(normalize_path "$DESTINATION")"

    if [[ "$SOURCE" == "$DESTINATION" ]]; then
        log_error "SOURCE and DESTINATION cannot be the same"
        return 1
    fi

    if [[ ! -d "$SOURCE" ]]; then
        log_error "SOURCE does not exist: $SOURCE"
        return 1
    fi

    if [[ ! -d "$(dirname "$DESTINATION")" ]]; then
        log_error "DESTINATION parent directory does not exist: $(dirname "$DESTINATION")"
        log_info "Please create parent directory first: mkdir -p $(dirname "$DESTINATION")"
        return 1
    fi

    # Check for existing destination
    if [[ -d "$DESTINATION" ]]; then
        log_warn "DESTINATION already exists: $DESTINATION"
        log_info "Migration would merge contents into existing directory"
        if [[ "$DRY_RUN" == "false" ]]; then
            if ! confirm "Proceed with merge?"; then
                log_info "Cancelled"
                return 1
            fi
        fi
    fi

    # Check for existing backup
    local latest_backup
    latest_backup=$(find "$(dirname "$SOURCE")" -maxdepth 1 -type d -name "$(basename "$SOURCE").backup.*" 2>/dev/null | sort -r | head -1 || true)
    if [[ -n "$latest_backup" ]]; then
        log_info "Previous backup found: $latest_backup"
    fi

    return 0
}

# ---------------------------------------------------------------------------
# Migration
# ---------------------------------------------------------------------------

migrate() {
    log_header "Directory Migration"
    log_info "SOURCE:      $SOURCE"
    log_info "DESTINATION: $DESTINATION"
    log_info ""

    # Show what's in SOURCE
    local source_size
    source_size=$(du -sh "$SOURCE" 2>/dev/null | cut -f1)
    local file_count
    file_count=$(find "$SOURCE" -type f 2>/dev/null | wc -l)

    log_info "Contents:"
    log_info "  Size:  $source_size"
    log_info "  Files: $file_count"
    log_info ""

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "[DRY-RUN] No changes will be made"
        log_info ""
        log_info "Steps that would be performed:"
        log_info "  1. Create backup:   $(basename "$SOURCE").backup.$(date +%Y%m%d_%H%M%S)"
        log_info "  2. Create dest:     mkdir -p $DESTINATION"
        log_info "  3. Move contents:   mv $SOURCE/* $DESTINATION/"
        log_info "  4. Create symlink:  ln -s $DESTINATION $SOURCE"
        log_info ""
        log_info "To execute: migrate-directory.sh \"$SOURCE\" \"$DESTINATION\" --execute"
        log_info "To rollback: migrate-directory.sh \"$SOURCE\" \"$DESTINATION\" --rollback"
        return 0
    fi

    # EXECUTE MODE
    local timestamp
    timestamp="$(date +%Y%m%d_%H%M%S)"
    local backup_path="${SOURCE}.backup.${timestamp}"
    local rollback_script="${SOURCE}.rollback.${timestamp}.sh"

    # Step 1: Create backup
    log_info "Creating backup: $backup_path"
    cp -r "$SOURCE" "$backup_path"
    log_ok "Backup created"

    # Step 2: Create destination if needed
    if [[ ! -d "$DESTINATION" ]]; then
        log_info "Creating destination directory: $DESTINATION"
        mkdir -p "$DESTINATION"
    fi

    # Step 3: Move contents
    log_info "Moving contents from $SOURCE to $DESTINATION"
    mv "$SOURCE"/* "$DESTINATION/" 2>/dev/null || true

    # Remove source if empty
    if [[ -z "$(ls -A "$SOURCE" 2>/dev/null)" ]]; then
        rmdir "$SOURCE" 2>/dev/null || true
    fi

    # Step 4: Create fallback symlink
    log_info "Creating fallback symlink: $SOURCE → $DESTINATION"
    ln -s "$DESTINATION" "$SOURCE"

    # Step 5: Generate rollback script
    generate_rollback_script "$SOURCE" "$backup_path" "$DESTINATION" "$rollback_script"

    log_ok "Migration complete!"
    log_info ""
    log_info "Summary:"
    log_info "  Original:   $SOURCE (now → symlink to $DESTINATION)"
    log_info "  New home:   $DESTINATION"
    log_info "  Backup:     $backup_path"
    log_info ""
    log_info "To rollback: bash $rollback_script"
}

# ---------------------------------------------------------------------------
# Rollback
# ---------------------------------------------------------------------------

rollback() {
    log_header "Rollback: Restoring from backup"

    # Find latest backup
    local latest_backup
    latest_backup=$(find "$(dirname "$SOURCE")" -maxdepth 1 -type d -name "$(basename "$SOURCE").backup.*" 2>/dev/null | sort -r | head -1 || true)

    if [[ -z "$latest_backup" ]]; then
        log_error "No backup found for $SOURCE"
        log_info "Looking for: $(basename "$SOURCE").backup.* in $(dirname "$SOURCE")"
        return 1
    fi

    log_info "Found backup: $latest_backup"
    log_info ""

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "[DRY-RUN] Would restore from: $latest_backup"
        log_info ""
        log_info "To execute: migrate-directory.sh \"$SOURCE\" \"$DESTINATION\" --rollback"
        return 0
    fi

    # EXECUTE rollback
    log_info "Removing symlink and migrated content..."
    rm -rf "$SOURCE"

    log_info "Restoring from backup..."
    mv "$latest_backup" "$SOURCE"

    log_ok "Rollback complete. Restored from: $latest_backup"
}

# ---------------------------------------------------------------------------
# Rollback script generation
# ---------------------------------------------------------------------------

generate_rollback_script() {
    local source=$1
    local backup=$2
    local destination=$3
    local script_path=$4

    cat > "$script_path" << EOF
#!/bin/bash
# Auto-generated rollback script for directory migration
# Generated: $(date)
# Source:      $source
# Destination: $destination
# Backup:      $backup

set -euo pipefail

echo "Rolling back migration of $(basename "$source")..."
echo ""
echo "This will:"
echo "  1. Remove: $source (symlink)"
echo "  2. Remove: $destination (migrated contents)"
echo "  3. Restore: $backup → $source"
echo ""

if ! read -p "Proceed with rollback? [y/N]: " -r answer; then
    echo "Cancelled"
    exit 1
fi

case "\$answer" in
    [yY]|[yY][eE][sS])
        rm -rf "$source"
        if [[ -d "$destination" ]]; then
            rm -rf "$destination"
        fi
        mv "$backup" "$source"
        echo "✓ Rollback complete. Restored to: $source"
        ;;
    *)
        echo "Cancelled"
        exit 1
        ;;
esac
EOF

    chmod +x "$script_path"
    log_info "Generated rollback script: $script_path"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    log_header "migrate-directory.sh"

    if ! validate_inputs; then
        return 1
    fi

    if [[ "$ROLLBACK" == "true" ]]; then
        rollback
    else
        migrate
    fi
}

main "$@"
