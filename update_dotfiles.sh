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
    if [[ "$file" != ".gitconfig" && "$file" != "init.lua" && "$file" != "vscode-settings.json" && "$file" != "solarized.vim" ]]; then
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

function setup_vscode_settings() {
  [[ "$OSTYPE" == darwin* ]] || return 0

  __profile_log_info "updating VS Code settings..."
  local user_dir="$HOME/Library/Application Support/Code/User"

  if [[ ! -d "$user_dir" ]]; then
    mkdir -p "$user_dir"
  fi

  ln -sf "$dotfiles_dir/vscode-settings.json" "$user_dir/settings.json"
}

function setup_vim_colors() {
  __profile_log_info "updating vim colorscheme..."
  local colors_dir="$HOME/.vim/colors"

  if [[ ! -d "$colors_dir" ]]; then
    mkdir -p "$colors_dir"
  fi

  ln -sf "$dotfiles_dir/colors/solarized.vim" "$colors_dir/solarized.vim"
}

link_dotfiles
setup_neovim
setup_vim_colors
setup_vscode_settings
__profile_log_success "done!"
