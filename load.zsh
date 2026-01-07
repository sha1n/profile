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
source $SHA1N_PROFILE_HOME/zsh-plugins/zsh-history-substring-search/zsh-history-substring-search.zsh
source $SHA1N_PROFILE_HOME/zsh-plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
# theme
source $SHA1N_PROFILE_HOME/zsh-theme/agnoster-zsh-theme/agnoster.zsh-theme

source $SHA1N_PROFILE_HOME/include/exports
source $SHA1N_PROFILE_HOME/include/aliases
source $SHA1N_PROFILE_HOME/include/functions
source $SHA1N_PROFILE_HOME/include/keybindings
source $SHA1N_PROFILE_HOME/include/completions
source $SHA1N_PROFILE_HOME/include/history
source $SHA1N_PROFILE_HOME/include/prompt

source $SHA1N_PROFILE_HOME/zsh-plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
