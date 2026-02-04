# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a personal Zsh configuration management repository that provides shell environment setup, dotfiles, aliases, functions, and utility scripts. It's designed to be installed on new machines to quickly set up a consistent development environment.

## Key Architecture

### Loading Hierarchy
The shell environment is loaded through a specific chain:
1. `~/.zshrc` sources `load.zsh` (added during installation)
2. `load.zsh` orchestrates all configuration loading:
   - Sets up locale and zsh options
   - Loads zsh plugins (from git submodules)
   - Sources theme
   - Sources all include files (exports, aliases, functions, keybindings, completions, history, prompt)
   - Loads syntax highlighting last (order matters)

### Directory Structure
- **dotfiles/**: Configuration files that get symlinked to `$HOME` during installation (`.gitconfig`, `.vimrc`, `.gitignore_global`, `.bazelrc`, neovim `init.lua`)
- **include/**: Modular shell configuration files sourced by `load.zsh`
  - `aliases`: All shell command aliases
  - `functions`: Shell utility functions
  - `exports`: Environment variable definitions
  - `keybindings`, `completions`, `history`, `prompt`: Shell configuration
- **scripts/**: Utility scripts added to PATH (executable tools)
  - `lib.zsh`: Shared library functions for logging and tree searching
- **zsh-plugins/**: Git submodules for external zsh plugins (path-ethic, zsh-autosuggestions, zsh-completions, zsh-history-substring-search, zsh-syntax-highlighting)
- **zsh-theme/**: Git submodule for agnoster theme
- **tests/**: Test suite using zsh-scriptest framework

## Common Commands

### Installation
```bash
./install.sh
```
This script:
- Updates git submodules
- Creates symlinks for dotfiles in `$HOME`
- Creates necessary directories (`~/.local/bin`, `$CODE/w`)
- Adds source command to `~/.zshrc`
- Sets up neovim config

### Testing
```bash
make test
# Or directly:
./tests/run_tests.sh
```

### Updating
```bash
make update_submodules
# Or use the built-in alias (available after installation):
update_profile
```

## Important Implementation Notes

### Plugin Load Order
The order of plugin loading in `load.zsh` is critical:
- `zsh-syntax-highlighting` must be loaded LAST (after all other plugins and keybindings)
- `fpath` must be updated with `zsh-completions` BEFORE running `autoload`

### Shell Function Patterns
The repository uses consistent patterns for shell functions:
- Logging: Use `__profile_log_{error,warn,info,success}` from `scripts/lib.zsh`
- Tree search: Use `__profile_search_ancestor_tree` to find files in parent directories
- Private functions: Prefix with `__profile_` to indicate internal use

### Environment Variables
- `$SHA1N_PROFILE_HOME`: Set to the repository directory path (used throughout)
- Standard variables are defined in `include/exports`

### Aliases Convention
When modifying `include/aliases`:
- Group aliases by category (comments indicate sections)
- Git aliases use current branch: `$(git branch --show-current)`
- The `alias_last` function can append new aliases dynamically

### Dotfile Symlinking
The installation creates symlinks (not copies) from `dotfiles/` to `$HOME/`. Changes to dotfiles in the repo are immediately reflected in the user's environment.

### Testing Requirements
Tests run on both Ubuntu and macOS in CI. Any changes to shell scripts should:
- Be POSIX-compliant where possible
- Use zsh-specific features only when necessary
- Work with zsh versions 5.7.1, 5.8.1, and 5.9
