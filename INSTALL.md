# Installation Guide

## Prerequisites

- macOS 11+ (Big Sur or later)
- bash 3.2+ (ships with macOS)
- rsync (ships with macOS)
- python3 (ships with macOS 12.3+)
- An existing dotfiles directory (e.g., `~/.dotfiles`)

Verify prerequisites:

```bash
bash --version        # Should be 3.2+
rsync --version       # Should output version info
python3 --version     # Should be 3.9+
```

## Quick install (recommended)

```bash
# Clone the repository
git clone https://github.com/mektigh/dotfile-automation.git /tmp/dotfile-automation

# Run the installer
/tmp/dotfile-automation/examples/install.sh
```

The installer will:
1. Copy scripts to `~/.local/share/dotfile-automation/`
2. Create symlinks in `~/.local/bin/` for each command
3. Generate a `.env` configuration file
4. Copy a starter `dotfiles.conf` to your dotfiles directory
5. Verify the installation

## Manual install

If you prefer to install manually:

```bash
# 1. Clone the repo
git clone https://github.com/mektigh/dotfile-automation.git
cd dotfile-automation

# 2. Create the install directory
mkdir -p ~/.local/share/dotfile-automation/scripts
mkdir -p ~/.local/share/dotfile-automation/examples
mkdir -p ~/.local/bin

# 3. Copy scripts
cp scripts/*.sh ~/.local/share/dotfile-automation/scripts/
cp examples/dotfiles.conf.example ~/.local/share/dotfile-automation/examples/
cp .env.example ~/.local/share/dotfile-automation/

# 4. Make scripts executable
chmod +x ~/.local/share/dotfile-automation/scripts/*.sh

# 5. Create your .env config (copy the template and customize)
cp ~/.local/share/dotfile-automation/.env.example ~/.local/share/dotfile-automation/.env
# Optional: edit to customize paths and feature flags
vi ~/.local/share/dotfile-automation/.env

# 6. Create command symlinks
ln -s ~/.local/share/dotfile-automation/scripts/symlink-check.sh ~/.local/bin/symlink-check.sh
ln -s ~/.local/share/dotfile-automation/scripts/add-dotfile.sh ~/.local/bin/add-dotfile.sh
ln -s ~/.local/share/dotfile-automation/scripts/home-cleanup.sh ~/.local/bin/home-cleanup.sh

# 7. Ensure ~/.local/bin is in your PATH
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshenv
source ~/.zshenv

# 8. Create your dotfiles registry
cp examples/dotfiles.conf.example ~/.dotfiles/dotfiles.conf
vi ~/.dotfiles/dotfiles.conf
```

## Understanding the .env file

### What is .env?

The `.env` file is a **shell configuration template** that all scripts in dotfile-automation read on startup.

- **Location after installation:** `~/.local/share/dotfile-automation/.env`
- **Source:** Created by copying `.env.example` from the repository
- **Purpose:** Tells scripts where your dotfiles are, which tools to migrate, and where to put files

### How scripts use .env

Every script begins with:

```bash
# In scripts/lib.sh:
load_env() {
    local env_file="${DOTFILE_AUTOMATION_DIR}/.env"
    if [[ -f "$env_file" ]]; then
        source "$env_file"  # Reads your configuration
    fi
    # Apply defaults if not set
    DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
    ...
}
```

This means:
1. Your scripts read `.env` to get your preferences
2. If a variable is missing, sensible defaults are used
3. You can customize paths and feature flags without editing script code

### Do I need to change .env?

**Short answer:** Probably not. The defaults work for most people.

**Change .env if:**
- Your dotfiles are somewhere other than `~/.dotfiles`
- You use bash instead of zsh
- You don't use certain tools (Docker, nvm, etc.) and want to skip their migration
- You want config files in different XDG locations

Otherwise, the installer creates a `.env` that just works.

---

## Post-install setup

### 1. Add `~/.local/bin` to your PATH

If not already in your PATH, add to your shell config:

**zsh** (`~/.zshenv`):
```bash
export PATH="$HOME/.local/bin:$PATH"
```

**bash** (`~/.bashrc` or `~/.bash_profile`):
```bash
export PATH="$HOME/.local/bin:$PATH"
```

### 2. Configure your dotfiles registry

Edit `~/.dotfiles/dotfiles.conf` (or wherever your dotfiles live):

```bash
vi ~/.dotfiles/dotfiles.conf
```

Add entries for each dotfile you manage. Format:

```
source:description:destination
```

Example:

```
~/.dotfiles/.zshrc:Zsh configuration:~/.zshrc
~/.dotfiles/.gitconfig:Git configuration:~/.gitconfig
```

### 3. Verify installation

```bash
# Check that commands are available
which symlink-check.sh
which add-dotfile.sh
which home-cleanup.sh

# Run a symlink check
symlink-check.sh

# Preview HOME cleanup
home-cleanup.sh
```

### 4. Understand and customize .env (optional)

The `.env` file is a **configuration file that all scripts read** to know:
- Where your dotfiles repository is
- Which tools to migrate in HOME cleanup
- Where to put config, cache, and data files

**Location:** `~/.local/share/dotfile-automation/.env`

The file is created from `.env.example` during installation. You can customize it:

```bash
vi ~/.local/share/dotfile-automation/.env
```

#### Core configuration (usually fine as-is)

| Variable | Default | Description |
|----------|---------|-------------|
| `DOTFILES_DIR` | `$HOME/.dotfiles` | Path to your dotfiles repository |
| `CONF_FILE` | `$DOTFILES_DIR/dotfiles.conf` | Path to your symlink registry |
| `SHELL_ENV_FILE` | `$HOME/.zshenv` | Shell config for env var exports (use `~/.bashrc` for bash) |

#### XDG Base Directory paths

These determine where tools store files when migrated by `home-cleanup.sh`:

| Variable | Default | Purpose |
|----------|---------|---------|
| `XDG_CONFIG_HOME` | `$HOME/.config` | Configuration files (e.g., `~/.config/docker`) |
| `XDG_CACHE_HOME` | `$HOME/.cache` | Cache files (e.g., `~/.cache/npm`) |
| `XDG_DATA_HOME` | `$HOME/.local/share` | Application data (e.g., `~/.local/share/nvm`) |
| `XDG_STATE_HOME` | `$HOME/.local/state` | Runtime state and logs |

#### Feature flags (customize which tools to migrate)

Enable/disable specific tool migrations in `home-cleanup.sh`:

```bash
# Set to "false" to skip tools you don't use
INCLUDE_DOCKER="true"        # Docker configuration
INCLUDE_NVM="true"           # Node Version Manager
INCLUDE_BUN="true"           # Bun package manager
INCLUDE_PYTHON="true"        # Python packages
# ... and more (see .env.example for complete list)
```

**No need to edit:** All settings have sensible defaults. The installer creates your `.env` automatically. Only customize if your setup differs from the defaults (e.g., you use bash instead of zsh, or your dotfiles live elsewhere).

See `.env.example` for the complete list of all available variables and detailed explanations.

## Updating

To update to the latest version:

```bash
cd /path/to/dotfile-automation
git pull

# Re-run the installer (it preserves your .env)
./examples/install.sh
```

## Uninstalling

```bash
# Remove command symlinks
rm -f ~/.local/bin/symlink-check.sh
rm -f ~/.local/bin/add-dotfile.sh
rm -f ~/.local/bin/home-cleanup.sh

# Remove installed scripts
rm -rf ~/.local/share/dotfile-automation

# Remove state data (if you used home-cleanup.sh)
rm -rf ~/.local/state/home-cleanup

# Your dotfiles.conf and actual dotfiles are untouched
```

## Troubleshooting

### "command not found" after installation

Make sure `~/.local/bin` is in your PATH:

```bash
echo $PATH | tr ':' '\n' | grep local
```

If not present, add it to your shell config and reload:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshenv
source ~/.zshenv
```

### "Config file not found"

Check that `CONF_FILE` in `.env` points to an existing file:

```bash
cat ~/.local/share/dotfile-automation/.env | grep CONF_FILE
```

### Scripts fail with "permission denied"

Make sure the scripts are executable:

```bash
chmod +x ~/.local/share/dotfile-automation/scripts/*.sh
```
