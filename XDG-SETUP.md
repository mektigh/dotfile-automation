# XDG Base Directory Setup Guide

A comprehensive guide to organizing macOS dotfiles using the XDG Base Directory Specification. This document covers the what, why, and how of XDG compliance on macOS, including tool-specific configurations and migration procedures.

---

## Table of Contents

1. [What is XDG Base Directory Specification?](#what-is-xdg-base-directory-specification)
2. [macOS Default vs XDG Standard](#macos-default-vs-xdg-standard)
3. [Environment Variables](#environment-variables)
4. [Directory Layout](#directory-layout)
5. [Tool-Specific Configurations](#tool-specific-configurations)
6. [Migration Scripts](#migration-scripts)
7. [Migration Checklist](#migration-checklist)
8. [Verification](#verification)
9. [Rollback Instructions](#rollback-instructions)
10. [Troubleshooting](#troubleshooting)

---

## What is XDG Base Directory Specification?

The **XDG Base Directory Specification** is a [freedesktop.org standard](https://specifications.freedesktop.org/basedir-spec/latest/) that defines where applications should store their files. Originally created for Linux desktop environments, it has become the de facto standard for organizing dotfiles across Unix-like systems.

### History

- **2003**: First published by freedesktop.org as part of the XDG (X Desktop Group) standards
- **2010s**: Adopted broadly by Linux tools (git, vim, zsh, etc.)
- **2020s**: Increasingly adopted on macOS as developers move toward cross-platform consistency

### The Problem It Solves

Without XDG, every tool dumps its configuration, cache, and state files directly into `$HOME`:

```
~/
  .bashrc
  .bash_history
  .vimrc
  .viminfo
  .gitconfig
  .npmrc
  .docker/
  .nvm/
  .bun/
  .gem/
  .oh-my-zsh/
  .claude.json
  .mailcap
  .mime.types
  ... (50+ dotfiles and directories)
```

This creates a cluttered HOME directory where configuration, cache, state, and data are all mixed together. You cannot easily:

- Back up just your configuration (without caches)
- Clear caches without risking config loss
- Audit what tools are installed
- Keep HOME clean and navigable

### The Solution

XDG separates files by **purpose**:

| Purpose | Variable | Default Path | What goes here |
|---------|----------|-------------|----------------|
| Configuration | `XDG_CONFIG_HOME` | `~/.config/` | Settings, preferences, rc files |
| Data | `XDG_DATA_HOME` | `~/.local/share/` | Persistent application data |
| State | `XDG_STATE_HOME` | `~/.local/state/` | Logs, history, session state |
| Cache | `XDG_CACHE_HOME` | `~/.cache/` | Regeneratable cached data |
| Runtime | `XDG_RUNTIME_DIR` | `/tmp/` | Sockets, locks (session-scoped) |

### Benefits

- **Clean HOME**: Only critical files remain (`.ssh`, `.zshenv`, `.zsh_history`)
- **Easy backups**: Back up `~/.config/` for all your settings
- **Safe cache clearing**: Delete `~/.cache/` without losing configuration
- **Portability**: Same layout works on Linux and macOS
- **Auditability**: `ls ~/.config/` shows every configured tool at a glance
- **Standardization**: One convention instead of every tool inventing its own

---

## macOS Default vs XDG Standard

macOS has its own conventions for application storage that differ from XDG. Here is how the two systems compare:

```
macOS Default (Apple convention):
  ~/Library/Application Support/  --> App-specific persistent data
  ~/Library/Caches/               --> App caches (system may purge)
  ~/Library/Preferences/          --> App preferences (plist files)
  ~/Library/Logs/                 --> App log files
  ~/ (HOME root)                  --> CLI config files (.zshrc, .gitconfig, etc.)

XDG Standard (what we use):
  ~/.config/                      --> Configuration     (XDG_CONFIG_HOME)
  ~/.local/share/                 --> Application data  (XDG_DATA_HOME)
  ~/.local/state/                 --> State/logs        (XDG_STATE_HOME)
  ~/.cache/                       --> Caches            (XDG_CACHE_HOME)
  ~/                              --> ONLY critical files (.ssh, .zshenv)
```

### Why XDG on macOS?

macOS GUI applications use `~/Library/` and that is fine -- we do not touch those. But CLI tools (git, vim, zsh, node, docker, etc.) historically dump files into `$HOME` because they originated on Linux systems that had no standard. XDG gives them a home.

The key insight: **XDG and macOS conventions are complementary, not conflicting.**

- GUI apps: `~/Library/` (Apple convention)
- CLI tools: `~/.config/`, `~/.cache/`, etc. (XDG convention)
- Both: Clean, organized, purposeful

---

## Environment Variables

All XDG variables are set in `~/.zshenv` (loaded for every shell invocation, including scripts and non-interactive shells).

### Core XDG Variables

```bash
# ~/.dotfiles/.zshenv (symlinked to ~/.zshenv)

# XDG Base Directory Specification
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_STATE_HOME="$HOME/.local/state"

# Ensure directories exist
[[ ! -d "$XDG_CONFIG_HOME" ]] && mkdir -p "$XDG_CONFIG_HOME"
[[ ! -d "$XDG_CACHE_HOME" ]] && mkdir -p "$XDG_CACHE_HOME"
[[ ! -d "$XDG_DATA_HOME" ]] && mkdir -p "$XDG_DATA_HOME"
[[ ! -d "$XDG_STATE_HOME" ]] && mkdir -p "$XDG_STATE_HOME"
```

### Tool-Specific Variables

```bash
# Package managers
export NPM_CONFIG_CACHE="$XDG_CACHE_HOME/npm"
export GEM_HOME="$XDG_DATA_HOME/gem"
export PUB_CACHE="$XDG_CACHE_HOME/pub"
export NUGET_PACKAGES="$XDG_DATA_HOME/NuGet/packages"

# Runtimes
export NVM_DIR="$XDG_DATA_HOME/nvm"
export DOTNET_CLI_HOME="$XDG_DATA_HOME/dotnet"

# Tools
export DOCKER_CONFIG="$XDG_CONFIG_HOME/docker"
export ZSH="$XDG_DATA_HOME/oh-my-zsh"
export ANDROID_USER_HOME="$XDG_DATA_HOME/android"

# Vim (sources vimrc from XDG location)
export VIMINIT='source $XDG_CONFIG_HOME/vim/vimrc'

# Mailcap (MIME type handlers)
export MAILCAPS="$XDG_CONFIG_HOME/mailcap"

# Shell history (explicit, stays in HOME)
export HISTFILE="$HOME/.zsh_history"
```

### Why .zshenv?

Zsh has multiple config files loaded at different stages:

| File | When loaded | Use for |
|------|-------------|---------|
| `.zshenv` | ALWAYS (every shell) | Environment variables, PATH |
| `.zprofile` | Login shells only | Login-time setup |
| `.zshrc` | Interactive shells only | Aliases, prompt, completions |
| `.zlogin` | Login shells (after .zshrc) | Post-login commands |

Environment variables **must** go in `.zshenv` because:
- Scripts need them (scripts don't load `.zshrc`)
- Subshells need them
- IDE terminals need them
- cron jobs need them

---

## Directory Layout

After full XDG migration, your directory structure looks like this:

```
~/.config/                          # XDG_CONFIG_HOME
  aider/                            # Aider AI assistant config
  chezmoi/                          # Chezmoi dotfile manager
  claude/                           # Claude CLI settings
    settings.json                   # (symlinked from ~/.claude.json)
  docker/                           # Docker configuration
  fish/                             # Fish shell config
  gcloud/                           # Google Cloud SDK config
  gemini/                           # Google Gemini CLI
  gh/                               # GitHub CLI config
  ghostty/                          # Ghostty terminal config
  gmailctl/                         # Gmail filter manager
  iterm2/                           # iTerm2 preferences
  kitty/                            # Kitty terminal config
  mailcap                           # MIME type handlers
  mime.types                        # MIME type definitions
  nvim/                             # Neovim config
  ranger/                           # Ranger file manager
  raycast/                          # Raycast launcher
  sketchybar/                       # SketchyBar menu bar
  vim/                              # Vim config
    vimrc                           # Vim configuration file
    viminfo                         # Vim session state
  wrangler/                         # Cloudflare Wrangler
  zed/                              # Zed editor config
  zsh/                              # Zsh-specific config

~/.cache/                           # XDG_CACHE_HOME
  npm/                              # npm package cache
  pub/                              # Dart pub cache

~/.local/share/                     # XDG_DATA_HOME
  android/                          # Android SDK user data
  aspnet/                           # ASP.NET data protection keys
  dart/                             # Dart SDK data
  dotnet/                           # .NET CLI data
  gem/                              # Ruby gems
  mail/                             # Local mail storage
  nvm/                              # Node Version Manager
  NuGet/                            # NuGet package data
  oh-my-zsh/                        # Oh My Zsh framework

~/.local/state/                     # XDG_STATE_HOME
  node_repl_history                 # Node REPL history
  home-cleanup/                     # Migration state/manifest

~/                                  # HOME (minimal)
  .ssh/                             # SSH keys (must stay here)
  .zshenv -> .dotfiles/.zshenv      # Env vars (must be in HOME)
  .zsh_history                      # Shell history
  .claude.json -> .config/claude/settings.json
  .dotfiles/                        # Version-controlled dotfile source
```

---

## Tool-Specific Configurations

### Vim

Vim does not natively support XDG, but the `VIMINIT` environment variable lets us redirect it.

**Setup:**

1. Set `VIMINIT` in `.zshenv`:
   ```bash
   export VIMINIT='source $XDG_CONFIG_HOME/vim/vimrc'
   ```

2. Create `~/.config/vim/vimrc`:
   ```vim
   " Store viminfo in XDG config directory
   set viminfofile=$XDG_CONFIG_HOME/vim/viminfo

   " Source the original vimrc if it exists (migration compatibility)
   if filereadable(expand('~/.vimrc'))
       source ~/.vimrc
   endif
   ```

3. Move `.viminfo` to `~/.config/vim/viminfo`

**Why:** Vim creates `.viminfo` (marks, registers, search history) and `.vimrc` (configuration) in HOME. Neither supports XDG natively, but `VIMINIT` + `viminfofile` achieves the same result.

**Verify:** `vim +q` then check `ls ~/.config/vim/viminfo`

### Zsh History

**Setup:**
```bash
# In .zshenv
export HISTFILE="$HOME/.zsh_history"
```

**Why:** The history file stays in HOME because it is a critical file that should remain accessible even if XDG directories are missing. Setting `HISTFILE` explicitly documents this choice and makes it easy to relocate later if desired.

**Verify:** `echo $HISTFILE` should show the path.

### Git

Git natively supports XDG since version 2.0:
- Config: `~/.config/git/config` (checked before `~/.gitconfig`)
- Ignore: `~/.config/git/ignore` (global gitignore)
- Attributes: `~/.config/git/attributes`

**Current setup:** `~/.gitconfig` is symlinked from `.dotfiles/`. Git checks both locations automatically.

**Verify:** `git config --list --show-origin | head -5`

### npm

**Setup:**
```bash
export NPM_CONFIG_CACHE="$XDG_CACHE_HOME/npm"
```

**Why:** npm stores its package cache in `~/.npm` by default. The cache can be safely regenerated, so it belongs in `XDG_CACHE_HOME`.

**Verify:** `npm cache ls 2>/dev/null; echo $NPM_CONFIG_CACHE`

### Docker

**Setup:**
```bash
export DOCKER_CONFIG="$XDG_CONFIG_HOME/docker"
```

**Why:** Docker stores auth tokens and configuration in `~/.docker/`. Moving to XDG keeps credentials organized with other config.

**Verify:** `docker version 2>/dev/null; ls $DOCKER_CONFIG/`

### NVM (Node Version Manager)

**Setup:**
```bash
export NVM_DIR="$XDG_DATA_HOME/nvm"
```

**Why:** NVM stores installed Node versions (persistent data, not config), so it belongs in `XDG_DATA_HOME`.

**Verify:** `command -v nvm; nvm ls`

### Oh My Zsh

**Setup:**
```bash
export ZSH="$XDG_DATA_HOME/oh-my-zsh"
```

**Why:** Oh My Zsh is a framework (data/plugins), not user configuration. It belongs in `XDG_DATA_HOME`.

**Verify:** `test -d $ZSH/plugins && echo "OK"`

### Claude CLI

**Setup:** Symlink approach (Claude CLI hardcodes `~/.claude.json`):
```
~/.claude.json -> ~/.config/claude/settings.json
```

**Why:** Claude CLI does not respect XDG or environment variables. A symlink maintains compatibility while keeping the actual file in the XDG location.

**Verify:** `ls -la ~/.claude.json` (should show symlink)

### Mailcap and MIME Types

**Setup:**
```bash
export MAILCAPS="$XDG_CONFIG_HOME/mailcap"
# mime.types: standard XDG lookup path, no env var needed
```

**Why:** These are configuration files that define how MIME types are handled. They belong in `XDG_CONFIG_HOME`.

**Verify:** `cat $XDG_CONFIG_HOME/mailcap; cat $XDG_CONFIG_HOME/mime.types`

---

## Migration Scripts

This repository includes two migration scripts that work together:

### 1. home-cleanup.sh -- Directory Migrations

Handles directories (`.npm/`, `.nvm/`, `.docker/`, etc.) in 5 dependency-ordered waves:

```bash
# Preview what would happen
./home-cleanup.sh

# Execute all waves
./home-cleanup.sh --execute

# Execute only wave 2 (runtimes)
./home-cleanup.sh --wave 2 --execute
```

### 2. migrate-dotfiles-to-xdg.sh -- File Migrations

Handles individual dotfiles (`.viminfo`, `.mailcap`, `.claude.json`, etc.):

```bash
# Preview what would happen
./migrate-dotfiles-to-xdg.sh

# Execute migrations
./migrate-dotfiles-to-xdg.sh --execute
```

### 3. cleanup-home-unnecessary.sh -- Stale File Removal

Removes auto-generated cache files and stale remnants:

```bash
# Preview
./cleanup-home-unnecessary.sh

# Execute
./cleanup-home-unnecessary.sh --execute
```

### Recommended Execution Order

```bash
# Step 1: Migrate directories first (establishes XDG structure)
./home-cleanup.sh --execute

# Step 2: Migrate remaining dotfiles
./migrate-dotfiles-to-xdg.sh --execute

# Step 3: Clean up stale files
./cleanup-home-unnecessary.sh --execute

# Step 4: Reload shell
source ~/.zshenv

# Step 5: Verify
ls -la ~/           # Should be minimal
ls ~/.config/       # Should have all your tools
```

---

## Migration Checklist

### Directories (via home-cleanup.sh)

- [x] `.npm` moved to `.cache/npm/` (NPM_CONFIG_CACHE)
- [x] `.node_repl_history` moved to `.local/state/` (NODE_REPL_HISTORY)
- [x] `.dotnet` moved to `.local/share/dotnet/` (DOTNET_CLI_HOME)
- [x] `.aspnet` moved to `.local/share/aspnet/` (symlink)
- [x] `.nuget` moved to `.local/share/NuGet/` (NUGET_PACKAGES)
- [x] `.nvm` moved to `.local/share/nvm/` (NVM_DIR)
- [x] `.gem` moved to `.local/share/gem/` (GEM_HOME)
- [x] `.pub-cache` moved to `.cache/pub/` (PUB_CACHE)
- [x] `.docker` moved to `.config/docker/` (DOCKER_CONFIG)
- [x] `.oh-my-zsh` moved to `.local/share/oh-my-zsh/` (ZSH)
- [x] `.android` moved to `.local/share/android/` (ANDROID_USER_HOME)
- [x] `.iterm2` moved to `.config/iterm2/` (symlink)
- [x] `.dart-tool` moved to `.local/share/dart/` (symlink)
- [x] `.aider` moved to `.config/aider/` (symlink)
- [x] `.wrangler` moved to `.config/wrangler/` (symlink)
- [x] `.gemini` moved to `.config/gemini/` (symlink)
- [x] `.gmailctl` moved to `.config/gmailctl/` (symlink)
- [x] `.vim` moved to `.config/vim/` (symlink)
- [x] `.mail` moved to `.local/share/mail/` (symlink)

### Individual Files (via migrate-dotfiles-to-xdg.sh)

- [ ] `.viminfo` moved to `.config/vim/viminfo` (VIMINIT env var)
- [ ] `.mime.types` moved to `.config/mime.types` (standard lookup)
- [ ] `.mailcap` moved to `.config/mailcap` (MAILCAPS env var)
- [ ] `.claude.json` moved to `.config/claude/settings.json` (symlink)
- [ ] `.zsh_history` HISTFILE set in `.zshenv` (file stays in HOME)

### Cleanup (via cleanup-home-unnecessary.sh)

- [ ] `.zcompdump*` files removed (auto-regenerated)
- [ ] `.DS_Store` removed (auto-regenerated)
- [ ] Stale tool directories removed
- [ ] Broken symlinks removed

### Files That Stay in HOME

These files **must** remain in HOME (tools require it):

| File | Why it stays |
|------|-------------|
| `.ssh/` | SSH protocol hardcodes `~/.ssh` |
| `.zshenv` | Zsh loads this from HOME before anything else |
| `.zsh_history` | Critical file, should survive XDG issues |
| `.claude.json` | Symlink to `.config/claude/settings.json` |
| `.dotfiles/` | Version-controlled source for all config |

---

## Verification

After migration, verify everything works:

```bash
# 1. Check HOME is clean
ls -la ~/ | grep -v "^total" | wc -l
# Should be ~10-15 items (not 50+)

# 2. Check XDG directories exist and have content
ls ~/.config/
ls ~/.cache/
ls ~/.local/share/
ls ~/.local/state/

# 3. Check env vars are set
echo "CONFIG: $XDG_CONFIG_HOME"
echo "CACHE:  $XDG_CACHE_HOME"
echo "DATA:   $XDG_DATA_HOME"
echo "STATE:  $XDG_STATE_HOME"

# 4. Check tool-specific vars
echo "NPM_CONFIG_CACHE: $NPM_CONFIG_CACHE"
echo "NVM_DIR:          $NVM_DIR"
echo "DOCKER_CONFIG:    $DOCKER_CONFIG"
echo "VIMINIT:          $VIMINIT"
echo "HISTFILE:         $HISTFILE"

# 5. Test individual tools
vim +q                    # Should write to .config/vim/viminfo
npm --version             # Should use .cache/npm/
docker version            # Should use .config/docker/
git config --list | head  # Should work normally

# 6. Check symlinks
ls -la ~/.claude.json     # Should point to .config/claude/settings.json
```

---

## Rollback Instructions

Every migration script creates backups before making changes.

### Automatic Rollback (home-cleanup.sh)

The `home-cleanup.sh` script generates a rollback script automatically:

```bash
# Preview what would be reverted
./rollback-home-cleanup.sh

# Actually revert all directory migrations
./rollback-home-cleanup.sh --execute

# Also clean up pre-migration backups
./rollback-home-cleanup.sh --execute --clean-backups
```

### Manual Rollback (individual files)

For files migrated by `migrate-dotfiles-to-xdg.sh`:

```bash
# 1. Find the backup
ls -la ~/.viminfo.backup.*

# 2. Remove the migrated file (or symlink)
rm ~/.config/vim/viminfo   # or: rm ~/.claude.json (the symlink)

# 3. Restore from backup
mv ~/.viminfo.backup.20260206_193000 ~/.viminfo

# 4. Remove the env var from .zshenv
# Edit ~/.dotfiles/.zshenv and remove the relevant export line

# 5. Reload shell
source ~/.zshenv
```

### Full System Rollback

If something goes seriously wrong:

```bash
# 1. Revert directory migrations
./rollback-home-cleanup.sh --execute

# 2. Revert file migrations (manual, per file)
# For each .backup.* file in HOME:
for backup in ~/*.backup.*; do
    original="${backup%.backup.*}"
    echo "Restoring: $backup -> $original"
    # Uncomment to execute:
    # rm -f "$original"
    # mv "$backup" "$original"
done

# 3. Clean env vars from .zshenv
# Edit ~/.dotfiles/.zshenv and remove all "Added by" blocks

# 4. Reload
source ~/.zshenv
```

---

## Troubleshooting

### Tool cannot find its config after migration

**Cause:** The tool does not respect the env var, or the env var is not loaded.

**Fix:**
1. Check if the env var is set: `echo $VARIABLE_NAME`
2. Check if `.zshenv` is being loaded: `zsh -c 'echo $XDG_CONFIG_HOME'`
3. If the tool ignores env vars, use a symlink instead

### Vim writes .viminfo to HOME again

**Cause:** `VIMINIT` is not set, or vimrc does not have `viminfofile`.

**Fix:**
```bash
# Verify VIMINIT
echo $VIMINIT
# Should show: source $XDG_CONFIG_HOME/vim/vimrc

# Verify vimrc has the setting
grep viminfofile ~/.config/vim/vimrc
# Should show: set viminfofile=$XDG_CONFIG_HOME/vim/viminfo
```

### npm install fails after migration

**Cause:** npm cache directory does not exist at the new location.

**Fix:**
```bash
mkdir -p "$NPM_CONFIG_CACHE"
npm cache clean --force
```

### Claude CLI cannot find settings

**Cause:** Symlink is broken or missing.

**Fix:**
```bash
# Check symlink
ls -la ~/.claude.json

# Recreate if needed
ln -sf ~/.config/claude/settings.json ~/.claude.json
```

### Shell history is empty

**Cause:** `HISTFILE` is pointing to wrong location.

**Fix:**
```bash
echo $HISTFILE
# Should show: /Users/yourname/.zsh_history

# If empty, add to .zshenv:
export HISTFILE="$HOME/.zsh_history"
```

### Environment variables not available in scripts

**Cause:** Script uses `#!/bin/bash` (not zsh), so `.zshenv` is not loaded.

**Fix:** For bash scripts that need XDG vars, source them explicitly:
```bash
#!/bin/bash
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
```

---

## References

- [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir-spec/latest/)
- [Arch Wiki: XDG Base Directory](https://wiki.archlinux.org/title/XDG_Base_Directory)
- [XDG support in common tools](https://wiki.archlinux.org/title/XDG_Base_Directory#Support)
- [macOS File System Basics](https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/FileSystemOverview/FileSystemOverview.html)
