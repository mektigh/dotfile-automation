# Usage Guide

Complete command reference for dotfile-automation.

## Table of contents

- [symlink-check.sh](#symlink-checksh) -- Validate and repair symlinks
- [add-dotfile.sh](#add-dotfilesh) -- Onboard new dotfiles
- [migrate-directory.sh](#migrate-directorysh) -- Generic directory migration
- [home-cleanup.sh](#home-cleanupsh) -- Organize HOME directory
- [Configuration](#configuration) -- The .env file
- [The dotfiles.conf format](#the-dotfilesconf-format)
- [Troubleshooting](#troubleshooting)
- [FAQ](#faq)

---

## symlink-check.sh

Validates all dotfile symlinks defined in your `dotfiles.conf` registry.

### Basic usage

```bash
# Check all symlinks (read-only, no changes)
symlink-check.sh

# Fix broken symlinks (creates backups first)
symlink-check.sh --fix

# Preview what --fix would do
symlink-check.sh --dry-run

# Use a specific config file
symlink-check.sh --conf /path/to/my-dotfiles.conf
```

### What it checks

For each entry in `dotfiles.conf`, the script verifies:

| Status | Meaning |
|--------|---------|
| `OK` | Symlink exists and points to the correct source |
| `MISSING` | No file or symlink at the destination |
| `BROKEN` | Symlink exists but target file is gone |
| `WRONG_TARGET` | Symlink exists but points to the wrong file |
| `NOT_SYMLINK` | A regular file exists where a symlink should be |
| `MISSING_SOURCE` | The source file in your dotfiles repo doesn't exist |

### Example output

```
Dotfile Symlink Check
------------------------------------------------------------

  Zsh main configuration                       OK
  Zsh environment variables                     OK
  Git configuration                             OK
  Alacritty config                              BROKEN (points to: /old/path)
  Tmux configuration                            MISSING (expected: ~/.tmux.conf)

Summary
------------------------------------------------------------
  Total entries:     5
  OK:                3
  Broken:            1
  Missing dest:      1

  [WARN] Run with --fix to repair, or --dry-run to preview changes
```

### Fix mode

When run with `--fix`:
1. Creates a timestamped backup of any existing file at the destination
2. Removes the broken/wrong symlink
3. Creates a new correct symlink
4. Reports success or failure

```bash
# Preview fixes first
symlink-check.sh --dry-run

# Then apply
symlink-check.sh --fix
```

### Options

| Flag | Description |
|------|-------------|
| `--fix` | Repair broken or missing symlinks |
| `--dry-run` | Show what --fix would do without changes |
| `--conf FILE` | Use a specific config file |
| `--help` | Show help message |

---

## add-dotfile.sh

Onboards a new configuration file into your managed dotfiles system.

### Basic usage

```bash
# Add a file with auto-generated description
add-dotfile.sh ~/.tmux.conf

# Add a file with a custom description
add-dotfile.sh ~/.config/starship.toml "Starship prompt configuration"

# Show help
add-dotfile.sh --help
```

### What it does (step by step)

1. **Validates** the file exists and isn't already managed
2. **Shows a preview** of what will happen
3. **Asks for confirmation** before proceeding
4. **Backs up** the original file (timestamped copy)
5. **Moves** the file into your dotfiles repo, mirroring its path:
   - `~/.tmux.conf` becomes `~/.dotfiles/.tmux.conf`
   - `~/.config/starship.toml` becomes `~/.dotfiles/.config/starship.toml`
6. **Creates a symlink** at the original location
7. **Registers** the entry in `dotfiles.conf`
8. **Verifies** the symlink works

### Example session

```
$ add-dotfile.sh ~/.config/starship.toml "Starship prompt"

Add Dotfile: starship.toml
------------------------------------------------------------

  Plan:
  File:                ~/.config/starship.toml
  Move to:             ~/.dotfiles/.config/starship.toml
  Symlink:             ~/.config/starship.toml -> ~/.dotfiles/.config/starship.toml
  Description:         Starship prompt
  Registry:            ~/.dotfiles/dotfiles.conf

Proceed with adding this dotfile? [y/N]: y

  [INFO] Step 1/6: Backing up existing files...
  [INFO] Backed up: ~/.config/starship.toml -> ~/.config/starship.toml.backup.20260206_140000
  [INFO] Step 2/6: Preparing dotfiles directory...
  [INFO] Created directory: ~/.dotfiles/.config
  [INFO] Step 3/6: Moving file to dotfiles repo...
  [OK] Moved to: ~/.dotfiles/.config/starship.toml
  [INFO] Step 4/6: Creating symlink...
  [OK] Symlink: ~/.config/starship.toml -> ~/.dotfiles/.config/starship.toml
  [INFO] Step 5/6: Adding to dotfiles.conf...
  [OK] Added to registry: ~/.dotfiles/.config/starship.toml
  [INFO] Step 6/6: Verifying...
  [OK] Verification passed

Done
------------------------------------------------------------
  Successfully onboarded: starship.toml
```

### Safety features

- Never overwrites without backing up first
- Detects if the file is already managed (symlink to dotfiles repo)
- Detects duplicate entries in `dotfiles.conf`
- Requires explicit confirmation before making changes

---

## migrate-directory.sh

Generic directory migration tool for moving any directory from `$HOME` to XDG-compliant locations.

### Basic usage

```bash
# Preview migration (dry-run, no changes)
migrate-directory.sh ~/.myapp ~/.config/myapp

# Execute migration
migrate-directory.sh ~/.myapp ~/.config/myapp --execute

# Rollback to backup
migrate-directory.sh ~/.myapp ~/.config/myapp --rollback
```

### When to use

Use `migrate-directory.sh` when:
- You install a new application that creates a directory in `$HOME`
- You want to move it to an XDG-compliant location (e.g., `~/.config/`, `~/.local/share/`)
- You want automatic backups and fallback symlinks

Use `add-dotfile.sh` when:
- You're managing individual configuration **files** (not directories)
- You want to track them in your dotfiles repo

### What it does

1. **Validates** that SOURCE exists and DESTINATION parent exists
2. **Creates backup** with timestamp: `SOURCE.backup.YYYYMMDD_HHMMSS`
3. **Moves contents** from SOURCE to DESTINATION
4. **Creates symlink** from SOURCE to DESTINATION (for backward compatibility)
5. **Generates rollback script** for easy reversal

### Example session

```bash
$ migrate-directory.sh ~/.myapp ~/.config/myapp --dry-run

migrate-directory.sh
============================================================

SOURCE:      /Users/brandel/.myapp
DESTINATION: /Users/brandel/.config/myapp

Contents:
  Size:  8.2M
  Files: 47

[DRY-RUN] No changes will be made

Steps that would be performed:
  1. Create backup:   .myapp.backup.20260206_143000
  2. Create dest:     mkdir -p ~/.config/myapp
  3. Move contents:   mv ~/.myapp/* ~/.config/myapp/
  4. Create symlink:  ln -s ~/.config/myapp ~/.myapp

To execute: migrate-directory.sh "~/.myapp" "~/.config/myapp" --execute
To rollback: migrate-directory.sh "~/.myapp" "~/.config/myapp" --rollback
```

Then execute:

```bash
$ migrate-directory.sh ~/.myapp ~/.config/myapp --execute

migrate-directory.sh
============================================================

SOURCE:      /Users/brandel/.myapp
DESTINATION: /Users/brandel/.config/myapp

Contents:
  Size:  8.2M
  Files: 47

Creating backup: /Users/brandel/.myapp.backup.20260206_143000
  [OK] Backup created
Creating destination directory: /Users/brandel/.config/myapp
  [INFO] Moving contents from /Users/brandel/.myapp to /Users/brandel/.config/myapp
Creating fallback symlink: /Users/brandel/.myapp → /Users/brandel/.config/myapp
  [OK] Migration complete!

Summary:
  Original:   /Users/brandel/.myapp (now → symlink to /Users/brandel/.config/myapp)
  New home:   /Users/brandel/.config/myapp
  Backup:     /Users/brandel/.myapp.backup.20260206_143000

To rollback: bash /Users/brandel/.myapp.rollback.20260206_143000.sh
```

### Options

| Flag | Description |
|------|-------------|
| (none) | Dry-run mode (default, no changes) |
| `--dry-run` | Explicit dry-run mode |
| `--execute` | Perform the migration |
| `--rollback` | Restore from the latest backup |

### Safety features

- **Dry-run by default** -- nothing changes without `--execute`
- **Automatic backups** -- timestamped backup created before any changes
- **Fallback symlinks** -- SOURCE becomes symlink to DESTINATION for backward compatibility
- **Rollback script** -- auto-generated bash script to undo everything
- **Validation** -- checks that SOURCE exists and DESTINATION parent exists
- **Idempotent** -- can run multiple times safely

### Common workflows

**Install a new app and migrate immediately:**

```bash
# App creates ~/.newapp/ during installation
# Then migrate it:
migrate-directory.sh ~/.newapp ~/.config/newapp --execute

# Done. App still works, but data is now in ~/.config/newapp/
# Original ~/.newapp is now a symlink for backward compatibility
```

**Move cache directories:**

```bash
# Move app cache to XDG_CACHE_HOME
migrate-directory.sh ~/.myapp-cache ~/.cache/myapp --execute
```

**Move state/data directories:**

```bash
# Move app data to XDG_DATA_HOME
migrate-directory.sh ~/.myapp-data ~/.local/share/myapp --execute
```

**Undo a migration:**

```bash
# Find the rollback script
ls -la ~/.myapp.rollback.*.sh

# Execute it
bash ~/.myapp.rollback.20260206_143000.sh
```

---

## home-cleanup.sh

Migrates non-essential hidden directories from `$HOME` to proper XDG Base Directory locations.

### Basic usage

```bash
# Preview all waves (dry-run, no changes)
home-cleanup.sh

# Preview a specific wave
home-cleanup.sh --wave 1

# Execute all waves
home-cleanup.sh --execute

# Execute a specific wave
home-cleanup.sh --wave 2 --execute
```

### The 5 waves

Migrations are organized in dependency-ordered waves:

#### Wave 1: Foundation

Package managers and basic tooling.

| Item | From | To | Strategy |
|------|------|----|----------|
| npm cache | `~/.npm` | `~/.cache/npm` | env var (`NPM_CONFIG_CACHE`) |
| node history | `~/.node_repl_history` | `~/.local/state/node_repl_history` | env var |
| .dotnet | `~/.dotnet` | `~/.local/share/dotnet` | env var (`DOTNET_CLI_HOME`) |
| .aspnet | `~/.aspnet` | `~/.local/share/aspnet` | symlink |
| .nuget | `~/.nuget` | `~/.local/share/NuGet` | env var (`NUGET_PACKAGES`) |

#### Wave 2: Runtimes

Language runtime managers.

| Item | From | To | Strategy |
|------|------|----|----------|
| nvm | `~/.nvm` | `~/.local/share/nvm` | env var (`NVM_DIR`) |
| bun | `~/.bun` | `~/.local/share/bun` | env var (`BUN_INSTALL`) |
| gem | `~/.gem` | `~/.local/share/gem` | env var (`GEM_HOME`) |
| pub-cache | `~/.pub-cache` | `~/.cache/pub` | env var (`PUB_CACHE`) |

#### Wave 3: Tool Configs

Application configurations.

| Item | From | To | Strategy |
|------|------|----|----------|
| docker | `~/.docker` | `~/.config/docker` | env var (`DOCKER_CONFIG`) |
| oh-my-zsh | `~/.oh-my-zsh` | `~/.local/share/oh-my-zsh` | env var + symlink |
| android | `~/.android` | `~/.local/share/android` | env var |

#### Wave 4: Symlink-Only

Directories that don't support env vars -- compatibility symlinks are used.

| Item | From | To |
|------|------|----|
| iterm2 | `~/.iterm2` | `~/.config/iterm2` |
| dart-tool | `~/.dart-tool` | `~/.local/share/dart` |
| vim | `~/.vim` | `~/.config/vim` |

#### Wave 5: Cleanup

Stale files and broken backups.

- Old bash history (if zsh is primary)
- `.zshrc.bak` files (dotfiles should be version controlled)
- Broken `.backup.*` symlinks in HOME

### Migration strategies

| Strategy | How it works |
|----------|--------------|
| `envvar` | Sets an environment variable in your shell config so the tool finds its data in the new location. Original directory is removed. |
| `symlink` | Creates a symlink from old location to new location. The tool doesn't know the difference. |
| `envvar+symlink` | Both: sets the env var AND creates a compatibility symlink. Belt and suspenders. |

### Safety features

1. **Dry-run by default** -- nothing changes without `--execute`
2. **Pre-migration backups** -- `~/.npm.pre-migration` created before any migration
3. **Checksums** -- SHA-256 verified after rsync
4. **Test commands** -- each migration runs a test (e.g., `npm --version`) to verify the tool still works
5. **Auto-rollback** -- if the test fails, the migration is automatically reversed
6. **Manifest** -- all state tracked in `~/.local/state/home-cleanup/manifest.json`
7. **Rollback script** -- auto-generated to undo everything
8. **Idempotent** -- already-migrated items are skipped

### Example dry-run output

```
Home Directory Cleanup - DRY-RUN
================================================================

  This preview shows what would happen with --execute.
  No changes will be made.

WAVE 1: Foundation (no dependencies)
--------------------------------------------------

  [ ] npm-cache                       (45M)
      From:     ~/.npm
      To:       ~/.cache/npm
      Strategy: env var (NPM_CONFIG_CACHE)
      Test:     npm cache ls 2>/dev/null || npm --version

  [x] node-repl-history               ALREADY DONE

WAVE 2: Runtimes
--------------------------------------------------

  [ ] nvm                             (312M)
      From:     ~/.nvm
      To:       ~/.local/share/nvm
      Strategy: env var (NVM_DIR)
      Test:     command -v nvm ...

================================================================
Summary:
  Directories to migrate: 15
  Already migrated:       3
  Total size:             487M

  Status: DRY-RUN - no changes made
  Next:   Run with --execute to proceed
```

### Disabling specific tools

Edit your `.env` to skip tools you don't use:

```bash
INCLUDE_DOCKER="false"    # Skip Docker migration
INCLUDE_ANDROID="false"   # Skip Android migration
INCLUDE_BUN="false"       # Skip Bun migration
```

### Rollback

If something goes wrong:

```bash
# Preview what will be reverted
./scripts/rollback-home-cleanup.sh

# Execute rollback
./scripts/rollback-home-cleanup.sh --execute

# Also clean up pre-migration backups
./scripts/rollback-home-cleanup.sh --execute --clean-backups
```

---

## Configuration

### The .env file

Located at `~/.local/share/dotfile-automation/.env` (after installation).

```bash
# Core paths
DOTFILES_DIR="$HOME/.dotfiles"
CONF_FILE="$DOTFILES_DIR/dotfiles.conf"
SHELL_ENV_FILE="$HOME/.zshenv"

# XDG directories
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_STATE_HOME="$HOME/.local/state"

# Feature flags for home-cleanup.sh
INCLUDE_NPM="true"
INCLUDE_DOCKER="true"
# ... etc
```

### Environment variable reference

| Variable | Used by | Default | Description |
|----------|---------|---------|-------------|
| `DOTFILES_DIR` | all scripts | `$HOME/.dotfiles` | Path to your dotfiles repository |
| `CONF_FILE` | symlink-check, add-dotfile | `$DOTFILES_DIR/dotfiles.conf` | Path to symlink registry |
| `SHELL_ENV_FILE` | home-cleanup | `$HOME/.zshenv` | Shell config for env var exports |
| `XDG_CONFIG_HOME` | home-cleanup | `$HOME/.config` | XDG config directory |
| `XDG_CACHE_HOME` | home-cleanup | `$HOME/.cache` | XDG cache directory |
| `XDG_DATA_HOME` | home-cleanup | `$HOME/.local/share` | XDG data directory |
| `XDG_STATE_HOME` | home-cleanup | `$HOME/.local/state` | XDG state directory |

---

## The dotfiles.conf format

A plain text file with colon-delimited fields:

```
source:description:destination
```

| Field | Description |
|-------|-------------|
| `source` | Path to the canonical file in your dotfiles repo |
| `description` | Human-readable label (shown in status output) |
| `destination` | Where the symlink should exist on the system |

**Rules:**
- Use `~` for home directory (scripts expand it automatically)
- Lines starting with `#` are comments
- Empty lines are ignored
- Fields are separated by colons (`:`)

**Example:**

```
# Shell
~/.dotfiles/.zshrc:Zsh configuration:~/.zshrc

# Git
~/.dotfiles/.gitconfig:Git configuration:~/.gitconfig

# Terminal
~/.dotfiles/config/alacritty/alacritty.toml:Alacritty config:~/.config/alacritty/alacritty.toml
```

---

## Troubleshooting

### symlink-check.sh reports MISSING_SOURCE

The file listed in the `source` column of `dotfiles.conf` does not exist. This means your dotfiles repo is missing that file. Either:
- The file was deleted from the repo
- The path in `dotfiles.conf` has a typo

Fix: correct the path in `dotfiles.conf` or restore the file to the repo.

### add-dotfile.sh says "already a symlink to the dotfiles repo"

The file is already managed. If you need to update the registry entry, edit `dotfiles.conf` directly.

### home-cleanup.sh test fails and rolls back

The test command for a migration failed, which means the tool can't find its data in the new location. Common causes:
- The tool doesn't respect the environment variable
- The shell hasn't been reloaded (run `source ~/.zshenv` or open a new terminal)
- The tool has a hardcoded path

Fix: check if the tool supports XDG directories. If not, use `symlink` strategy instead of `envvar`.

### Scripts can't find dotfiles.conf

Check your `.env` configuration:

```bash
cat ~/.local/share/dotfile-automation/.env | grep -E 'DOTFILES_DIR|CONF_FILE'
```

Make sure the paths point to existing files.

### Colors don't show in output

Colors are automatically disabled when output is piped or redirected. This is by design. If you're running in a terminal and don't see colors, make sure your terminal supports ANSI escape codes.

---

## FAQ

**Q: Does this work on Linux?**

**A:** The scripts are primarily tested on macOS. Most functionality should work on Linux, but `stat` flags differ between macOS and GNU coreutils. The `dir_size_bytes` and `dir_checksum` functions in `home-cleanup.sh` have fallbacks for both.

**Q: Can I use a different dotfiles directory name?**

**A:** Yes. Set `DOTFILES_DIR` in your `.env` to any path (e.g., `$HOME/dotfiles`, `$HOME/.config/dotfiles`).

**Q: What if I use bash instead of zsh?**

**A:** Set `SHELL_ENV_FILE="$HOME/.bashrc"` in your `.env`. The `home-cleanup.sh` script will add environment variables there instead of `.zshenv`.

**Q: Is it safe to run home-cleanup.sh multiple times?**

**A:** Yes. It's idempotent. Already-migrated items are detected and skipped.

**Q: How do I add a new tool to home-cleanup.sh?**

**A:** Add a `migrate_entry` call in the appropriate wave function. See the existing entries for the pattern. You'll need: the source path, destination path, strategy, env var name (if applicable), and a test command.

**Q: What if I don't use some of the tools listed in home-cleanup.sh?**

**A:** Set the corresponding `INCLUDE_*` variable to `"false"` in your `.env`. Or just leave it -- the script safely skips directories that don't exist.

**Q: Can I undo a home-cleanup migration?**

**A:** Yes. Run the auto-generated rollback script: `./scripts/rollback-home-cleanup.sh --execute`. It uses the manifest to reverse all migrations in the correct order.
