#!/bin/bash
# migrate-data-and-mg.sh
#
# Migrates two small dotdirectories to XDG-compliant locations:
#   ~/.data/          → ~/.local/share/homebox/
#   ~/.mg/            → ~/.config/mg/
#
# Safe by default (dry-run), with backups before any changes.
# Supports --dry-run (default), --execute, and --rollback modes.

set -euo pipefail

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILE_AUTOMATION_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source shared utilities
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

# Mode
MODE="${1:-}"
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

ROLLBACK="${ROLLBACK:-false}"

# ---------------------------------------------------------------------------
# Colors and logging setup
# ---------------------------------------------------------------------------

# (Already loaded via lib.sh)

# ---------------------------------------------------------------------------
# Migration Plan
# ---------------------------------------------------------------------------

log_header "XDG Migration Plan"

# .data migration
cat << 'EOF'

🗂️  MIGRATION 1: .data (660K) → ~/.local/share/homebox/
   ├─ Source:        ~/.data/
   │  ├─ homebox.db (4K)        — SQLite database
   │  ├─ homebox.db-shm (32K)   — Shared memory segment
   │  └─ homebox.db-wal (624K)  — Write-ahead log
   │
   ├─ Destination:  ~/.local/share/homebox/
   ├─ Backup:       ~/.data.backup.YYYYMMDD_HHMMSS/
   ├─ Symlink:      ~/.data → ~/.local/share/homebox/ (fallback)
   ├─ Env var:      HOMEBOX_DATA_HOME (if app supports)
   └─ Risk:         VERY LOW (small, no system dependency)

🗂️  MIGRATION 2: .mg (293B) → ~/.config/mg/
   ├─ Source:        ~/.mg/
   │  └─ mg.authrecord.json  — Microsoft Graph auth token
   │
   ├─ Destination:  ~/.config/mg/
   ├─ Backup:       ~/.mg.backup.YYYYMMDD_HHMMSS/
   ├─ Symlink:      ~/.mg → ~/.config/mg/ (fallback)
   ├─ Env var:      MG_AUTH_HOME (if CLI supports)
   └─ Risk:         VERY LOW (tiny, app-specific, not critical)

EOF

# ---------------------------------------------------------------------------
# Backup and migrate .data
# ---------------------------------------------------------------------------

migrate_data() {
    local source="$HOME/.data"
    local destination="$HOME/.local/share/homebox"

    if [[ ! -d "$source" ]]; then
        log_info "Source $source does not exist, skipping"
        return 0
    fi

    log_header "MIGRATION 1: .data → ~/.local/share/homebox/"

    # Show what will happen
    log_info "Current contents:"
    du -sh "$source"/*

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would perform the following steps:"
        log_info "  1. Backup: cp -r $source $source.backup.$(date +%Y%m%d_%H%M%S)"
        log_info "  2. Create: mkdir -p $destination"
        log_info "  3. Move:   mv $source/* $destination/"
        log_info "  4. Link:   ln -s $destination $source (fallback symlink)"
        return 0
    fi

    # EXECUTE mode
    local timestamp
    timestamp="$(date +%Y%m%d_%H%M%S)"
    local backup_path="${source}.backup.${timestamp}"

    # Step 1: Backup
    log_info "Creating backup: $backup_path"
    cp -r "$source" "$backup_path"
    log_ok "Backup created"

    # Step 2: Create destination
    log_info "Creating destination directory"
    mkdir -p "$destination"

    # Step 3: Move files
    log_info "Moving files from $source to $destination"
    mv "$source"/* "$destination/" 2>/dev/null || true

    # Step 4: Create fallback symlink
    log_info "Creating fallback symlink: $source → $destination"
    rm -rf "$source"
    ln -s "$destination" "$source"

    log_ok "Migration complete: .data → ~/.local/share/homebox/"
}

# ---------------------------------------------------------------------------
# Backup and migrate .mg
# ---------------------------------------------------------------------------

migrate_mg() {
    local source="$HOME/.mg"
    local destination="$HOME/.config/mg"

    if [[ ! -d "$source" ]]; then
        log_info "Source $source does not exist, skipping"
        return 0
    fi

    log_header "MIGRATION 2: .mg → ~/.config/mg/"

    # Show what will happen
    log_info "Current contents:"
    ls -lah "$source"/*

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would perform the following steps:"
        log_info "  1. Backup: cp -r $source $source.backup.$(date +%Y%m%d_%H%M%S)"
        log_info "  2. Create: mkdir -p $destination"
        log_info "  3. Move:   mv $source/* $destination/"
        log_info "  4. Link:   ln -s $destination $source (fallback symlink)"
        return 0
    fi

    # EXECUTE mode
    local timestamp
    timestamp="$(date +%Y%m%d_%H%M%S)"
    local backup_path="${source}.backup.${timestamp}"

    # Step 1: Backup
    log_info "Creating backup: $backup_path"
    cp -r "$source" "$backup_path"
    log_ok "Backup created"

    # Step 2: Create destination
    log_info "Creating destination directory"
    mkdir -p "$destination"

    # Step 3: Move files
    log_info "Moving files from $source to $destination"
    mv "$source"/* "$destination/" 2>/dev/null || true

    # Step 4: Create fallback symlink
    log_info "Creating fallback symlink: $source → $destination"
    rm -rf "$source"
    ln -s "$destination" "$source"

    log_ok "Migration complete: .mg → ~/.config/mg/"
}

# ---------------------------------------------------------------------------
# Rollback
# ---------------------------------------------------------------------------

rollback_migrations() {
    log_header "ROLLBACK: Restoring from backups"

    # Rollback .data
    if [[ -d "$HOME/.data.backup"* ]]; then
        log_info "Rolling back .data..."
        rm -rf "$HOME/.data"
        mv "$HOME"/.data.backup.* "$HOME/.data"
        log_ok "Restored .data"
    else
        log_warn "No .data backup found"
    fi

    # Rollback .mg
    if [[ -d "$HOME/.mg.backup"* ]]; then
        log_info "Rolling back .mg..."
        rm -rf "$HOME/.mg"
        mv "$HOME"/.mg.backup.* "$HOME/.mg"
        log_ok "Restored .mg"
    else
        log_warn "No .mg backup found"
    fi
}

# ---------------------------------------------------------------------------
# Main execution
# ---------------------------------------------------------------------------

main() {
    if [[ "$ROLLBACK" == "true" ]]; then
        rollback_migrations
        return 0
    fi

    log_header "macOS XDG Migration: .data and .mg"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "DRY-RUN MODE — No changes will be made"
        log_info "To execute: $0 --execute"
        log_info "To rollback: $0 --rollback"
    else
        log_warn "EXECUTE MODE — Changes will be made!"
        if ! confirm "Proceed with migrations?"; then
            log_info "Cancelled"
            return 1
        fi
    fi

    migrate_data
    migrate_mg

    log_header "Summary"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Dry-run complete. No changes made."
        log_info ""
        log_info "To execute these migrations, run:"
        log_info "  $0 --execute"
    else
        log_ok "Migrations complete!"
        log_info ""
        log_info "Files have been moved to XDG-compliant locations:"
        log_info "  ~/.data/  → ~/.local/share/homebox/"
        log_info "  ~/.mg/    → ~/.config/mg/"
        log_info ""
        log_info "Fallback symlinks created for backward compatibility."
        log_info ""
        if [[ -d "$HOME/.data.backup"* ]] || [[ -d "$HOME/.mg.backup"* ]]; then
            log_info "Backups available in HOME:"
            ls -d "$HOME"/.{data,mg}.backup.* 2>/dev/null || true
            log_info ""
            log_info "To rollback: $0 --rollback"
        fi
    fi
}

main "$@"
