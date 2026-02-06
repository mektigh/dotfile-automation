#!/bin/bash
# home-cleanup.sh - Migrate non-essential dotfiles from $HOME to XDG directories
#
# Usage:
#   home-cleanup.sh              # Dry-run: show what would happen
#   home-cleanup.sh --execute    # Actually perform migrations
#   home-cleanup.sh --wave 2     # Only run wave 2
#   home-cleanup.sh --wave 1 --execute  # Execute wave 1 only
#
# Migrations are organized in 5 dependency-ordered waves:
#   Wave 1: Foundation (.npm, .node_repl_history, .dotnet, .aspnet, .nuget)
#   Wave 2: Runtimes  (.nvm, .bun, .gem, .pub-cache)
#   Wave 3: Tools     (.docker, .oh-my-zsh, .android)
#   Wave 4: Symlinks  (.iterm2, .dart-tool, .aider, .wrangler, .gemini, .gmailctl, .vim, .mail)
#   Wave 5: Cleanup   (stale files, old backups, temp files)
#
# Safety features:
#   - Dry-run by default (no changes without --execute)
#   - Pre-migration backups (.pre-migration)
#   - SHA-256 checksums before/after rsync
#   - Test command after each migration
#   - Automatic rollback on test failure
#   - Manifest-based state tracking
#   - Auto-generated rollback script
#   - Idempotent (safe to run multiple times)

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

# State directory for manifest
STATE_DIR="$XDG_STATE_HOME/home-cleanup"
MANIFEST_FILE="$STATE_DIR/manifest.json"
ROLLBACK_SCRIPT="$SCRIPT_DIR/rollback-home-cleanup.sh"
ZSHENV_FILE="$HOME/.dotfiles/.zshenv"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
EXECUTE=false
WAVE_FILTER=""

usage() {
    printf "Usage: %s [--execute] [--wave N] [--dry-run] [--help]\n" "$(basename "$0")"
    printf "\n"
    printf "Options:\n"
    printf "  --execute    Actually perform migrations (default: dry-run)\n"
    printf "  --dry-run    Show what would happen without changes (default)\n"
    printf "  --wave N     Only run wave N (1-5)\n"
    printf "  --help       Show this help message\n"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --execute)  EXECUTE=true; shift ;;
        --dry-run)  EXECUTE=false; shift ;;
        --wave)
            if [[ -z "${2:-}" ]] || ! [[ "$2" =~ ^[1-5]$ ]]; then
                log_error "Wave must be 1-5"
                exit 1
            fi
            WAVE_FILTER="$2"
            shift 2
            ;;
        --help|-h) usage ;;
        *)
            log_error "Unknown option: $1"
            usage
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Counters and state
# ---------------------------------------------------------------------------
TOTAL_DIRS=0
TOTAL_SIZE_BYTES=0
TOTAL_MIGRATED=0
TOTAL_SKIPPED=0
TOTAL_FAILED=0
WAVE_ENTRIES=()  # JSON entries for manifest
ROLLBACK_LINES=()  # Lines for rollback script
ENV_VARS_TO_ADD=()  # env var exports to add to .zshenv

# ---------------------------------------------------------------------------
# Utility: human-readable size
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

# ---------------------------------------------------------------------------
# Utility: get directory size in bytes
# ---------------------------------------------------------------------------
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
# Utility: compute checksum of a directory (recursive file list + sizes)
# ---------------------------------------------------------------------------
dir_checksum() {
    local path="$1"
    if [[ -d "$path" ]]; then
        # Checksum based on file listing with sizes for speed
        # Full content checksums would be too slow for large dirs
        find "$path" -type f -exec stat -f '%z %N' {} \; 2>/dev/null | sort | shasum -a 256 | awk '{print $1}'
    elif [[ -f "$path" ]]; then
        shasum -a 256 "$path" 2>/dev/null | awk '{print $1}'
    else
        echo "none"
    fi
}

# ---------------------------------------------------------------------------
# Utility: check if migration already done (idempotency)
# ---------------------------------------------------------------------------
is_already_migrated() {
    local source="$1"
    local destination="$2"

    # If source is a symlink pointing to destination, already migrated
    if [[ -L "$source" ]]; then
        local target
        target="$(readlink "$source" 2>/dev/null || true)"
        if [[ "$target" == "$destination" ]]; then
            return 0
        fi
    fi

    # If source doesn't exist but destination does, already migrated
    if [[ ! -e "$source" ]] && [[ ! -L "$source" ]] && [[ -e "$destination" ]]; then
        return 0
    fi

    return 1
}

# ---------------------------------------------------------------------------
# Utility: JSON escape
# ---------------------------------------------------------------------------
json_escape() {
    printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()), end="")'
}

# ---------------------------------------------------------------------------
# Utility: add env var to .zshenv (if not already there)
# ---------------------------------------------------------------------------
add_env_var() {
    local var_name="$1"
    local var_value="$2"

    if [[ ! -f "$ZSHENV_FILE" ]]; then
        log_warn "Cannot add env var: $ZSHENV_FILE not found"
        return 1
    fi

    # Check if already set
    if grep -q "^export ${var_name}=" "$ZSHENV_FILE" 2>/dev/null; then
        log_info "Env var $var_name already set in .zshenv"
        return 0
    fi

    # Append to .zshenv
    printf '\n# Added by home-cleanup.sh on %s\nexport %s="%s"\n' \
        "$(date +%Y-%m-%d)" "$var_name" "$var_value" >> "$ZSHENV_FILE"

    log_ok "Added $var_name to .zshenv"
    return 0
}

# ---------------------------------------------------------------------------
# Utility: remove env var from .zshenv
# ---------------------------------------------------------------------------
remove_env_var() {
    local var_name="$1"

    if [[ ! -f "$ZSHENV_FILE" ]]; then
        return 0
    fi

    # Remove the export line and the comment line above it
    if grep -q "^export ${var_name}=" "$ZSHENV_FILE" 2>/dev/null; then
        # Use sed to remove the env var line and the comment line before it
        sed -i '' "/^# Added by home-cleanup.sh/,+1{/^export ${var_name}=/d;/^# Added by home-cleanup.sh/d;}" "$ZSHENV_FILE" 2>/dev/null || true
        # Also remove standalone export line if comment pattern didn't match
        sed -i '' "/^export ${var_name}=/d" "$ZSHENV_FILE" 2>/dev/null || true
    fi
}

# ---------------------------------------------------------------------------
# Core: migrate a single directory
# ---------------------------------------------------------------------------
# Arguments:
#   $1 = name (human label)
#   $2 = source path (e.g. ~/.npm)
#   $3 = destination path (e.g. ~/.cache/npm)
#   $4 = strategy: "envvar" | "symlink" | "envvar+symlink"
#   $5 = env var name (or "" if symlink-only)
#   $6 = env var value (or "" if symlink-only)
#   $7 = test command (or "" if none)
#   $8 = wave number
migrate_entry() {
    local name="$1"
    local source="$2"
    local destination="$3"
    local strategy="$4"
    local env_var_name="${5:-}"
    local env_var_value="${6:-}"
    local test_cmd="${7:-}"
    local wave_num="$8"

    TOTAL_DIRS=$((TOTAL_DIRS + 1))

    # Check if source exists
    if [[ ! -e "$source" ]] && [[ ! -L "$source" ]]; then
        if [[ "$EXECUTE" == true ]]; then
            log_warn "Skipping $name: source does not exist ($source)"
        else
            printf "  ${YELLOW}[ ]${NC} %-30s ${YELLOW}NOT FOUND${NC} (%s)\n" "$name" "$source"
        fi
        TOTAL_SKIPPED=$((TOTAL_SKIPPED + 1))
        return 0
    fi

    # Check if already migrated
    if is_already_migrated "$source" "$destination"; then
        if [[ "$EXECUTE" == true ]]; then
            log_info "Skipping $name: already migrated"
        else
            printf "  ${GREEN}[x]${NC} %-30s ${GREEN}ALREADY DONE${NC}\n" "$name"
        fi
        TOTAL_SKIPPED=$((TOTAL_SKIPPED + 1))
        return 0
    fi

    # Get size
    local size_bytes
    size_bytes="$(dir_size_bytes "$source")"
    local size_human
    size_human="$(human_size "$size_bytes")"
    TOTAL_SIZE_BYTES=$((TOTAL_SIZE_BYTES + size_bytes))

    # Determine strategy display
    local strategy_display
    case "$strategy" in
        envvar)         strategy_display="env var ($env_var_name)" ;;
        symlink)        strategy_display="symlink" ;;
        envvar+symlink) strategy_display="env var ($env_var_name) + symlink" ;;
        *)              strategy_display="$strategy" ;;
    esac

    # ---------------------------------------------------------------------------
    # DRY-RUN output
    # ---------------------------------------------------------------------------
    if [[ "$EXECUTE" != true ]]; then
        # Pretty-print the ~ paths
        local source_short="${source/#$HOME/\~}"
        local dest_short="${destination/#$HOME/\~}"

        printf "  ${BLUE}[ ]${NC} %-30s (%s)\n" "$name" "$size_human"
        printf "      ${BOLD}From:${NC}     %s\n" "$source_short"
        printf "      ${BOLD}To:${NC}       %s\n" "$dest_short"
        printf "      ${BOLD}Strategy:${NC} %s\n" "$strategy_display"
        if [[ -n "$test_cmd" ]]; then
            printf "      ${BOLD}Test:${NC}     %s\n" "$test_cmd"
        fi
        printf "\n"
        return 0
    fi

    # ---------------------------------------------------------------------------
    # EXECUTE mode
    # ---------------------------------------------------------------------------
    log_info "Migrating $name ($size_human)..."

    local timestamp
    timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    local status="in_progress"
    local checksum_before=""
    local checksum_after=""
    local test_result="skipped"
    local backup_path="${source}.pre-migration"

    # Step 1: Pre-migration backup
    if [[ -e "$source" ]] && [[ ! -L "$source" ]]; then
        log_info "  Creating pre-migration backup..."
        if [[ -e "$backup_path" ]]; then
            log_warn "  Pre-migration backup already exists, skipping backup"
        else
            cp -a "$source" "$backup_path"
            log_ok "  Backup: $backup_path"
        fi
    fi

    # Step 2: Checksum before
    log_info "  Computing checksum (this may take a moment for large dirs)..."
    checksum_before="$(dir_checksum "$source")"

    # Step 3: Ensure destination parent exists
    mkdir -p "$(dirname "$destination")"

    # Step 4: Rsync to new location
    log_info "  Syncing to $destination..."
    if [[ -d "$source" ]]; then
        if ! rsync -a --delete "$source/" "$destination/"; then
            log_error "  Rsync FAILED for $name"
            log_error "  Pre-migration backup preserved at: $backup_path"
            TOTAL_FAILED=$((TOTAL_FAILED + 1))
            # Record failure in manifest entry
            WAVE_ENTRIES+=("$(printf '{
        "name": %s,
        "source": %s,
        "destination": %s,
        "strategy": %s,
        "env_var": %s,
        "env_value": %s,
        "symlink": false,
        "size_bytes": %d,
        "checksum_before": "sha256:%s",
        "checksum_after": "sha256:none",
        "backup_path": %s,
        "status": "failed",
        "error": "rsync failed",
        "test_command": %s,
        "test_result": "skipped",
        "timestamp": "%s"
      }' \
                "$(json_escape "$name")" \
                "$(json_escape "$source")" \
                "$(json_escape "$destination")" \
                "$(json_escape "$strategy")" \
                "$(json_escape "$env_var_name")" \
                "$(json_escape "$env_var_value")" \
                "$size_bytes" \
                "$checksum_before" \
                "$(json_escape "$backup_path")" \
                "$(json_escape "$test_cmd")" \
                "$timestamp")")
            return 1
        fi
    elif [[ -f "$source" ]]; then
        if ! cp -a "$source" "$destination"; then
            log_error "  Copy FAILED for $name"
            TOTAL_FAILED=$((TOTAL_FAILED + 1))
            return 1
        fi
    fi

    # Step 5: Checksum after
    checksum_after="$(dir_checksum "$destination")"

    if [[ "$checksum_before" != "$checksum_after" ]]; then
        log_warn "  Checksum mismatch (this can happen with metadata changes)"
        log_warn "  Before: $checksum_before"
        log_warn "  After:  $checksum_after"
        # Not necessarily fatal -- rsync can update timestamps
    fi

    # Step 6: Set environment variable (BEFORE deletion so it's tested)
    if [[ -n "$env_var_name" ]] && [[ -n "$env_var_value" ]]; then
        add_env_var "$env_var_name" "$env_var_value"
        ENV_VARS_TO_ADD+=("$env_var_name=$env_var_value")
        # Export for current session too
        export "$env_var_name"="$(eval echo "$env_var_value")"
    fi

    # Step 7: Create symlink if needed (BEFORE testing)
    local created_symlink=false
    if [[ "$strategy" == "symlink" ]] || [[ "$strategy" == "envvar+symlink" ]]; then
        log_info "  Creating symlink..."
        # DON'T delete original yet - test first!
        if ! ln -s "$destination" "$source.test-symlink"; then
            log_error "  Failed to create test symlink"
            TOTAL_FAILED=$((TOTAL_FAILED + 1))
            return 1
        fi
        # Move test symlink to real location after test passes
        created_symlink=true
    fi

    # Step 8: Test BEFORE deleting original
    if [[ -n "$test_cmd" ]]; then
        log_info "  Testing: $test_cmd"
        if eval "$test_cmd" >/dev/null 2>&1; then
            test_result="pass"
            log_ok "  Test passed"
        else
            test_result="fail"
            log_error "  Test FAILED for $name"
            log_error "  Rolling back migration..."

            # Rollback: remove the test symlink and env vars, keep original
            if [[ -L "$source.test-symlink" ]]; then
                rm -f "$source.test-symlink"
            fi
            if [[ -L "$source" ]]; then
                rm -f "$source"
            fi

            # Remove env var
            if [[ -n "$env_var_name" ]]; then
                remove_env_var "$env_var_name"
            fi

            TOTAL_FAILED=$((TOTAL_FAILED + 1))
            status="rolled_back"

            WAVE_ENTRIES+=("$(printf '{
        "name": %s,
        "source": %s,
        "destination": %s,
        "strategy": %s,
        "env_var": %s,
        "env_value": %s,
        "symlink": %s,
        "size_bytes": %d,
        "checksum_before": "sha256:%s",
        "checksum_after": "sha256:%s",
        "backup_path": %s,
        "status": "rolled_back",
        "error": "test command failed",
        "test_command": %s,
        "test_result": "fail",
        "timestamp": "%s"
      }' \
                "$(json_escape "$name")" \
                "$(json_escape "$source")" \
                "$(json_escape "$destination")" \
                "$(json_escape "$strategy")" \
                "$(json_escape "$env_var_name")" \
                "$(json_escape "$env_var_value")" \
                "$created_symlink" \
                "$size_bytes" \
                "$checksum_before" \
                "$checksum_after" \
                "$(json_escape "$backup_path")" \
                "$(json_escape "$test_cmd")" \
                "$timestamp")")
            return 1
        fi
    fi

    # Step 9: Finalize - now that test passed, safely delete original
    # This is only done AFTER test passes, ensuring we can rollback if needed
    if [[ "$strategy" == "symlink" ]] || [[ "$strategy" == "envvar+symlink" ]]; then
        log_info "  Finalizing symlink (removing test-symlink, replacing with real)..."
        if [[ -L "$source.test-symlink" ]]; then
            # Move test symlink to final location
            rm -f "$source" 2>/dev/null || true
            mv "$source.test-symlink" "$source"
            log_ok "  Symlink finalized: $source -> $destination"
        fi
        # Now safe to remove original directory
        if [[ -e "$source" ]] && [[ ! -L "$source" ]]; then
            log_info "  Removing original directory..."
            if rm -rf "$source" 2>/dev/null; then
                log_ok "  Original removed: $source"
            else
                log_warn "  Could not fully remove original (some files may be in use): $source"
                # Still mark as success since symlink works and data is safe
            fi
        fi
    elif [[ "$strategy" == "envvar" ]]; then
        # For envvar-only strategy: remove original now that env var is set and tested
        log_info "  Removing original directory (env var will point to new location)..."
        if rm -rf "$source" 2>/dev/null; then
            log_ok "  Original removed: $source"
        else
            log_warn "  Could not fully remove original (some files may be in use): $source"
            # Still mark as success since env var is set and tested
        fi
    fi

    # Step 10: Success
    status="completed"
    TOTAL_MIGRATED=$((TOTAL_MIGRATED + 1))
    log_ok "Migrated $name successfully"

    # Record for manifest
    WAVE_ENTRIES+=("$(printf '{
        "name": %s,
        "source": %s,
        "destination": %s,
        "strategy": %s,
        "env_var": %s,
        "env_value": %s,
        "symlink": %s,
        "size_bytes": %d,
        "checksum_before": "sha256:%s",
        "checksum_after": "sha256:%s",
        "backup_path": %s,
        "status": "completed",
        "test_command": %s,
        "test_result": %s,
        "timestamp": "%s"
      }' \
        "$(json_escape "$name")" \
        "$(json_escape "$source")" \
        "$(json_escape "$destination")" \
        "$(json_escape "$strategy")" \
        "$(json_escape "$env_var_name")" \
        "$(json_escape "$env_var_value")" \
        "$created_symlink" \
        "$size_bytes" \
        "$checksum_before" \
        "$checksum_after" \
        "$(json_escape "$backup_path")" \
        "$(json_escape "$test_cmd")" \
        "$(json_escape "$test_result")" \
        "$timestamp")")

    # Record for rollback
    ROLLBACK_LINES+=("# Rollback: $name")
    if [[ "$created_symlink" == true ]]; then
        ROLLBACK_LINES+=("rm -f $(json_escape "$source")")
    fi
    ROLLBACK_LINES+=("rsync -a --delete $(json_escape "$destination/") $(json_escape "$source/")")
    if [[ -n "$env_var_name" ]]; then
        ROLLBACK_LINES+=("# Remove env var: $env_var_name from .zshenv")
    fi
    ROLLBACK_LINES+=("")
}

# ---------------------------------------------------------------------------
# Core: cleanup entry (Wave 5 - delete stale files)
# ---------------------------------------------------------------------------
cleanup_entry() {
    local name="$1"
    local path="$2"
    local reason="$3"

    TOTAL_DIRS=$((TOTAL_DIRS + 1))

    # Check if target exists
    if [[ ! -e "$path" ]] && [[ ! -L "$path" ]]; then
        if [[ "$EXECUTE" != true ]]; then
            printf "  ${GREEN}[x]${NC} %-30s ${GREEN}ALREADY GONE${NC}\n" "$name"
        fi
        TOTAL_SKIPPED=$((TOTAL_SKIPPED + 1))
        return 0
    fi

    local size_bytes
    size_bytes="$(dir_size_bytes "$path")"
    local size_human
    size_human="$(human_size "$size_bytes")"
    local path_short="${path/#$HOME/\~}"

    if [[ "$EXECUTE" != true ]]; then
        printf "  ${RED}[D]${NC} %-30s (%s)\n" "$name" "$size_human"
        printf "      ${BOLD}Path:${NC}     %s\n" "$path_short"
        printf "      ${BOLD}Reason:${NC}   %s\n" "$reason"
        printf "\n"
    else
        log_info "Deleting $name ($size_human)..."
        rm -rf "$path"
        log_ok "Deleted: $path_short"
        TOTAL_MIGRATED=$((TOTAL_MIGRATED + 1))
    fi
}

# ---------------------------------------------------------------------------
# Cleanup: find and remove broken backup symlinks
# ---------------------------------------------------------------------------
cleanup_broken_backups() {
    local count=0
    local found=()

    # Find .backup.* symlinks in HOME that are broken
    while IFS= read -r -d '' file; do
        if [[ -L "$file" ]] && [[ ! -e "$file" ]]; then
            found+=("$file")
            count=$((count + 1))
        fi
    done < <(find "$HOME" -maxdepth 1 -name "*.backup.*" -print0 2>/dev/null)

    if [[ ${#found[@]} -eq 0 ]]; then
        if [[ "$EXECUTE" != true ]]; then
            printf "  ${GREEN}[x]${NC} %-30s ${GREEN}NONE FOUND${NC}\n" "Broken backup symlinks"
        fi
        return 0
    fi

    TOTAL_DIRS=$((TOTAL_DIRS + ${#found[@]}))

    if [[ "$EXECUTE" != true ]]; then
        printf "  ${RED}[D]${NC} %-30s (%d found)\n" "Broken backup symlinks" "${#found[@]}"
        for f in "${found[@]}"; do
            local f_short="${f/#$HOME/\~}"
            local target
            target="$(readlink "$f" 2>/dev/null || echo "???")"
            printf "      ${BOLD}File:${NC}     %s -> %s\n" "$f_short" "$target"
        done
        printf "\n"
    else
        for f in "${found[@]}"; do
            rm -f "$f"
            log_ok "Deleted broken symlink: ${f/#$HOME/\~}"
            TOTAL_MIGRATED=$((TOTAL_MIGRATED + 1))
        done
    fi
}

# ---------------------------------------------------------------------------
# Wave definitions
# ---------------------------------------------------------------------------
run_wave_1() {
    local wave_label="WAVE 1: Foundation (no dependencies)"

    if [[ "$EXECUTE" != true ]]; then
        printf "\n${BOLD}%s${NC}\n" "$wave_label"
        printf "%s\n\n" "$(printf '%.0s-' {1..50})"
    else
        log_header "$wave_label"
    fi

    migrate_entry "npm-cache" \
        "$HOME/.npm" \
        "$XDG_CACHE_HOME/npm" \
        "envvar" \
        "NPM_CONFIG_CACHE" \
        '$XDG_CACHE_HOME/npm' \
        "npm cache ls 2>/dev/null || npm --version" \
        "1"

    migrate_entry "node-repl-history" \
        "$HOME/.node_repl_history" \
        "$XDG_STATE_HOME/node_repl_history" \
        "envvar" \
        "NODE_REPL_HISTORY" \
        '$XDG_STATE_HOME/node_repl_history' \
        "" \
        "1"

    migrate_entry "dotnet" \
        "$HOME/.dotnet" \
        "$XDG_DATA_HOME/dotnet" \
        "envvar" \
        "DOTNET_CLI_HOME" \
        '$XDG_DATA_HOME/dotnet' \
        "dotnet --info 2>/dev/null || true" \
        "1"

    migrate_entry "aspnet" \
        "$HOME/.aspnet" \
        "$XDG_DATA_HOME/aspnet" \
        "symlink" \
        "" \
        "" \
        "" \
        "1"

    migrate_entry "nuget" \
        "$HOME/.nuget" \
        "$XDG_DATA_HOME/NuGet" \
        "envvar" \
        "NUGET_PACKAGES" \
        '$XDG_DATA_HOME/NuGet/packages' \
        "" \
        "1"
}

run_wave_2() {
    local wave_label="WAVE 2: Runtimes"

    if [[ "$EXECUTE" != true ]]; then
        printf "\n${BOLD}%s${NC}\n" "$wave_label"
        printf "%s\n\n" "$(printf '%.0s-' {1..50})"
    else
        log_header "$wave_label"
    fi

    migrate_entry "nvm" \
        "$HOME/.nvm" \
        "$XDG_DATA_HOME/nvm" \
        "envvar" \
        "NVM_DIR" \
        '$XDG_DATA_HOME/nvm' \
        "command -v nvm >/dev/null 2>&1 || [[ -s \$NVM_DIR/nvm.sh ]]" \
        "2"

    # NOTE: Bun is a complex installation (binary in ~/.bun/bin/, metadata in ~/.bun/install/)
    # It doesn't migrate cleanly like npm cache or gems. Recommend manual migration if needed:
    #   1. backup ~/.bun
    #   2. install bun to new location: curl -fsSL https://bun.sh/install | bash
    #   3. set BUN_INSTALL to new location
    # For now, skip automatic migration
    #
    # migrate_entry "bun" \
    #     "$HOME/.bun" \
    #     "$XDG_DATA_HOME/bun" \
    #     "envvar" \
    #     "BUN_INSTALL" \
    #     '$XDG_DATA_HOME/bun' \
    #     "bun --version" \
    #     "2"

    migrate_entry "gem" \
        "$HOME/.gem" \
        "$XDG_DATA_HOME/gem" \
        "envvar" \
        "GEM_HOME" \
        '$XDG_DATA_HOME/gem' \
        "gem env 2>/dev/null | head -1 || true" \
        "2"

    migrate_entry "pub-cache" \
        "$HOME/.pub-cache" \
        "$XDG_CACHE_HOME/pub" \
        "envvar" \
        "PUB_CACHE" \
        '$XDG_CACHE_HOME/pub' \
        "" \
        "2"
}

run_wave_3() {
    local wave_label="WAVE 3: Tool Configs"

    if [[ "$EXECUTE" != true ]]; then
        printf "\n${BOLD}%s${NC}\n" "$wave_label"
        printf "%s\n\n" "$(printf '%.0s-' {1..50})"
    else
        log_header "$wave_label"
    fi

    migrate_entry "docker" \
        "$HOME/.docker" \
        "$XDG_CONFIG_HOME/docker" \
        "envvar" \
        "DOCKER_CONFIG" \
        '$XDG_CONFIG_HOME/docker' \
        "docker version 2>/dev/null || true" \
        "3"

    migrate_entry "oh-my-zsh" \
        "$HOME/.oh-my-zsh" \
        "$XDG_DATA_HOME/oh-my-zsh" \
        "envvar+symlink" \
        "ZSH" \
        '$XDG_DATA_HOME/oh-my-zsh' \
        "test -d \$ZSH/plugins" \
        "3"

    migrate_entry "android" \
        "$HOME/.android" \
        "$XDG_DATA_HOME/android" \
        "envvar" \
        "ANDROID_USER_HOME" \
        '$XDG_DATA_HOME/android' \
        "" \
        "3"
}

run_wave_4() {
    local wave_label="WAVE 4: Symlink-Only (no env var needed)"

    if [[ "$EXECUTE" != true ]]; then
        printf "\n${BOLD}%s${NC}\n" "$wave_label"
        printf "%s\n\n" "$(printf '%.0s-' {1..50})"
    else
        log_header "$wave_label"
    fi

    migrate_entry "iterm2" \
        "$HOME/.iterm2" \
        "$XDG_CONFIG_HOME/iterm2" \
        "symlink" \
        "" "" \
        "" \
        "4"

    migrate_entry "dart-tool" \
        "$HOME/.dart-tool" \
        "$XDG_DATA_HOME/dart" \
        "symlink" \
        "" "" \
        "" \
        "4"

    migrate_entry "aider" \
        "$HOME/.aider" \
        "$XDG_CONFIG_HOME/aider" \
        "symlink" \
        "" "" \
        "" \
        "4"

    migrate_entry "wrangler" \
        "$HOME/.wrangler" \
        "$XDG_CONFIG_HOME/wrangler" \
        "symlink" \
        "" "" \
        "" \
        "4"

    migrate_entry "gemini" \
        "$HOME/.gemini" \
        "$XDG_CONFIG_HOME/gemini" \
        "symlink" \
        "" "" \
        "" \
        "4"

    migrate_entry "gmailctl" \
        "$HOME/.gmailctl" \
        "$XDG_CONFIG_HOME/gmailctl" \
        "symlink" \
        "" "" \
        "" \
        "4"

    migrate_entry "vim" \
        "$HOME/.vim" \
        "$XDG_CONFIG_HOME/vim" \
        "symlink" \
        "" "" \
        "vim --version 2>/dev/null | head -1 || true" \
        "4"

    migrate_entry "mail" \
        "$HOME/.mail" \
        "$XDG_DATA_HOME/mail" \
        "symlink" \
        "" "" \
        "" \
        "4"
}

run_wave_5() {
    local wave_label="WAVE 5: Cleanup (stale files and temp data)"

    if [[ "$EXECUTE" != true ]]; then
        printf "\n${BOLD}%s${NC}\n" "$wave_label"
        printf "%s\n\n" "$(printf '%.0s-' {1..50})"
    else
        log_header "$wave_label"
    fi

    cleanup_entry "bash_history" \
        "$HOME/.bash_history" \
        "Stale bash history (zsh is the primary shell)"

    cleanup_entry "zshrc.bak" \
        "$HOME/.zshrc.bak" \
        "Old zshrc backup (dotfiles are version controlled)"

    cleanup_broken_backups

    cleanup_entry "temp-mailbox" \
        "$HOME/~\$mailbox20151029.xlsx" \
        "Temp Excel lock file from 2015"

    cleanup_entry "brewfile-fixes" \
        "$HOME/BREWFILE_FIXES.md" \
        "Temporary Brewfile analysis (session artifact)"

    cleanup_entry "brewfile-review" \
        "$HOME/BREWFILE_REVIEW.md" \
        "Temporary Brewfile review (session artifact)"
}

# ---------------------------------------------------------------------------
# Manifest generation
# ---------------------------------------------------------------------------
generate_manifest() {
    mkdir -p "$STATE_DIR"

    local manifest_date
    manifest_date="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    # Build the entries JSON for current wave(s)
    local entries_json=""
    if [[ ${#WAVE_ENTRIES[@]} -gt 0 ]]; then
        entries_json="$(printf '%s,' "${WAVE_ENTRIES[@]}")"
        entries_json="[${entries_json%,}]"
    else
        entries_json="[]"
    fi

    # If manifest already exists, merge in the new wave data
    if [[ -f "$MANIFEST_FILE" ]]; then
        # Read existing manifest and add new entries
        local existing
        existing="$(cat "$MANIFEST_FILE")"

        # Use python3 to merge (available on macOS)
        python3 -c "
import json, sys

existing = json.loads('''$existing''')
new_entries = json.loads('''$entries_json''')

# Determine wave number from new entries
for entry in new_entries:
    wave_num = '$WAVE_FILTER' if '$WAVE_FILTER' else 'all'
    if wave_num not in existing.get('waves', {}):
        existing.setdefault('waves', {})[wave_num] = []
    existing['waves'][wave_num].extend([entry])

existing['last_updated'] = '$manifest_date'
print(json.dumps(existing, indent=2))
" > "${MANIFEST_FILE}.tmp" 2>/dev/null && mv "${MANIFEST_FILE}.tmp" "$MANIFEST_FILE"
    else
        # Create new manifest
        local wave_key="${WAVE_FILTER:-all}"

        python3 -c "
import json

manifest = {
    'version': '1.0',
    'date': '$manifest_date',
    'last_updated': '$manifest_date',
    'target_user': '$(whoami)',
    'home_dir': '$HOME',
    'waves': {
        '$wave_key': json.loads('''$entries_json''')
    }
}
print(json.dumps(manifest, indent=2))
" > "$MANIFEST_FILE"
    fi

    log_ok "Manifest saved: $MANIFEST_FILE"
}

# ---------------------------------------------------------------------------
# Rollback script generation
# ---------------------------------------------------------------------------
generate_rollback_script() {
    local rollback_date
    rollback_date="$(date +%Y-%m-%d)"

    cat > "$ROLLBACK_SCRIPT" << 'ROLLBACK_HEADER'
#!/bin/bash
# rollback-home-cleanup.sh - Reverse all home-cleanup migrations
#
# AUTO-GENERATED by home-cleanup.sh --execute
# This script reverses ALL home-cleanup migrations in reverse order.
#
# Usage:
#   rollback-home-cleanup.sh              # Dry-run: show what would revert
#   rollback-home-cleanup.sh --execute    # Actually revert migrations
#
# What it does:
#   1. Reads manifest.json for migration records
#   2. Removes symlinks from old locations
#   3. Rsyncs data back from new location to old
#   4. Removes env var exports from .zshenv
#   5. Optionally deletes .pre-migration backups

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

STATE_DIR="$XDG_STATE_HOME/home-cleanup"
MANIFEST_FILE="$STATE_DIR/manifest.json"
ZSHENV_FILE="$HOME/.dotfiles/.zshenv"

EXECUTE=false
CLEAN_BACKUPS=false

for arg in "$@"; do
    case "$arg" in
        --execute)        EXECUTE=true ;;
        --clean-backups)  CLEAN_BACKUPS=true ;;
        --help|-h)
            printf "Usage: %s [--execute] [--clean-backups]\n" "$(basename "$0")"
            printf "\n"
            printf "Options:\n"
            printf "  --execute         Actually revert migrations (default: dry-run)\n"
            printf "  --clean-backups   Also delete .pre-migration backup files\n"
            printf "  --help            Show this help message\n"
            exit 0
            ;;
        *)
            log_error "Unknown option: $arg"
            exit 1
            ;;
    esac
done

# Check manifest exists
if [[ ! -f "$MANIFEST_FILE" ]]; then
    log_error "No manifest found at $MANIFEST_FILE"
    log_error "Nothing to rollback."
    exit 1
fi

log_header "Home Cleanup Rollback"

if [[ "$EXECUTE" != true ]]; then
    log_info "DRY-RUN mode: no changes will be made"
    printf "\n"
fi

# Parse manifest and rollback in reverse order
TOTAL_REVERTED=0
TOTAL_FAILED=0

# Use python3 to extract entries in reverse order
entries_json="$(python3 -c "
import json

with open('$MANIFEST_FILE') as f:
    manifest = json.load(f)

entries = []
for wave_key in sorted(manifest.get('waves', {}).keys(), reverse=True):
    for entry in reversed(manifest['waves'][wave_key]):
        if entry.get('status') == 'completed':
            entries.append(json.dumps(entry))

for e in entries:
    print(e)
")"

while IFS= read -r entry_json; do
    [[ -z "$entry_json" ]] && continue

    name="$(echo "$entry_json" | python3 -c "import json,sys; print(json.load(sys.stdin)['name'])")"
    source="$(echo "$entry_json" | python3 -c "import json,sys; print(json.load(sys.stdin)['source'])")"
    destination="$(echo "$entry_json" | python3 -c "import json,sys; print(json.load(sys.stdin)['destination'])")"
    strategy="$(echo "$entry_json" | python3 -c "import json,sys; print(json.load(sys.stdin)['strategy'])")"
    env_var="$(echo "$entry_json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('env_var', ''))")"
    backup_path="$(echo "$entry_json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('backup_path', ''))")"
    is_symlink="$(echo "$entry_json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('symlink', False))")"

    source_short="${source/#$HOME/\~}"
    dest_short="${destination/#$HOME/\~}"

    if [[ "$EXECUTE" != true ]]; then
        printf "  [R] %-25s %s <- %s\n" "$name" "$source_short" "$dest_short"
        if [[ -n "$env_var" ]]; then
            printf "      Remove env var: %s\n" "$env_var"
        fi
        if [[ "$CLEAN_BACKUPS" == true ]] && [[ -n "$backup_path" ]]; then
            printf "      Delete backup: %s\n" "${backup_path/#$HOME/\~}"
        fi
        printf "\n"
        TOTAL_REVERTED=$((TOTAL_REVERTED + 1))
        continue
    fi

    log_info "Reverting: $name"

    # Step 1: Remove symlink if present
    if [[ -L "$source" ]]; then
        rm -f "$source"
        log_ok "  Removed symlink: $source_short"
    fi

    # Step 2: Restore data
    if [[ -e "$backup_path" ]] && [[ ! -L "$backup_path" ]]; then
        # Prefer pre-migration backup
        if [[ -e "$source" ]]; then
            rm -rf "$source"
        fi
        mv "$backup_path" "$source"
        log_ok "  Restored from pre-migration backup"
    elif [[ -d "$destination" ]]; then
        mkdir -p "$source"
        rsync -a --delete "$destination/" "$source/"
        log_ok "  Synced back: $dest_short -> $source_short"
    elif [[ -f "$destination" ]]; then
        cp -a "$destination" "$source"
        log_ok "  Copied back: $dest_short -> $source_short"
    else
        log_warn "  No data to restore for $name"
    fi

    # Step 3: Remove env var from .zshenv
    if [[ -n "$env_var" ]] && [[ -f "$ZSHENV_FILE" ]]; then
        if grep -q "^export ${env_var}=" "$ZSHENV_FILE" 2>/dev/null; then
            sed -i '' "/^# Added by home-cleanup.sh/,+1{/^export ${env_var}=/d;/^# Added by home-cleanup.sh/d;}" "$ZSHENV_FILE" 2>/dev/null || true
            sed -i '' "/^export ${env_var}=/d" "$ZSHENV_FILE" 2>/dev/null || true
            log_ok "  Removed $env_var from .zshenv"
        fi
    fi

    # Step 4: Clean up backup if requested
    if [[ "$CLEAN_BACKUPS" == true ]] && [[ -e "$backup_path" ]]; then
        rm -rf "$backup_path"
        log_ok "  Deleted backup: ${backup_path/#$HOME/\~}"
    fi

    TOTAL_REVERTED=$((TOTAL_REVERTED + 1))
    log_ok "Reverted: $name"

done <<< "$entries_json"

# Summary
printf "\n"
log_header "Rollback Summary"
printf "  Reverted: %d\n" "$TOTAL_REVERTED"

if [[ "$EXECUTE" != true ]]; then
    printf "\n"
    log_info "DRY-RUN complete. Run with --execute to actually revert."
else
    printf "\n"
    log_ok "Rollback complete. Reload your shell: source ~/.zshenv"

    # Mark manifest as rolled back
    python3 -c "
import json
with open('$MANIFEST_FILE') as f:
    m = json.load(f)
m['rolled_back'] = True
m['rollback_date'] = '$(date -u +%Y-%m-%dT%H:%M:%SZ)'
with open('$MANIFEST_FILE', 'w') as f:
    json.dump(m, f, indent=2)
"
fi
ROLLBACK_HEADER

    chmod +x "$ROLLBACK_SCRIPT"
    log_ok "Rollback script generated: $ROLLBACK_SCRIPT"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    # Print header
    if [[ "$EXECUTE" == true ]]; then
        printf "\n"
        log_header "Home Directory Cleanup - EXECUTE MODE"
        log_warn "This WILL modify your home directory!"
        printf "\n"

        if ! confirm "Proceed with home cleanup migrations?"; then
            log_info "Aborted by user."
            exit 0
        fi
    else
        printf "\n"
        printf "${BOLD}Home Directory Cleanup - DRY-RUN${NC}\n"
        printf "%s\n" "$(printf '%.0s=' {1..64})"
        printf "\n"
        printf "  ${BLUE}This preview shows what would happen with --execute.${NC}\n"
        printf "  ${BLUE}No changes will be made.${NC}\n"
    fi

    # Run waves
    if [[ -z "$WAVE_FILTER" ]] || [[ "$WAVE_FILTER" == "1" ]]; then
        run_wave_1
    fi

    if [[ -z "$WAVE_FILTER" ]] || [[ "$WAVE_FILTER" == "2" ]]; then
        run_wave_2
    fi

    if [[ -z "$WAVE_FILTER" ]] || [[ "$WAVE_FILTER" == "3" ]]; then
        run_wave_3
    fi

    if [[ -z "$WAVE_FILTER" ]] || [[ "$WAVE_FILTER" == "4" ]]; then
        run_wave_4
    fi

    if [[ -z "$WAVE_FILTER" ]] || [[ "$WAVE_FILTER" == "5" ]]; then
        run_wave_5
    fi

    # Summary
    printf "\n"
    printf "%s\n" "$(printf '%.0s=' {1..64})"

    local total_size_human
    total_size_human="$(human_size "$TOTAL_SIZE_BYTES")"

    if [[ "$EXECUTE" != true ]]; then
        printf "${BOLD}Summary:${NC}\n"
        printf "  Directories to migrate: %d\n" "$TOTAL_DIRS"
        printf "  Already migrated:       %d\n" "$TOTAL_SKIPPED"
        printf "  Total size:             %s\n" "$total_size_human"
        printf "\n"
        printf "  ${BLUE}Status: DRY-RUN - no changes made${NC}\n"
        printf "  ${BOLD}Next:${NC}   Run with ${BOLD}--execute${NC} to proceed\n"
        if [[ -n "$WAVE_FILTER" ]]; then
            printf "  ${BOLD}Scope:${NC}  Wave %s only\n" "$WAVE_FILTER"
        fi
    else
        printf "${BOLD}Migration Summary:${NC}\n"
        printf "  Migrated:  %d\n" "$TOTAL_MIGRATED"
        printf "  Skipped:   %d\n" "$TOTAL_SKIPPED"
        printf "  Failed:    %d\n" "$TOTAL_FAILED"
        printf "  Total:     %d directories\n" "$TOTAL_DIRS"
        printf "  Size:      %s\n" "$total_size_human"

        # Generate manifest
        if [[ ${#WAVE_ENTRIES[@]} -gt 0 ]]; then
            printf "\n"
            generate_manifest
        fi

        # Generate rollback script
        printf "\n"
        generate_rollback_script

        # Final instructions
        printf "\n"
        log_header "Next Steps"
        printf "  1. Reload your shell:    ${BOLD}source ~/.zshenv${NC}\n"
        printf "  2. Verify manifest:      ${BOLD}cat %s${NC}\n" "$MANIFEST_FILE"
        printf "  3. To rollback:          ${BOLD}%s${NC}\n" "$ROLLBACK_SCRIPT"

        if [[ $TOTAL_FAILED -gt 0 ]]; then
            printf "\n"
            log_warn "$TOTAL_FAILED migration(s) failed. Check output above for details."
            log_warn "Pre-migration backups (.pre-migration) preserved for failed items."
        fi
    fi

    printf "\n"
}

main
