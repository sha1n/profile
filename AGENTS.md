# AGENTS.md

This file provides guidance to AI coding agents (Claude Code, Codex, Gemini, etc.) when working with code in this repository.

`CLAUDE.md` at the repo root is a symlink to this file — edit `AGENTS.md`, never replace the symlink.

## Repository Overview

Personal Zsh configuration repository: shell environment, dotfiles, aliases, functions, and utility scripts. Designed to bootstrap a consistent dev environment on new machines via `./install.sh`.

## Key Architecture

### Loading Chain
1. `~/.zshrc` sources `load.zsh` (added by `install.sh`)
2. `load.zsh` orchestrates everything:
   - Locale, zsh options, `path-ethic` plugin (synchronous — needed at startup)
   - Sources all `include/` files: exports, mise, aliases, functions, keybindings, completions, history
   - **`include/mise` runs synchronously right after `include/exports`** — runtime `PATH` must be correct at the first prompt, so never defer it
   - **fzf shell integration loads at the end of `include/keybindings`**, before `fzf-tab` — `fzf-tab` must be the last plugin to bind `^I`
   - **Deferred plugins** (via `zsh-defer`, interactive sessions only): `zsh-history-substring-search`, `zsh-autosuggestions`, `fzf-tab`, `zsh-syntax-highlighting` — these load after the prompt appears
   - **Non-interactive fallback**: deferred plugins load synchronously when `[[ ! -o interactive ]]` (e.g., tests)
   - **`zsh-syntax-highlighting` MUST be loaded LAST** (after all other plugins and keybindings, even when deferred)
   - **`fpath` must include `zsh-completions/src` BEFORE `autoload`**
   - **`fzf-tab` must load AFTER `compinit`** (`include/completions`) and before `zsh-syntax-highlighting`
   - **History-substring-search keybindings** are deferred in `load.zsh` (not in `include/keybindings`) because they depend on the deferred plugin

### Key Directories
- **`include/`** — Modular shell config files sourced by `load.zsh`
- **`scripts/`** — Executable tools, added to `$PATH` via `include/exports`. Any file here is a CLI command.
  - `lib.zsh` — Shared library (logging, tree search) sourced by functions and install script
- **`dotfiles/`** — Symlinked to `$HOME` during install (not copied — changes are live). The repo has no `.gitignore` of its own — ignore rules go in `dotfiles/.gitignore_global`
- **`agents/`** — Global Agent instructions (`AGENTS.md`). `install.sh` symlinks agent configuration files (e.g. `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`) to this file. If a target already exists, the script prompts `[n/Y]` before replacing it (default Yes, also at end of input); an existing correct link is left untouched
- **`brew/Brewfile`** — The only Brewfile: every Homebrew package of the three machine profiles (`essentials`, `dev`, `workstation`), one line each, each inside its `if profiles.include?("<name>")` block. The profiles come from `HOMEBREW_PROFILE_INSTALL_PROFILES` (unset or empty means every profile, so that a plain `brew bundle cleanup` never treats a profile's packages as unlisted; `profile install` always sets it; the profiles form one chain in the order of `known`, so applying `dev` also applies `essentials`, and applying `workstation` also applies `dev` and `essentials`); the `HOMEBREW_` prefix is required because the `brew` wrapper passes no other variables to the Brewfile. `include/exports` exports `HOMEBREW_BUNDLE_FILE` with this file's path, so a plain `brew bundle` reads it from any directory; `scripts/profile` still passes `--file` on every `brew bundle` call, so it does not depend on the shell environment. Keep the file to Ruby logic that Homebrew documents for Brewfiles (no processes, no loading of other files). No language runtimes here — mise owns them
- **`config/`** — Config files with nested targets (`install.sh` links dotfiles by basename only, so they cannot live in `dotfiles/`). `config/mise/profile.toml` holds the runtime versions and mise settings; `install.sh` links it to `~/.config/mise/conf.d/profile.toml` (not `config.toml`, which `mise use -g` writes to)
- **`bootstrap.sh`** — One-command new-Mac setup (`curl … | zsh -s -- [essentials|dev|workstation]`): Homebrew, clone, `install.sh`, then `scripts/profile install`. At the repo root, not in `scripts/`, so it is not a command on `PATH`. Add no install logic here; it belongs in `scripts/profile` or `install.sh`
- **`zsh-plugins/`** — Git submodules
- **`tests/`** — Test suite using `zsh-scriptest` submodule

## Commands

```bash
./install.sh              # Full setup: submodules, symlinks, dirs, .zshrc, .zprofile (macOS), neovim, mise link, zwc compilation
                          # Runs every step; exits 1 and names the failed steps if any step failed (an existing target is a skip, not a failure)
profile update            # Pull the current branch, update submodules, remove submodules no longer in .gitmodules (keeps any with local work)
profile install [essentials|dev|workstation]    # brew bundle for the given profile and the ones before it in the chain (default: essentials), then mise install for dev and workstation
profile cleanup           # List the formulae, casks and taps no profile lists and unused mise versions, ask [y/N], then remove
make test                 # Run tests (also: ./tests/run_tests.sh)
make update_submodules    # Update all git submodules
make compile              # Compile zsh files to .zwc bytecode
make clean_zwc            # Remove all .zwc bytecode files
reload!                   # Alias: recompiles .zwc files, then re-sources ~/.zshrc
zsh_bench                 # Benchmark shell startup time (see scripts/zsh_bench)
zsh_bench -n 20 -o        # 20 iterations, save results to .benchmarks/
```

To run a single test file directly: `zsh tests/my_test.test.sh` (but prefer `make test` — the runner sets up the sandbox environment via `zsh-scriptest`).

## Writing Tests

Tests use the `zsh-scriptest` framework (submodule in `tests/`). Test files must be named `*.test.sh` and placed in `tests/`.

- Tests run in a **sandboxed `$HOME`** (temporary empty dir). Each test file sources `tests/sandbox.zsh` first, never a copy of its functions. It gives `profile_home`, the matchers, and:
  1. `setup` — exits if `$HOME` is not empty (guard against running outside sandbox), then writes a fingerprint file to `$HOME`
  2. `cleanup` — asserts the fingerprint exists (proves sandbox isolation), then empties `$HOME`
  3. `reset_home` — removes all but the fingerprint, so each case starts clean
  4. `known_profiles_of <brewfile>` — prints the names of the Brewfile `known` line, so no test keeps its own list of profiles
- A file that installs before its cases calls `setup` first, then its install (see `tests/sanity.test.sh`).
- Tests that run `install.sh` in a child shell also source `tests/install_helpers.zsh`: `run_install [<extra_path>]`, `run_install_with_rc`, `errors_naming`, and `write_failing_stub <dir> <command> <pattern>`. To inject a failure, prefer a stub or a regular file where a directory must go: both also work as root, which ignores directory modes.
- Available matchers from `matchers.sh`: `assert_contains`, `assert_not_empty`, `assert_file_exists`, `assert_dir_exists`, etc.
- Use `test_case_title` / `test_setup_title` / `test_teardown_title` for structured output.
- Test functions are called sequentially at the bottom of the file (not auto-discovered).
- Test files must be executable — the runner silently skips a non-executable file.
- Call `cleanup` before `finish_tests`: `finish_tests` exits on failure, and a skipped cleanup leaves the fingerprint behind for the next file.
- Run child shells with `env -i HOME="$HOME" PATH=… TERM=dumb` so variables exported by the developer's own shell cannot mask what `load.zsh` exports.
- See `tests/sanity.test.sh` for the canonical pattern.

CI runs on **ubuntu-latest** and **macos-latest** (GitHub Actions, `.github/workflows/ci.yml`).

## Implementation Conventions

### Shell Functions
- **Logging**: `__profile_log_{error,warn,info,success}` from `scripts/lib.zsh`; start each step of a setup script with `__profile_log_section <title>` (bold, blue background)
- **Tree search**: `__profile_search_ancestor_tree <filename>` walks up from `$PWD` to `/` looking for a file
- **Private functions**: Prefix with `__profile_` to indicate internal use
- **Public functions** in `include/functions` are user-facing shell commands (e.g., `start`, `jest`, `alias_last`, `wt`)
- **Worktrees**: `wt <branch>` / `wt_rm <branch>` create and remove worktrees under `<repo-root>/.worktree/<branch>`

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

### Machine Profiles
- Three profiles in one chain: `essentials` < `dev` < `workstation`. Applying a profile also applies every profile before it in the chain. They are arguments only; no file stores a selection.
- The `known` line of `brew/Brewfile` (`known = %w[...]`) is the only list of profiles, and its order is the chain. `scripts/profile` reads it from the Brewfile (`__profile_cmd_known_profiles`); tests read it with `known_profiles_of` from `tests/sandbox.zsh`. To add a profile, change `known`, add its Brewfile block, and update `test_profile_chain` in `tests/brewfile.test.sh`.
- `scripts/profile` is the only sequence that installs or removes tools: `install` runs `brew bundle`, then `mise install` for `dev` and every profile after it in the chain; `cleanup` always compares against every profile and asks one question per tool before it removes. Its Homebrew section covers formulae, casks and taps only, drops every candidate that a profile lists (by name, full name, old names and aliases from `brew info --json=v2`, and keeps a candidate whose names it cannot read), and removes the rest itself with `brew uninstall` and `brew untap`, never with `brew bundle cleanup --force`. Each `brew uninstall` runs with `HOMEBREW_NO_AUTOREMOVE=1`, because autoremove can drop a profile formula that was installed as a dependency, and the formula one runs with `--force`, so every installed version goes. Removal must never use a subset of the profiles. Keep all its logic in functions with one call on the last line: `profile update` can rewrite the file while it runs.
- To set up a machine, or to change its profiles, obey the "Set up with an agent" section of `README.md`.

### Python Policy
No global Python libraries: `PIP_REQUIRE_VIRTUALENV=true` is exported, Python comes from mise, and Python CLI tools install as uv tools (`uv "<tool>"` in the Brewfile, or `uv tool install <tool>` by hand; `uv tool` replaces `pipx`). The `uv` formula is in `essentials`, which `dev` includes. Add no `python@*`, `pipx` or Homebrew Python library formulae.

### Scripts as CLI Commands
Files in `scripts/` are on `$PATH` and act as standalone commands. Notable: `y` and `n` (yarn/npm wrappers), `docker_cleanup`, `git_config_hook`, `zsh_bench` (startup benchmarking), `profile` (`update` the repo, `install` or `cleanup` the tools of the machine profiles). New scripts placed here are automatically available as commands.

### Performance
- **Startup time**: Optimized via `compinit` caching, `.zwc` bytecode compilation, and `zsh-defer` plugin deferral. Use `zsh_bench` to measure impact of changes.
- **compinit caching** (`include/completions`): The `.zcompdump` file is only regenerated when stale (>24h) or missing. `compinit -C` is used otherwise.
- **`.zwc` bytecode**: Zsh auto-prefers `file.zwc` over `file` when sourcing (if `.zwc` is newer). Stale `.zwc` files are harmless — zsh falls back to the source. `reload!` and `install.sh` recompile automatically. Some files (aliases, exports, functions) fail `zcompile` silently — this is expected.
- **`zsh-defer`**: Only used in interactive sessions. Keybindings that depend on deferred plugins must also be deferred — see `load.zsh` for the pattern.

### Cross-Platform
Changes must work on both macOS and Linux. Use platform checks (`$OSTYPE`) when behavior differs (see `__profile_git_file_timestamp` for an example).
The one exception is `bootstrap.sh`, which is macOS only and exits on other platforms. `brew/` tests skip when `brew` is not on `PATH`.
