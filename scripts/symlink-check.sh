#!/bin/bash
# symlink-check.sh - Validate and optionally repair dotfile symlinks
#
# Reads your dotfiles.conf registry and verifies each symlink is:
#   - Present at the destination
#   - Actually a symlink (not a regular file)
#   - Pointing to the correct source
#   - Source file exists
#
# Usage:
#   symlink-check.sh              # Check all symlinks, report status
#   symlink-check.sh --fix        # Check and repair broken symlinks
#   symlink-check.sh --dry-run    # Show what --fix would do, without doing it
#   symlink-check.sh --conf FILE  # Use a specific config file
#
# Exit codes:
#   0 = All symlinks OK (or all fixed successfully)
#   1 = Problems found (without --fix) or fix failed

set -euo pipefail

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

# Parse arguments
FIX_MODE=false
DRY_RUN=false
CUSTOM_CONF=""

show_help() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Validate and optionally repair dotfile symlinks defined in dotfiles.conf.

Options:
  --fix           Repair broken or missing symlinks
  --dry-run       Show what --fix would do without making changes
  --conf FILE     Use a specific config file (default: \$CONF_FILE)
  --help, -h      Show this help message

Environment variables:
  DOTFILES_DIR    Path to your dotfiles repo (default: \$HOME/.dotfiles)
  CONF_FILE       Path to your dotfiles.conf (default: \$DOTFILES_DIR/dotfiles.conf)

Examples:
  $(basename "$0")                    # Check all symlinks
  $(basename "$0") --fix              # Fix broken symlinks
  $(basename "$0") --dry-run          # Preview fixes
  $(basename "$0") --conf my.conf     # Use custom config

Exit codes:
  0  All symlinks are correct (or were fixed)
  1  Problems found or fix failed
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --fix)      FIX_MODE=true; shift ;;
        --dry-run)  DRY_RUN=true; FIX_MODE=true; shift ;;
        --conf)
            if [[ -z "${2:-}" ]]; then
                log_error "--conf requires a file path argument"
                exit 1
            fi
            CUSTOM_CONF="$2"; shift 2
            ;;
        --help|-h)  show_help ;;
        -*)
            log_error "Unknown option: $1"
            log_info "Run with --help for usage information"
            exit 1
            ;;
        *)  shift ;;
    esac
done

# Use custom conf if provided, otherwise use default from .env
ACTIVE_CONF="${CUSTOM_CONF:-$CONF_FILE}"

if [[ ! -f "$ACTIVE_CONF" ]]; then
    log_error "Config file not found: $ACTIVE_CONF"
    log_info "Create one from the example: cp examples/dotfiles.conf.example \$DOTFILES_DIR/dotfiles.conf"
    exit 1
fi

# ---------------------------------------------------------------------------
# Counters
# ---------------------------------------------------------------------------
COUNT_OK=0
COUNT_BROKEN=0
COUNT_WRONG_TARGET=0
COUNT_NOT_SYMLINK=0
COUNT_MISSING_SOURCE=0
COUNT_MISSING_DEST=0
COUNT_FIXED=0
COUNT_FAILED=0

# ---------------------------------------------------------------------------
# Fix a symlink: backup old, create new
# ---------------------------------------------------------------------------
fix_symlink() {
    local source="$1"
    local destination="$2"
    local reason="$3"

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY-RUN] Would fix: $destination -> $source ($reason)"
        COUNT_FIXED=$((COUNT_FIXED + 1))
        return 0
    fi

    # Backup existing file/symlink before touching it
    if [[ -e "$destination" ]] || [[ -L "$destination" ]]; then
        if ! backup_file "$destination"; then
            log_error "Backup failed for $destination, skipping fix"
            COUNT_FAILED=$((COUNT_FAILED + 1))
            return 1
        fi
        rm -f "$destination"
    fi

    # Ensure parent directory exists
    ensure_parent_dir "$destination"

    # Create the symlink
    if ln -s "$source" "$destination"; then
        log_ok "Fixed: $destination -> $source"
        COUNT_FIXED=$((COUNT_FIXED + 1))
    else
        log_error "Failed to create symlink: $destination -> $source"
        COUNT_FAILED=$((COUNT_FAILED + 1))
    fi
}

# ---------------------------------------------------------------------------
# Check a single dotfile entry
# ---------------------------------------------------------------------------
check_entry() {
    local source="$1"
    local description="$2"
    local destination="$3"

    printf "  %-45s " "$description"

    # Case 1: Source file does not exist
    if [[ ! -e "$source" ]]; then
        printf "${YELLOW}MISSING_SOURCE${NC} (source: %s)\n" "$source"
        COUNT_MISSING_SOURCE=$((COUNT_MISSING_SOURCE + 1))
        if [[ "$FIX_MODE" == true ]]; then
            log_warn "Cannot fix: source file does not exist: $source"
        fi
        return
    fi

    # Case 2: Destination does not exist at all (no file, no symlink)
    if [[ ! -e "$destination" ]] && [[ ! -L "$destination" ]]; then
        printf "${RED}MISSING${NC} (expected: %s)\n" "$destination"
        COUNT_MISSING_DEST=$((COUNT_MISSING_DEST + 1))
        if [[ "$FIX_MODE" == true ]]; then
            fix_symlink "$source" "$destination" "missing"
        fi
        return
    fi

    # Case 3: Destination exists but is NOT a symlink (regular file)
    if [[ ! -L "$destination" ]]; then
        printf "${YELLOW}NOT_SYMLINK${NC} (regular file at %s)\n" "$destination"
        COUNT_NOT_SYMLINK=$((COUNT_NOT_SYMLINK + 1))
        if [[ "$FIX_MODE" == true ]]; then
            fix_symlink "$source" "$destination" "was regular file"
        fi
        return
    fi

    # Destination IS a symlink -- check where it points
    local current_target
    current_target="$(readlink "$destination")"

    # Case 4: Symlink exists but is broken (target doesn't exist)
    if [[ ! -e "$destination" ]]; then
        printf "${RED}BROKEN${NC} (points to: %s)\n" "$current_target"
        COUNT_BROKEN=$((COUNT_BROKEN + 1))
        if [[ "$FIX_MODE" == true ]]; then
            fix_symlink "$source" "$destination" "broken symlink"
        fi
        return
    fi

    # Case 5: Symlink exists and works, but points to wrong target
    local resolved_current resolved_expected
    resolved_current="$(cd "$(dirname "$destination")" && realpath "$current_target" 2>/dev/null || echo "$current_target")"
    resolved_expected="$(realpath "$source" 2>/dev/null || echo "$source")"

    if [[ "$resolved_current" != "$resolved_expected" ]]; then
        printf "${YELLOW}WRONG_TARGET${NC}\n"
        printf "    current:  %s\n" "$current_target"
        printf "    expected: %s\n" "$source"
        COUNT_WRONG_TARGET=$((COUNT_WRONG_TARGET + 1))
        if [[ "$FIX_MODE" == true ]]; then
            fix_symlink "$source" "$destination" "wrong target"
        fi
        return
    fi

    # Case 6: Everything is correct
    printf "${GREEN}OK${NC}\n"
    COUNT_OK=$((COUNT_OK + 1))
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
log_header "Dotfile Symlink Check"

if [[ "$DRY_RUN" == true ]]; then
    log_info "DRY-RUN mode: no changes will be made"
elif [[ "$FIX_MODE" == true ]]; then
    log_warn "FIX mode: broken symlinks will be repaired"
fi

log_info "Config: $ACTIVE_CONF"
printf "\n"

# Run the check against every entry in the config
parse_dotfiles_conf "$ACTIVE_CONF" check_entry

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
TOTAL=$((COUNT_OK + COUNT_BROKEN + COUNT_WRONG_TARGET + COUNT_NOT_SYMLINK + COUNT_MISSING_SOURCE + COUNT_MISSING_DEST))

printf "\n"
log_header "Summary"
printf "  Total entries:     %d\n" "$TOTAL"
printf "  ${GREEN}OK:${NC}                %d\n" "$COUNT_OK"
[[ $COUNT_BROKEN -gt 0 ]]         && printf "  ${RED}Broken:${NC}            %d\n" "$COUNT_BROKEN"
[[ $COUNT_WRONG_TARGET -gt 0 ]]   && printf "  ${YELLOW}Wrong target:${NC}      %d\n" "$COUNT_WRONG_TARGET"
[[ $COUNT_NOT_SYMLINK -gt 0 ]]    && printf "  ${YELLOW}Not a symlink:${NC}     %d\n" "$COUNT_NOT_SYMLINK"
[[ $COUNT_MISSING_SOURCE -gt 0 ]] && printf "  ${YELLOW}Missing source:${NC}    %d\n" "$COUNT_MISSING_SOURCE"
[[ $COUNT_MISSING_DEST -gt 0 ]]   && printf "  ${RED}Missing dest:${NC}      %d\n" "$COUNT_MISSING_DEST"

if [[ "$FIX_MODE" == true ]]; then
    printf "\n"
    if [[ "$DRY_RUN" == true ]]; then
        printf "  ${BLUE}Would fix:${NC}         %d\n" "$COUNT_FIXED"
    else
        [[ $COUNT_FIXED -gt 0 ]]  && printf "  ${GREEN}Fixed:${NC}             %d\n" "$COUNT_FIXED"
        [[ $COUNT_FAILED -gt 0 ]] && printf "  ${RED}Failed to fix:${NC}     %d\n" "$COUNT_FAILED"
    fi
fi

printf "\n"

# Exit with error if there are unresolved problems
PROBLEMS=$((COUNT_BROKEN + COUNT_WRONG_TARGET + COUNT_NOT_SYMLINK + COUNT_MISSING_DEST))
if [[ "$FIX_MODE" != true ]] && [[ $PROBLEMS -gt 0 ]]; then
    log_warn "Run with --fix to repair, or --dry-run to preview changes"
    exit 1
fi

if [[ "$FIX_MODE" == true ]] && [[ $COUNT_FAILED -gt 0 ]]; then
    exit 1
fi

exit 0
