[![CI](https://github.com/sha1n/profile/actions/workflows/ci.yml/badge.svg)](https://github.com/sha1n/profile/actions/workflows/ci.yml)

- [Profile](#profile)
- [What's in the Box?](#whats-in-the-box)
- [Installation](#installation)
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
- zsh plugins (see: [zsh-plugins](zsh-plugins))
- essential key bindings
- zsh theme (see: [zsh-theme](zsh-theme))
- zsh completion configuration

# Installation

```bash
git clone https://github.com/sha1n/profile.git
git -C profile submodule update --init

profile/install.sh
```

```bash
./install.sh                          # Dotfiles + shell config; on macOS also the essentials layer
./install.sh --profile dev-go         # Add a provisioning layer (repeatable, comma form accepted)
./install.sh --check                  # Report drift, mutate nothing. Exit 0 = clean
./install.sh --compose --profile dev-go  # Print the effective Brewfile to stdout
./install.sh --yes                    # Non-interactive
./install.sh --no-provision           # Skip the Homebrew step
./install.sh --help                   # Usage
```

The installation script does two things:
1. Creates links for each file in the `dotfiles` directory in the user's home directory. This takes care of `.vimrc` , `.gitconfig` and others.
   - If a dot file with the same name already exists, skips
2. `source` the `load.zsh` file from `~/.zshrc`. 
   - If the file doesn't exist, it creates it
   - If `~/.zshrc` exists and a file named `load.zsh` is already sourced from it, aborts


## Provisioning (macOS only)

`install.sh` applies Homebrew Bundle layers from `provision/`. The `essentials`
layer is always applied; `--profile` adds toolchain layers.

### Checking for drift

    ./install.sh --check --profile dev-go

Exit code 0 means everything declared is installed. `--check` passes
`--no-upgrade`, so *outdated* packages do not count as drift — add `--upgrades`
if you want version drift reported too.

### Removing undeclared packages

There is no `--cleanup` flag, deliberately. Run it by hand against a **temp file**,
never a pipe — `brew bundle cleanup` reads the Brewfile from stdin, so the
confirmation prompt cannot be shown and it exits 1:

    ./install.sh --compose --profile dev-go > /tmp/Brewfile
    brew bundle cleanup --file=/tmp/Brewfile          # prompts, then applies if confirmed
    brew bundle cleanup --force --file=/tmp/Brewfile  # applies with no prompt

> **Warning:** `--force` also **resets the Homebrew trust store** to exactly the
> taps the composed file declares, revoking trust for any tap it omits.

### Testing limitation

The real test of provisioning is a fresh Mac, and macOS VMs are out of scope. The
sandboxed-`$HOME` test harness covers dotfile linking, idempotency and manifest
resolution — it does **not** cover first-run Homebrew installation.

# Update
Since all external plugins are sourced as git submodules, updating everything that's included in this setup is as simple as pulling the repository recursively. To make this even easier, an alias named `update_profile` is registered to take care of that with a single command.
```bash
update_profile
```

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


