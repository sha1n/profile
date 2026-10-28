[![CI](https://github.com/sha1n/profile/actions/workflows/ci.yml/badge.svg)](https://github.com/sha1n/profile/actions/workflows/ci.yml)

- [Profile](#profile)
- [What's in the Box?](#whats-in-the-box)
- [Installation](#installation)
- [New Mac](#new-mac)
- [Update](#update)
- [Why not Oh-My-Zsh, Zim or Something else?](#why-not-oh-my-zsh-zim-or-something-else)
- [Can I Use This Repository to Configure My Own Zsh?](#can-i-use-this-repository-to-configure-my-own-zsh)
- [Does it Work with Bash and Other Shells Too?](#does-it-work-with-bash-and-other-shells-too)

# Profile
This repository is used to manage and maintain *my personal* Zsh configuration preferences easily and across multiple environment. 
It is not designed to be generic and open, but it is mostly very simple and can be used as a reference for those who prefer to configure their own 
shell environment.

# What's in the Box?
- common directory structures
- common environment variables
- aliases and shell functions
- utility scripts (added to `PATH`)
- Homebrew packages per machine profile (see: [brew/tiers](brew/tiers) and [brew/addons](brew/addons))
- language runtime versions for mise (see: [config/mise/profile.toml](config/mise/profile.toml))
- global instructions for coding agents (see: [agents/AGENTS.md](agents/AGENTS.md))
- zsh plugins (see: [zsh-plugins](zsh-plugins))
- essential key bindings
- zsh completion configuration

# Installation

```bash
git clone git@github.com:sha1n/profile.git

profile/install.sh
```

The installation script runs these steps, each under a section title:
1. Updates the git submodules.
2. Links each file in the `dotfiles` directory into your home directory. This takes care of `.vimrc`, `.gitconfig` and others.
   - If a file with the same name already exists, skips it
3. Creates `~/.local/bin` and `~/code/w`.
4. On macOS, adds `brew shellenv` to `~/.zprofile`, when Homebrew is installed and the line is not there yet.
5. Adds `source '<repo>/load.zsh'` to `~/.zshrc`.
   - If the file doesn't exist, it creates it
   - If `~/.zshrc` already sources a `load.zsh`, skips it
6. Links `agents/AGENTS.md` to `~/.agents/AGENTS.md`, `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md`.
   - If a target already exists, asks `[n/Y]` before it replaces it. Default is Yes
7. Links the `config/nvim` directory to `~/.config/nvim`.
   - If `~/.config/nvim` is a directory of the old layout, whose `init.lua` links into this repository, moves it to `~/.config/nvim.bak.<epoch seconds>` first
   - If anything else is at `~/.config/nvim`, prints a warning and skips it
8. Links `config/mise/profile.toml` to `~/.config/mise/conf.d/profile.toml`.
9. Compiles the zsh files to `.zwc` bytecode.

The script runs every step, even after one fails. An existing target is a skip, not a failure. At the end it exits with 1 and names the failed steps, or with 0.

The script installs no tools. Use `profile install` for that (see [Update](#update)) or the bootstrap below.

# New Mac
One command sets up a new Mac. It installs Homebrew, clones this repository to `~/code/profile`, runs `install.sh`, and runs `profile install` with the profiles that you name (default: `essentials`). It is macOS only and exits on other platforms. It can ask for your `sudo` password for the Homebrew installer. You can run it again: it skips an installed Homebrew and an existing clone.

```bash
curl -fsSL https://raw.githubusercontent.com/sha1n/profile/master/bootstrap.sh | zsh -s -- dev
```

| Profile | Contents |
|---|---|
| `essentials` | Core CLI tools, GNU `parallel`, the JetBrains Mono Nerd Font, stock Neovim, Sublime Text, Git and gh |
| `dev` | mise and its Go, Python, Node.js, Java and Maven runtimes, uv, build tools, agent CLI tools and the Neovim toolchain. Includes `essentials` |
| `dev.home` | Docker Desktop, LLVM, GoReleaser, Warp, VS Code, Orca, and Git maintenance and signing tools (`git-lfs`, `git-filter-repo`, `gnupg`). Includes `dev` |
| `audio` | BlackHole 2ch and AU Lab. An add-on |

There are two kinds of profiles. The tiers form one chain: `essentials` < `dev` < `dev.home`. Each tier includes every tier before it. An add-on such as `audio` stands outside the chain: it applies only itself, so `audio` alone installs no `essentials`. Name it next to a tier to get both, for example `dev audio`. Brave, Claude, Codex, cmux, Slack and Zoom are not in any profile: install them by hand on the machines that need them.

mise owns the language runtimes. Their versions are in [config/mise/profile.toml](config/mise/profile.toml), which `install.sh` links to `~/.config/mise/conf.d/profile.toml`. Homebrew installs no runtime. The `uv` formula starts at `dev`; Python CLI tools install as uv tools (`uv "<tool>"` in a profile Brewfile, or `uv tool install <tool>`), not with `pipx` or a Homebrew formula. The shell exports `PIP_REQUIRE_VIRTUALENV=true`, so `pip install` works only inside a virtualenv.

Each profile is one plain Brewfile: a tier is `brew/tiers/<N>-<name>.Brewfile`, and an add-on is `brew/addons/<name>.Brewfile`. A tier file holds only its own packages; `profile install` joins the files of the tiers before it. A plain `brew bundle` does not read this repo. To check one profile file, pass it with `--file`, for example `brew bundle check --file ~/code/profile/brew/tiers/2-dev.Brewfile`.

After the bootstrap, do these steps by hand: `gh auth login`, create an SSH key and add it with `gh ssh-key add`, and turn on VS Code Settings Sync. The bootstrap prints them at the end.

## Set up with an agent
To let a coding agent set up a machine, tell it: *"Set up this machine with the profile at https://github.com/sha1n/profile. Follow the 'Set up with an agent' section of its README."*

Agent, do these steps in order. Each step ends only when its check passes.

1. **Ask for the profiles.** Show the user the profile table above, and ask which profile applies. Check: the user confirmed one tier, `essentials`, `dev` or `dev.home` (each includes the tiers before it in the chain), and any add-ons, such as `audio`.
2. **Apply them.**
   - If `~/code/profile` does not exist, give the user the bootstrap command with the profiles. The user runs it in a terminal, because it can ask for the `sudo` password. Wait until the user says it is done, and read its output.
   - If it exists, run `profile update`, then `profile install <profiles>`. When `profile` is not on `PATH` yet, run `~/code/profile/scripts/profile` instead.

   Check: each command exits with 0.
3. **Verify.** For each file of the chosen profiles, run `brew bundle check --no-upgrade --file <file>`: every tier file under `~/code/profile/brew/tiers` up to the chosen tier, and the file of each add-on under `~/code/profile/brew/addons`. If `dev` or `dev.home` applies, in a new login shell, `mise ls` shows the runtimes, and `command -v` of `node`, `python3`, `go` and `java` shows a mise path. Check: all these checks pass, or you told the user which check failed.
4. **Hand over the manual steps** above. They need a browser or a password, so the user does them. Check: the user has the list.

# Update
The `profile` command updates this repository and installs the tools of the machine profiles. Run it from any directory.

```bash
profile update                   # pull the current branch, update the submodules, remove the ones the repo no longer lists
profile install                  # install the Homebrew packages of essentials
profile install dev              # install the packages of dev and essentials, sync the nvim plugins, then the mise runtimes
profile install dev.home         # install the packages of dev.home, dev and essentials, sync the nvim plugins, then the mise runtimes
profile install dev audio        # install the packages of dev and essentials and of the audio add-on, sync the nvim plugins, then the mise runtimes
profile install audio            # install the packages of the audio add-on only
profile cleanup                  # list what no profile needs, ask, then remove it
profile list                     # print the profiles: tiers in chain order, then add-ons
profile list --names             # print only the profile names, one per line
```

`profile list` prints the profiles from the file names under `brew/`, a section per kind:

```text
Tiers (each one includes the ones above it):
  essentials
  dev
  dev.home

Add-ons (each one installs only itself):
  audio
```

`profile list --names` prints the same names, one per line, without headers. `profile install <TAB>` completes the profile names from `profile list --names`.

`profile update` removes a submodule that the repo no longer lists: its working tree, its directory under `.git/modules/`, and its section in `.git/config`. It asks no question. It keeps the submodule and prints a warning if the submodule has uncommitted changes, untracked files, a stash, or commits that no remote-tracking ref contains.

`profile install` stores no selection: each run applies only the profiles that you name. A tier always includes the tiers before it in the chain; an add-on includes nothing else. After `brew bundle`, a run whose tiers reach `dev` runs `:ProfileSync` in a headless nvim and then `mise install`; `essentials` and an add-on alone stop after `brew bundle`. It never removes packages.

Changes to profile membership govern future `profile install` runs. Packages already installed stay in place. `profile cleanup` compares against every profile, so moving a package to a higher tier does not cause cleanup to remove it from a machine using a lower tier.

`profile cleanup` has a Homebrew section and a mise section. Each section lists what it would remove, asks its own `[y/N]` question, and removes that list only if you answer `y`. You can remove one list and keep the other.
- The Homebrew section lists the formulae, casks and taps that no profile lists and asks, for example, `Remove these 6 Homebrew packages? [y/N]`. It always compares against every profile, so it never removes a package of a profile. Before it asks, it checks each candidate against the entries of every profile, also by its old names and aliases, and prints a warning such as `kept docker: a profile lists it` for each candidate that it drops from the list. If it cannot read the names of a candidate, it keeps that candidate too. On `y` it removes the list itself with `brew uninstall` and `brew untap`. It removes every installed version of a formula, and it turns Homebrew autoremove off, so a dependency that a profile lists stays. A dependency that no profile lists shows up in the next cleanup. It never touches uv tools, VS Code extensions or the other `brew bundle` extension types. The list also shows packages that you installed by hand and never added to a profile Brewfile, for example Slack or Zoom from Homebrew, so read it before you answer.
- The mise section lists the runtime versions that no config uses, one `tool@version` per line, from `mise ls --prunable --json`. This needs `jq`, which is in `essentials`. Then it asks before it runs `mise prune`. If mise cannot list the versions, for example because of a config error, `profile cleanup` asks nothing and exits with 1.

`profile` exits with 0 on success, 1 when a step failed, and 2 on a usage error. `profile update` does not run `install.sh`. Run `install.sh` again after an update that adds a link.

Both `profile install` and `profile cleanup` skip their Homebrew section when `brew` is not on `PATH`, and their mise section when `mise` is not on `PATH`. `profile install` skips the nvim plugin sync when `nvim` is not on `PATH`.

## Git LFS in a repository

Homebrew installs the `git-lfs` executable with the `dev.home` profile. Git LFS filters are configured per repository. In each repository that tracks files with LFS, inspect its `core.hooksPath` and existing `pre-push` hook, then run `git lfs install --local` from that repository and verify the local filters with `git config --local --get-regexp '^filter\.lfs\.'`. Integrate the LFS pre-push hook with any custom hook setup. Existing repositories with local LFS filters continue to work.

The linked `~/.gitconfig` changes as soon as [dotfiles/.gitconfig](dotfiles/.gitconfig) changes. Its former global LFS filter settings are gone even when `git-lfs` remains installed. Migrate any repository that relied on those settings before updating the linked configuration.

## Neovim
The nvim config is [config/nvim](config/nvim), which `install.sh` links as a directory to `~/.config/nvim`. The plugin versions are pinned in the committed [config/nvim/lazy-lock.json](config/nvim/lazy-lock.json).

The full setup — plugins, LSP, treesitter, options — is for machines with the `dev` tier or a tier after it. `essentials` keeps the `neovim` binary (the `vim` alias maps to it) but runs it stock: the config returns early when lazy.nvim was never provisioned. No file stores a profile selection; the provisioned lazy.nvim install is the signal.

`profile install dev` (and every tier after it, such as `dev.home`) runs `:ProfileSync` in a headless nvim. It restores the plugins to the versions of the lockfile, removes the plugins that the config does not list, and installs the treesitter parsers. It exits with non-zero on failure, also when the loaded nvim config does not define `:ProfileSync`, and `profile install` then fails.

The `dev` Brewfile owns the language servers and formatters: `gopls`, `basedpyright`, `typescript`, `lua-language-server` and `stylua`, plus `tree-sitter-cli` for the parsers. `typescript` is TypeScript 7, and nvim uses its native LSP (`tsc --lsp`). The config enables each server whose binary is on `PATH`. There is no Mason.

To update the plugins, run `:Lazy update` in nvim, test the result, and commit `config/nvim/lazy-lock.json`.

# Why not Oh-My-Zsh, Zim or Something else?
I've been using Oh-My-Zsh happily for many years and I could continue using it forever. I created this repository for several reasons.
1. I realized that Oh-My-Zsh is basically a bunch of scripts that glue things together
2. I realized that Oh-My-Zsh sometimes makes configuration decisions that are either not necessary or not to my liking
3. Given 1 & 2, I realized that I can easily build something that does what I need and even takes me a step further, so that I don't have to make any manual adjustments after I install it
4. Finally, I use this a lot to configure dev VM boxes, so it saves me a lot of time

With all that said, I still love, appreciate and recommend [Oh-My-Zsh](https://ohmyz.sh/) to most people. I haven't tried [Zim](https://zimfw.sh/) yet, but it definitely looks good. So if you are not into fiddling with that kind of configuration be sure to check them out if you haven't done so yet.

# Can I Use This Repository to Configure My Own Zsh?
You can, but you probably want to make some adjustments to make it your own.
I would recommend to fork the repo and review the configuration, although it is very easy to make adjustments evern after installing, because it's all very very simple and magic free.

Pay extra attention to:
- [dotfiles/.gitconfig](dotfiles/.gitconfig)
- [dotfiles/.gitignore_global](dotfiles/.gitignore_global)
- [include/aliases](include/aliases)

# Does it Work with Bash and Other Shells Too?
No, it is designed to work only with Zsh. Tested extensively on macOS with `zsh` versions:
- 5.7.1
- 5.8.1
- 5.9

The shell configuration also works on Linux. CI runs the test suite (`make test`) on `ubuntu-latest` and `macos-latest`. `bootstrap.sh` is the one macOS-only part.


