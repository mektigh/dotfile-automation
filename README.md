# dotfile-automation

A set of shell scripts that manage, validate, and organize your dotfiles on macOS.

## Why

- **Symlinks break silently.** You move a file, rename a directory, or update a tool, and a symlink quietly dies. You don't notice until something fails at the worst time.
- **HOME gets cluttered.** Every tool dumps its config, cache, and data as hidden directories in `$HOME`. Over time you end up with dozens of dotdirs that make `ls -la ~` unreadable.
- **Dotfile management is manual.** Adding a new config file to your dotfiles repo requires remembering the correct sequence: move, symlink, register. Miss a step and things drift.

dotfile-automation solves all three with five core scripts and a config file.

## What it does

| Script | Purpose |
|--------|---------|
| `symlink-check.sh` | Validates all dotfile symlinks are correct, finds broken/missing/wrong-target links, optionally repairs them |
| `add-dotfile.sh` | Onboards a new config file: moves it to your dotfiles repo, creates the symlink, registers it |
| `migrate-directory.sh` | **Generic migration tool** — moves any directory from `$HOME` to XDG locations with automatic backup and fallback symlinks |
| `home-cleanup.sh` | Migrates known tool directories from `$HOME` to proper XDG locations (`~/.config`, `~/.cache`, `~/.local/share`) |
| `lib.sh` | Shared utilities used by all scripts (colors, logging, path handling, config parsing) |

## Quick start

```bash
# 1. Clone the repo
git clone https://github.com/mektigh/dotfile-automation.git
cd dotfile-automation

# 2. Run the installer
./examples/install.sh

# 3. Edit your dotfiles registry
vi ~/.dotfiles/dotfiles.conf

# 4. Check your symlinks
symlink-check.sh

# 5. Preview HOME cleanup
home-cleanup.sh
```

## Requirements

- macOS 11+ (Big Sur or later)
- bash 3.2+ (ships with macOS)
- rsync (ships with macOS)
- python3 (ships with macOS 12.3+, used only by `home-cleanup.sh` for JSON manifest)

## Features

- **Dry-run by default** -- every destructive script previews changes before doing anything
- **Automatic backups** -- timestamped backups before any file operation
- **Idempotent** -- safe to run multiple times; already-done work is skipped
- **Configurable** -- `.env` file controls paths, feature flags, and which tools to include
- **XDG compliant** -- follows the [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir-spec/latest/)
- **Auto-rollback** -- `home-cleanup.sh` generates a rollback script and tracks state in a JSON manifest
- **No dependencies** -- uses only tools that ship with macOS (bash, rsync, python3)
- **Works from anywhere** -- scripts resolve their own location; no need to `cd` into the repo

## Project structure

```
dotfile-automation/
├── README.md                        # This file
├── INSTALL.md                       # Installation guide
├── USAGE.md                         # Command reference and examples
├── LICENSE                          # MIT license
├── .env.example                     # Configuration template
├── .gitignore                       # Git ignore rules
├── scripts/
│   ├── lib.sh                       # Shared utilities
│   ├── symlink-check.sh             # Symlink validator and fixer
│   ├── add-dotfile.sh               # Dotfile onboarding tool
│   └── home-cleanup.sh              # HOME directory organizer
└── examples/
    ├── dotfiles.conf.example        # Example symlink registry
    └── install.sh                   # Installation script
```

## How it works

### The registry: `dotfiles.conf`

All symlink management revolves around a simple text file:

```
# source:description:destination
~/.dotfiles/.zshrc:Zsh configuration:~/.zshrc
~/.dotfiles/.gitconfig:Git configuration:~/.gitconfig
~/.dotfiles/config/alacritty/alacritty.toml:Alacritty config:~/.config/alacritty/alacritty.toml
```

Each line defines: where the real file lives (in your dotfiles repo), what it is, and where the symlink should point.

### Symlink checking

`symlink-check.sh` reads the registry and verifies every entry:

```
  Zsh configuration                            OK
  Git configuration                            OK
  Alacritty config                             BROKEN (points to: /old/path)
```

With `--fix`, it repairs broken links automatically (after creating backups).

### Adding new dotfiles

`add-dotfile.sh ~/.tmux.conf` handles the entire workflow:
1. Backs up the original file
2. Moves it into your dotfiles repo (mirroring the path structure)
3. Creates a symlink at the original location
4. Registers it in `dotfiles.conf`
5. Verifies the symlink works

### HOME cleanup

`home-cleanup.sh` organizes tool directories into XDG locations across 5 waves:

| Wave | What | Example |
|------|------|---------|
| 1 | Foundation | `~/.npm` to `~/.cache/npm` |
| 2 | Runtimes | `~/.nvm` to `~/.local/share/nvm` |
| 3 | Tools | `~/.docker` to `~/.config/docker` |
| 4 | Symlinks | `~/.vim` to `~/.config/vim` |
| 5 | Cleanup | Remove stale files and broken backups |

Each migration uses the appropriate strategy (environment variable, symlink, or both) and includes automatic rollback on test failure.

## Configuration

Copy `.env.example` to `.env` and customize:

```bash
# Where your dotfiles live
DOTFILES_DIR="$HOME/.dotfiles"

# Which shell config to update with env vars
SHELL_ENV_FILE="$HOME/.zshenv"

# Enable/disable specific tool migrations
INCLUDE_DOCKER="true"
INCLUDE_NVM="true"
INCLUDE_BUN="false"     # Set to false to skip
```

See `.env.example` for all available options.

## Documentation

- **[INSTALL.md](INSTALL.md)** -- Step-by-step installation guide
- **[USAGE.md](USAGE.md)** -- Complete command reference with examples

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Make your changes
4. Test on a clean macOS system or VM
5. Submit a pull request

Please ensure:
- Scripts work with bash 3.2+ (macOS default)
- No external dependencies beyond what ships with macOS
- Dry-run mode for any destructive operations
- Backups before any file modifications

## License

[MIT](LICENSE)
