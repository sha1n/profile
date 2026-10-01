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
  for file in "$dotfiles_dir"/**/*(.DN:t); do
    if [[ "$file" != ".gitconfig" ]]; then
      link_dotfile "$file" && __profile_log_success "ok!" || __profile_log_error "failed to link '$file'!"
    fi
  done
}

function setup_neovim() {
  __profile_log_info "updating neovim config..."
  local src="$SHA1N_PROFILE_HOME/config/nvim"
  local nvim_config_dir="$HOME/.config/nvim"

  if [[ -L "$nvim_config_dir" && "$(readlink "$nvim_config_dir")" == "$src" ]]; then
    return 0
  fi

  if [[ -d "$nvim_config_dir" && ! -L "$nvim_config_dir" ]]; then
    __profile_log_warn "'$nvim_config_dir' is a directory, not a link to the profile. Run install.sh to migrate it. Skipping..."
    return 0
  fi

  # A regular file or a link to a foreign config is user-owned; only install.sh may replace targets.
  if [[ -e "$nvim_config_dir" || -L "$nvim_config_dir" ]]; then
    __profile_log_warn "'$nvim_config_dir' exists and is not linked to the profile. Skipping..."
    return 0
  fi

  mkdir -p "${nvim_config_dir:h}" || { __profile_log_error "failed to create '${nvim_config_dir:h}'!"; return 1; }
  __profile_log_info "linking the nvim config directory..."
  ln -s "$src" "$nvim_config_dir"
}

link_dotfiles
setup_neovim
__profile_log_success "done!"
