#!/usr/bin/env zsh

SHA1N_PROFILE_HOME="${${(%):-%x}:a:h}"

source "$SHA1N_PROFILE_HOME/lib.zsh"

local dotfiles_dir="$SHA1N_PROFILE_HOME/dotfiles"


function link_dotfile() {
  __profile_log_info "linking $1..."
  ln -sf "$dotfiles_dir/$1" "$HOME/$1"
  return "$?"
}

function link_dotfiles() {
  __profile_log_info "linking dot files..."
  for file in $(find "$dotfiles_dir" -type f | awk -F/ '{print $NF}'); do
    if [[ "$file" != ".gitconfig" ]]; then
      link_dotfile "$file" && __profile_log_success "ok!" || error "failed!"
    fi
  done
}

link_dotfiles
__profile_log_success "done!"
