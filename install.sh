#!/usr/bin/env zsh

SHA1N_PROFILE_HOME="${${(%):-%x}:a:h}"
source "$SHA1N_PROFILE_HOME/scripts/lib.zsh"
source "$SHA1N_PROFILE_HOME/include/exports"

dotzshrc="$HOME/.zshrc"
dotfiles_dir="$SHA1N_PROFILE_HOME/dotfiles"
dirs=("$HOME/.local/bin" "$CODE/w")

function validate_shell_rc_file() {
  __profile_log_info "Observing $dotzshrc..."
  # We are not going to create .zshrc. If it doesn't exist something is probably off
  if [[ ! -f "$dotzshrc" ]]; then
   __profile_log_warn "the file '$dotzshrc' does not exist. An empty one will be created."
    touch "$dotzshrc"
  fi

  local existing_source=$(grep -e '^source .*/\load.zsh' "$dotzshrc")
  if [[ ! -z "$existing_source" ]]; then
    __profile_log_warn "the following 'source' command is already in your .zshrc profile: $existing_source"
    return 1
  fi
}

function install_source_command() {
  __profile_log_info "installing profile..."
  echo "source '$SHA1N_PROFILE_HOME/load.zsh'" >>"$dotzshrc"
  if [[ "$?" == "0" ]]; then
    __profile_log_info "installed successfully!"
    __profile_log_info "to verify installation start new session or source $dotzshrc"
  fi
}

function link_dotfile() {
  if [[ -f "$HOME/$1" ]]; then
    __profile_log_warn "the file '${HOME}/${1}' already exists. Skipping..."
  else
    __profile_log_info "linking $1..."
    ln -s "$dotfiles_dir/$1" "$HOME/$1"
    return "$?"
  fi
}

function link_dotfiles() {
  __profile_log_info "linking dot files..."
  
  for file in $(find "$dotfiles_dir" -type f | awk -F/ '{print $NF}'); do
    if [[ "$file" == "init.lua" ]]; then
      continue
    fi
    link_dotfile "$file" || __pe_log_error "failed to link '$file'!"
  done
}

function setup_neovim() {
  __profile_log_info "setting up neovim..."
  local nvim_config_dir="$HOME/.config/nvim"
  
  create_directory "$nvim_config_dir" || __pe_log_error "failed to create '$nvim_config_dir'!"

  if [[ -f "$nvim_config_dir/init.lua" ]]; then
       __profile_log_warn "the file '$nvim_config_dir/init.lua' already exists. Skipping..."
  else
       __profile_log_info "linking init.lua..."
       ln -s "$dotfiles_dir/init.lua" "$nvim_config_dir/init.lua"
  fi
}

function create_directory() {
  if [[ -d "$1" ]]; then
    __profile_log_warn "the directory '$1' already exists. Skipping..."
  else
    __profile_log_info "creating directory $1..."
    mkdir -p "$1"
    return "$?"
  fi
}

function create_directories() {
  __profile_log_info "creating directories..."

  for dir in "${dirs[@]}"; do 
    create_directory "$dir" || __pe_log_error "failed to create '$dir'!"
  done
}

function update_submodules() {
  __profile_log_info "updating submodules..."
  
  git submodule update --init
  return "$?"
}


update_submodules && __profile_log_success "submodules updated successfully" || __profile_log_warn "failed to update submodules!"

link_dotfiles

create_directories 

validate_shell_rc_file && install_source_command 

setup_neovim

__profile_log_info "done!"
