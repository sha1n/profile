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
   - Sources all `include/` files: exports, mise, aliases, functions, keybindings, completions, history, prompt
   - **`include/mise` runs synchronously right after `include/exports`** — runtime `PATH` must be correct at the first prompt, so never defer it
   - **fzf shell integration loads at the end of `include/keybindings`**, before `fzf-tab` — `fzf-tab` must be the last plugin to bind `^I`
   - **`include/prompt` runs synchronously after `include/history`** so the first prompt is Starship's; it is skipped when `starship` is not on `PATH` or `TERM` is `dumb`. Starship's `PROMPT` is a `$(…)` expansion, so `setopt prompt_subst` in `load.zsh` is required
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
- **`agents/`** — Global Agent instructions (`AGENTS.md`). `install.sh` symlinks agent configuration files (e.g. `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`) to this file. If a target already exists, the script prompts `[n/Y]` before replacing it (default Yes, also at end of input); an existing correct link is left untouched. `agents/claude/` holds the Claude Code status line renderer and a wrapper that also forwards the payload to Orca's status line script; the `claude` function in `include/functions` injects the wrapper with `--settings`
- **`brew/`** — One plain Brewfile per machine profile: the tiers in `brew/tiers/<N>-<name>.Brewfile` (`1-essentials`, `2-dev`, `3-dev.home`) and the add-ons in `brew/addons/<name>.Brewfile` (`audio`). Each file holds entries only (entry lines such as `tap`, `brew`, `cask` or `uv`, and comments; no other Ruby) and ends with a line break. A file that installs from `sha1n/tap` has its own `tap "sha1n/tap", trusted: true` line, so any selection of files taps it. The tiers form one chain in the numeric order of `<N>`: applying `dev` also applies `essentials`, and applying `dev.home` also applies `dev` and `essentials`. An add-on applies only itself. `scripts/profile` joins the selected files into one temporary file and passes it to `brew bundle` with `--file`. The shell exports no `HOMEBREW_BUNDLE_FILE`, and no variable selects profiles, so a plain `brew bundle` does not read this repo. No language runtimes here — mise owns them
- **`config/`** — Config files with nested targets (`install.sh` links dotfiles by basename only, so they cannot live in `dotfiles/`). `config/mise/profile.toml` holds the runtime versions and mise settings; `install.sh` links it to `~/.config/mise/conf.d/profile.toml` (not `config.toml`, which `mise use -g` writes to). `config/starship.toml` is the Starship prompt config; `include/exports` points `STARSHIP_CONFIG` at it, so it needs no link; its `custom.disk` module runs `disk_free`, so it needs `scripts/` on `PATH`. `config/nvim/` is the nvim config (`init.lua` and the committed `lazy-lock.json`); `install.sh` links the directory as a whole to `~/.config/nvim`, so lazy.nvim writes the lockfile into the repo, and moves an old-layout `~/.config/nvim` (a directory whose `init.lua` links into the repo) to `~/.config/nvim.bak.<epoch seconds>` first
- **`bootstrap.sh`** — One-command new-Mac setup (`curl … | zsh -s -- [profile...]`): Homebrew, clone, `install.sh`, then `scripts/profile install`. At the repo root, not in `scripts/`, so it is not a command on `PATH`. Add no install logic here; it belongs in `scripts/profile` or `install.sh`
- **`zsh-plugins/`** — Git submodules
- **`tests/`** — Test suite using `zsh-scriptest` submodule

## Commands

```bash
./install.sh              # Full setup: submodules, symlinks, dirs, .zshrc, .zprofile (macOS), ~/.config/nvim link, mise link, zwc compilation
                          # Runs every step; exits 1 and names the failed steps if any step failed (an existing target is a skip, not a failure)
profile update            # Pull the current branch, update submodules, remove submodules no longer in .gitmodules (keeps any with local work)
profile install [profile...]    # brew bundle for the given tier and the ones before it in the chain, plus each given add-on alone (default: essentials), then, only when the tiers reach dev, :ProfileSync in headless nvim and mise install
profile cleanup           # List the formulae, casks and taps no profile lists and unused mise versions, ask [y/N], then remove
profile list [--names]    # Print the tiers in chain order, then the add-ons, each under a brew-style "==> " headline (colored on a terminal unless NO_COLOR is set); --names prints only the names, one per line; runs nothing
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
  4. `tier_files_of <brew_dir>` — prints the tier files of `<brew_dir>/tiers`, in chain order, so no test keeps its own list of profiles
  5. `addon_files_of <brew_dir>` — prints the add-on files of `<brew_dir>/addons`, in name order
  6. `profile_name_of <file>` — prints the profile name of a tier or add-on file
- A file that installs before its cases calls `setup` first, then its install (see `tests/sanity.test.sh`).
- Tests that run `install.sh` in a child shell also source `tests/install_helpers.zsh`: `run_install [<extra_path>]`, `run_install_with_rc`, `errors_naming`, and `write_failing_stub <dir> <command> <pattern>`. To inject a failure, prefer a stub or a regular file where a directory must go: both also work as root, which ignores directory modes.
- Available matchers from `matchers.sh`: `assert_contains`, `assert_not_empty`, `assert_file_exists`, `assert_dir_exists`, etc.
- Use `test_case_title` / `test_setup_title` / `test_teardown_title` for structured output.
- Test functions are called sequentially at the bottom of the file (not auto-discovered).
- Test files must be executable — the runner silently skips a non-executable file.
- Call `cleanup` before `finish_tests`: `finish_tests` exits on failure, and a skipped cleanup leaves the fingerprint behind for the next file.
- Run child shells with `env -i HOME="$HOME" PATH=… TERM=dumb` so variables exported by the developer's own shell cannot mask what `load.zsh` exports. Only a test of `include/prompt` sets another `TERM`, because the prompt is skipped on a dumb terminal.
- See `tests/sanity.test.sh` for the canonical pattern.

CI runs on **ubuntu-latest** and **macos-latest** (GitHub Actions, `.github/workflows/ci.yml`).

## Implementation Conventions

### Shell Functions
- **Logging**: `__profile_log_{error,warn,info,success}` from `scripts/lib.zsh`; start each step of a setup script with `__profile_log_section <title>` (bold, blue background). `error` and `warn` write to stderr, the others to stdout; never add `>&2` at a call site
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
- Two kinds of profiles:
  - Tiers, in one chain: `essentials` < `dev` < `dev.home`. Applying a tier also applies every tier before it in the chain.
  - Add-ons, outside the chain: `audio`. An add-on applies only itself, so an add-on alone installs no `essentials`.
- Profiles are arguments only; no file stores a selection.
- `essentials` has core CLI tools, `parallel`, the JetBrains Mono Nerd Font, stock Neovim, Sublime Text, Git and gh. `dev` adds mise, uv, build tools, agent CLI tools and the Neovim toolchain. `dev.home` adds Docker Desktop, LLVM, GoReleaser, Warp, VS Code, Orca, `git-lfs`, `git-filter-repo` and `gnupg`. `audio` has BlackHole 2ch. Brave, Claude, Codex, cmux, Slack and Zoom are installed by hand.
- The file names under `brew/tiers` and `brew/addons` are the only list of profiles; a tier and an add-on never share a name. `scripts/profile` resolves names to files in `__profile_cmd_brewfiles` (no tier file is an error; a missing `brew/addons` means no add-ons); tests read the files with `tier_files_of`, `addon_files_of` and `profile_name_of` from `tests/sandbox.zsh`. To add a tier, add `brew/tiers/<N>-<name>.Brewfile`, where `<N>` sets its place in the chain. To add an add-on, add `brew/addons/<name>.Brewfile`. Then update `test_profile_chain` and the package lists of `test_package_lists` in `tests/brewfile.test.sh`.
- `scripts/profile` is the only sequence that installs or removes tools: `install` runs `brew bundle`, then, when the given tiers reach `dev` (add-ons never count), `:ProfileSync` in a headless nvim (with `--cmd 'lua vim.g.profile_sync = true'` before init.lua loads; restores the plugins to `config/nvim/lazy-lock.json` and installs the treesitter parsers) followed by `mise install`; `cleanup` always compares against every tier and every add-on and asks one question per tool before it removes. Its Homebrew section covers formulae, casks and taps only, drops every candidate that a profile lists (by name, full name, old names and aliases from `brew info --json=v2`, and keeps a candidate whose names it cannot read), and removes the rest itself with `brew uninstall` and `brew untap`, never with `brew bundle cleanup --force`. Each `brew uninstall` runs with `HOMEBREW_NO_AUTOREMOVE=1`, because autoremove can drop a profile formula that was installed as a dependency, and the formula one runs with `--force`, so every installed version goes. Removal must never use a subset of the profiles. Keep all its logic in functions with one call on the last line: `profile update` can rewrite the file while it runs.
- To set up a machine, or to change its profiles, obey the "Set up with an agent" section of `README.md`.
- Profile membership changes affect future installs only. `profile cleanup` compares against all profiles, so it keeps a package moved to a higher tier even on a lower-tier machine. For repositories using Git LFS, configure filters locally with `git lfs install --local` after inspecting `core.hooksPath` and `pre-push` hooks; changing the linked global Git config takes effect immediately. See the Git LFS section of `README.md`.

### Neovim Policy
Language servers and formatters for nvim come from `brew/tiers/2-dev.Brewfile`; no Mason. The `neovim` binary is `essentials` (the vim alias needs it), but the toolchain (`tree-sitter-cli`, `lua-language-server`, `stylua`, and the other language servers) is `dev`, so every tier from `dev` on gets it. `essentials` machines run stock nvim: a gate at the top of `config/nvim/init.lua` returns early when `vim.g.profile_sync` is unset and lazy.nvim is not installed — the provisioned lazy.nvim install is the signal, since no file stores a profile selection. `config/nvim/init.lua` enables each server whose binary is on `PATH`. Update plugins with `:Lazy update`, then commit `config/nvim/lazy-lock.json`.

### Python Policy
No global Python libraries: `PIP_REQUIRE_VIRTUALENV=true` is exported, Python comes from mise, and Python CLI tools install as uv tools (`uv "<tool>"` in a profile Brewfile, or `uv tool install <tool>` by hand; `uv tool` replaces `pipx`). The `uv` formula starts at `dev`. Add no `python@*`, `pipx` or Homebrew Python library formulae.

### Scripts as CLI Commands
Files in `scripts/` are on `$PATH` and act as standalone commands. Notable: `y` and `n` (yarn/npm wrappers), `docker_cleanup`, `git_config_hook`, `zsh_bench` (startup benchmarking), `disk_free` (prints the free space of `/`; the Starship `custom.disk` module and the Claude status line call it), `profile` (`update` the repo, `install` or `cleanup` the tools of the machine profiles). New scripts placed here are automatically available as commands.

### Performance
- **Startup time**: Optimized via `compinit` caching, `.zwc` bytecode compilation, and `zsh-defer` plugin deferral. Use `zsh_bench` to measure impact of changes.
- **compinit caching** (`include/completions`): The `.zcompdump` file is only regenerated when stale (>24h) or missing. `compinit -C` is used otherwise.
- **`_profile` completion** (`include/completions`): completes the `profile` subcommands, and after `install` the names from `profile list --names`. It runs `profile` only at completion time, never at startup.
- **`.zwc` bytecode**: Zsh auto-prefers `file.zwc` over `file` when sourcing (if `.zwc` is newer). Stale `.zwc` files are harmless — zsh falls back to the source. `reload!` and `install.sh` recompile automatically. Some files (aliases, exports, functions) fail `zcompile` silently — this is expected.
- **`zsh-defer`**: Only used in interactive sessions. Keybindings that depend on deferred plugins must also be deferred — see `load.zsh` for the pattern.

### Cross-Platform
Changes must work on both macOS and Linux. Use platform checks (`$OSTYPE`) when behavior differs (see `__profile_git_file_timestamp` for an example).
The one exception is `bootstrap.sh`, which is macOS only and exits on other platforms. The Brewfile tests that evaluate the files with `brew bundle list` skip when `brew` is not on `PATH`; the file layout and line checks run everywhere.
