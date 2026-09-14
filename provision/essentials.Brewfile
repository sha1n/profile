# Always applied. Language-agnostic AND dependency-light (D10), plus everything
# the shell config in include/ needs in order to function.

# Declared here rather than beside their formulae: `brew bundle cleanup --force`
# resets the trust store to the composed file's taps, and essentials is the only
# layer present in every composition.
tap "sha1n/tap"
tap "dapr/tap"
tap "sqldef/sqldef"

brew "coreutils"
brew "wget"
brew "watch"
# Load-bearing: only present today as an `ansible` dependency. Declare before
# uninstalling ansible or `brew autoremove` will take it.
brew "tree"
brew "jq"
brew "bat"
brew "ripgrep"
brew "gnu-time"
brew "parallel"
brew "tmux"
# dotfiles/init.lua:72-75 builds telescope-fzf-native with build = 'make'.
brew "make"
brew "git"
# dotfiles/.gitconfig declares a [filter "lfs"] block.
brew "git-lfs"
# scripts/github_email_privacy_migrator.sh shells out to it.
brew "git-filter-repo"
brew "gh"
brew "glab"
brew "fzf"
brew "neovim"
brew "python@3.12"
# Backs ~/.local/bin/aws, it2 and santacloud.
brew "pipx"
brew "go-task"
# macOS ships openrsync (protocol 29); include/aliases' `backup` uses
# --delete-during --force -P.
brew "rsync"
brew "sha1n/tap/hako"
brew "sha1n/tap/bert"

cask "warp"
cask "iterm2"
cask "sublime-text"
# agnoster needs only the branch glyph and init.lua sets icons_enabled = false,
# so one Powerline font is sufficient.
cask "font-menlo-for-powerline"
cask "visual-studio-code"
cask "obsidian"
cask "sha1n/tap/acdc-mcp"
