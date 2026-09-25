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
- zsh plugins (see: [zsh-plugins](zsh-plugins))
- essential key bindings
- zsh theme (see: [zsh-theme](zsh-theme))
- zsh completion configuration

# Installation

```bash
git clone git@github.com:sha1n/profile.git
git -C profile submodule update --init

profile/install.sh
```

The installation script does two things:
1. Creates links for each file in the `dotfiles` directory in the user's home directory. This takes care of `.vimrc` , `.gitconfig` and others.
   - If a dot file with the same name already exists, skips
2. `source` the `load.zsh` file from `~/.zshrc`. 
   - If the file doesn't exist, it creates it
   - If `~/.zshrc` exists and a file named `load.zsh` is already sourced from it, aborts

Each step of the installation script starts with a section title. If a target file already exists, the script asks before it replaces it.

# New Mac
One command sets up a new Mac. It installs Homebrew, clones this repository to `~/code/profile`, runs `install.sh`, and installs the tools of the profiles that you name.

```bash
curl -fsSL https://raw.githubusercontent.com/sha1n/profile/master/bootstrap.sh | zsh -s -- dev
```

| Profile | Contents |
|---|---|
| `essentials` | CLI core, editors, git tools, terminal, personal apps, and `uv` for Python CLI tools |
| `dev` | Development tools and apps, and mise with the Go, Python, Node.js, Java and Maven runtimes. Includes `essentials` |

After the bootstrap, do these steps by hand: `gh auth login`, create an SSH key and add it with `gh ssh-key add`, and turn on VS Code Settings Sync. The bootstrap prints them at the end.

## Set up with an agent
To let a coding agent set up a machine, tell it: *"Set up this machine with the profile at https://github.com/sha1n/profile. Follow the 'Set up with an agent' section of its README."*

Agent, do these steps in order. Each step ends only when its check passes.

1. **Ask for the profiles.** Show the user the profile table above, and ask which profiles apply. Check: the user confirmed `essentials` or `dev` (`dev` includes `essentials`).
2. **Apply them.**
   - If `~/code/profile` does not exist, give the user the bootstrap command with the profiles. The user runs it in a terminal, because it can ask for the `sudo` password. Wait until the user says it is done, and read its output.
   - If it exists, run `profile update`, then `profile install <profiles>`.

   Check: each command exits with 0.
3. **Verify.** Run `HOMEBREW_PROFILE_INSTALL_PROFILES="<profiles>" brew bundle check --no-upgrade --file ~/code/profile/brew/Brewfile`. If `dev` applies, in a new login shell, `mise ls` shows the runtimes, and `command -v` of `node`, `python3`, `go` and `java` shows a mise path. Check: all these checks pass, or you told the user which check failed.
4. **Hand over the manual steps** above. They need a browser or a password, so the user does them. Check: the user has the list.

# Update
The `profile` command updates this repository and installs the tools of the machine profiles. Run it from any directory.

```bash
profile update                   # pull the current branch and update the submodules
profile install                  # install the Homebrew packages of essentials
profile install dev              # install the packages of dev and essentials, then the mise runtimes
profile cleanup                  # list what no profile needs, ask, then remove it
```

`profile install` stores no selection: each run applies only the profiles that you name. `dev` always includes `essentials`. It never removes packages.

`profile cleanup` has a Homebrew section and a mise section. Each section lists what it would remove: the Homebrew packages that no profile lists, and the mise versions that no config uses. Then it asks its own question, such as `Remove these 6 Homebrew packages? [y/N]`, and it removes that list only if you answer `y`. You can remove one list and keep the other. It always compares against every profile, so it never offers to remove the packages of a profile. The list also shows packages that you installed by hand and never added to the Brewfile, so read it before you answer. A plain `brew bundle` command with no `HOMEBREW_PROFILE_INSTALL_PROFILES` also applies every profile.

`profile update` does not run `install.sh`. Run `install.sh` again after an update that adds a link.

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


