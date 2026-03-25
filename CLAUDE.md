# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

Personal Zsh configuration repository: shell environment, dotfiles, aliases, functions, and utility scripts. Designed to bootstrap a consistent dev environment on new machines via `./install.sh`.

## Key Architecture

### Loading Chain
1. `~/.zshrc` sources `load.zsh` (added by `install.sh`)
2. `load.zsh` orchestrates everything:
   - Locale, zsh options, plugins (git submodules), theme
   - Sources all `include/` files: exports, aliases, functions, keybindings, completions, history, prompt
   - **`zsh-syntax-highlighting` MUST be loaded LAST** (after all other plugins and keybindings)
   - **`fpath` must include `zsh-completions/src` BEFORE `autoload`**

### Key Directories
- **`include/`** — Modular shell config files sourced by `load.zsh`
- **`scripts/`** — Executable tools, added to `$PATH` via `include/exports`. Any file here is a CLI command.
  - `lib.zsh` — Shared library (logging, tree search) sourced by functions and install script
- **`dotfiles/`** — Symlinked to `$HOME` during install (not copied — changes are live)
- **`zsh-plugins/`, `zsh-theme/`** — Git submodules
- **`tests/`** — Test suite using `zsh-scriptest` submodule

## Commands

```bash
./install.sh              # Full setup: submodules, symlinks, dirs, .zshrc, neovim
make test                 # Run tests (also: ./tests/run_tests.sh)
make update_submodules    # Update all git submodules
reload!                   # Alias to re-source ~/.zshrc (use after editing include/ files)
```

To run a single test file directly: `zsh tests/my_test.test.sh` (but prefer `make test` — the runner sets up the sandbox environment via `zsh-scriptest`).

## Writing Tests

Tests use the `zsh-scriptest` framework (submodule in `tests/`). Test files must be named `*.test.sh` and placed in `tests/`.

- Tests run in a **sandboxed `$HOME`** (temporary empty dir). Each test file must:
  1. Verify `$HOME` is empty at start (guard against running outside sandbox)
  2. Write a fingerprint file to `$HOME` and assert it exists in cleanup (proves sandbox isolation)
  3. `rm -rf "$HOME"` in cleanup
- Available matchers from `matchers.sh`: `assert_contains`, `assert_not_empty`, `assert_file_exists`, `assert_dir_exists`, etc.
- Use `test_case_title` / `test_setup_title` / `test_teardown_title` for structured output.
- Test functions are called sequentially at the bottom of the file (not auto-discovered).
- See `tests/sanity.test.sh` for the canonical pattern.

CI runs on **ubuntu-latest** and **macos-latest** (GitHub Actions, `.github/workflows/ci.yml`).

## Implementation Conventions

### Shell Functions
- **Logging**: `__profile_log_{error,warn,info,success}` from `scripts/lib.zsh`
- **Tree search**: `__profile_search_ancestor_tree <filename>` walks up from `$PWD` to `/` looking for a file
- **Private functions**: Prefix with `__profile_` to indicate internal use
- **Public functions** in `include/functions` are user-facing shell commands (e.g., `start`, `jest`, `alias_last`)

### The `start()` Pattern
The `start` function searches ancestor directories for a `.start` file and sources it. This is a convention for project-specific environment setup.

### Aliases
When modifying `include/aliases`:
- Group by category (comment headers indicate sections)
- Git aliases evaluate current branch dynamically: `$(git branch --show-current)`
- `alias_last <name>` creates an alias from the last command and appends it to the aliases file

### Environment Variables
- `$SHA1N_PROFILE_HOME` — This repo's directory path (set in `load.zsh`, used everywhere)
- `$CODE` — `$HOME/code` (defined in `include/exports`)
- Other env vars: `include/exports`

### Scripts as CLI Commands
Files in `scripts/` are on `$PATH` and act as standalone commands. Notable: `y` and `n` (yarn/npm wrappers), `docker_cleanup`, `git_config_hook`. New scripts placed here are automatically available as commands.

### Cross-Platform
Changes must work on both macOS and Linux. Use platform checks (`$OSTYPE`) when behavior differs (see `__profile_git_file_timestamp` for an example).
