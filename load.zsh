#!/usr/bin/env zsh

SHA1N_PROFILE_HOME="${${(%):-%x}:a:h}"

setopt prompt_subst
autoload -U colors && colors

# export locale vars
export LANG="en_US.UTF-8"
export LC_CTYPE="en_US.UTF-8"

# plugins
fpath=($SHA1N_PROFILE_HOME/zsh-plugins/zsh-completions/src $fpath)
source $SHA1N_PROFILE_HOME/zsh-plugins/path-ethic/path-ethic.plugin.zsh

# zsh-defer for deferring non-critical interactive plugins
if [[ -o interactive ]]; then
  source $SHA1N_PROFILE_HOME/zsh-plugins/zsh-defer/zsh-defer.plugin.zsh
  zsh-defer source $SHA1N_PROFILE_HOME/zsh-plugins/zsh-history-substring-search/zsh-history-substring-search.zsh
  zsh-defer source $SHA1N_PROFILE_HOME/zsh-plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
else
  source $SHA1N_PROFILE_HOME/zsh-plugins/zsh-history-substring-search/zsh-history-substring-search.zsh
  source $SHA1N_PROFILE_HOME/zsh-plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
fi

# NVM_DIR is exported in include/exports but nothing sources nvm itself; envy
# used to append this to ~/.zshrc, which is this repo's file. nvm.sh is slow and
# only needed interactively, so it follows the deferred-plugin pattern above.
# Path is derived, not shelled out for: `brew --prefix nvm` forks brew on every
# shell start, before the prompt, and is not deferrable the way the sourcing is.
__profile_nvm_sh="${HOMEBREW_PREFIX:-/opt/homebrew}/opt/nvm/nvm.sh"
[[ -s "$__profile_nvm_sh" ]] || __profile_nvm_sh="/usr/local/opt/nvm/nvm.sh"
if [[ -s "$__profile_nvm_sh" ]]; then
  if [[ -o interactive ]]; then
    zsh-defer source "$__profile_nvm_sh"
  else
    source "$__profile_nvm_sh"
  fi
fi
unset __profile_nvm_sh

# theme
source $SHA1N_PROFILE_HOME/zsh-theme/agnoster-zsh-theme/agnoster.zsh-theme

source $SHA1N_PROFILE_HOME/include/exports
source $SHA1N_PROFILE_HOME/include/aliases
source $SHA1N_PROFILE_HOME/include/functions
source $SHA1N_PROFILE_HOME/include/keybindings
source $SHA1N_PROFILE_HOME/include/completions
source $SHA1N_PROFILE_HOME/include/history
source $SHA1N_PROFILE_HOME/include/prompt

# fzf-tab: after compinit (include/completions), before zsh-syntax-highlighting
if [[ -o interactive ]]; then
  zsh-defer source $SHA1N_PROFILE_HOME/zsh-plugins/fzf-tab/fzf-tab.plugin.zsh
else
  source $SHA1N_PROFILE_HOME/zsh-plugins/fzf-tab/fzf-tab.plugin.zsh
fi

# deferred keybindings that depend on history-substring-search
if [[ -o interactive ]]; then
  zsh-defer bindkey "^[[A" history-substring-search-up
  zsh-defer bindkey "^[[B" history-substring-search-down
fi

# zsh-syntax-highlighting MUST be loaded LAST
if [[ -o interactive ]]; then
  zsh-defer source $SHA1N_PROFILE_HOME/zsh-plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
else
  source $SHA1N_PROFILE_HOME/zsh-plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi
