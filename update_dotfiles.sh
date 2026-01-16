#!/usr/bin/env zsh

SHA1N_PROFILE_HOME="${${(%):-%x}:a:h}"
source "$SHA1N_PROFILE_HOME/scripts/lib.zsh"

local dotfiles_dir="$SHA1N_PROFILE_HOME/dotfiles"


function link_dotfile() {
  __profile_log_info "linking $1..."
  ln -sf "$dotfiles_dir/$1" "$HOME/$1"
  return "$?"
}

function link_dotfiles() {
  __profile_log_info "linking dot files..."
  for file in $(find "$dotfiles_dir" -type f | awk -F/ '{print $NF}'); do
    if [[ "$file" != ".gitconfig" && "$file" != "init.lua" ]]; then
      link_dotfile "$file" && __profile_log_success "ok!" || error "failed!"
    fi
  done
}

function setup_neovim() {
  __profile_log_info "updating neovim config..."
  local nvim_config_dir="$HOME/.config/nvim"
  
  if [[ ! -d "$nvim_config_dir" ]]; then
     mkdir -p "$nvim_config_dir"
  fi

  __profile_log_info "linking init.lua..."
  ln -sf "$dotfiles_dir/init.lua" "$nvim_config_dir/init.lua"
}

link_dotfiles
setup_neovim
__profile_log_success "done!"
