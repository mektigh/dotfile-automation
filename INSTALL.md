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
git clone https://github.com/YOUR_USERNAME/dotfile-automation.git /tmp/dotfile-automation

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
git clone https://github.com/YOUR_USERNAME/dotfile-automation.git
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

# 5. Create your .env config
cp ~/.local/share/dotfile-automation/.env.example ~/.local/share/dotfile-automation/.env
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

### 4. Customize .env (optional)

Edit the configuration file to match your setup:

```bash
vi ~/.local/share/dotfile-automation/.env
```

Key settings:

| Variable | Default | Description |
|----------|---------|-------------|
| `DOTFILES_DIR` | `$HOME/.dotfiles` | Path to your dotfiles repository |
| `CONF_FILE` | `$DOTFILES_DIR/dotfiles.conf` | Path to your symlink registry |
| `SHELL_ENV_FILE` | `$HOME/.zshenv` | Shell config for env var exports |
| `INCLUDE_DOCKER` | `true` | Include Docker in HOME cleanup |
| `INCLUDE_NVM` | `true` | Include nvm in HOME cleanup |
| `INCLUDE_BUN` | `true` | Include bun in HOME cleanup |

See `.env.example` for the full list.

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
