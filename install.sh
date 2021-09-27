#!/usr/bin/env zsh

SHA1N_PROFILE_HOME="${${(%):-%x}:a:h}"
source "$SHA1N_PROFILE_HOME/scripts/lib.zsh"

local dotzshrc="$HOME/.zshrc"
local dotfiles_dir="$SHA1N_PROFILE_HOME/dotfiles"

function validate() {
  __profile_log_info "Observing $dotzshrc..."
  # We are not going to create .zshrc. If it doesn't exist something is probably off
  if [[ ! -f "$dotzshrc" ]]; then
   __profile_log_warn "the file '$dotzshrc' does not exist. An empty one will be created."
    touch "$dotzshrc"
  fi

  local existing_source=$(grep -e '^source .*/\.include' "$dotzshrc")
  if [[ ! -z "$existing_source" ]]; then
    __profile_log_error "the following 'source' command is already in your .zshrc profile: $existing_source"
    return 1
  fi
}

function install() {
  __profile_log_info "installing profile..."
  echo "source '$SHA1N_PROFILE_HOME/.include'" >>"$dotzshrc"
  if [[ "$?" == "0" ]]; then
    __profile_log_info "installed successfully!"
    __profile_log_info "to verify installation start new session or source $dotzshrc"
  fi
}

function link_dotfile() {
  __profile_log_info "linking $1..."
  if [[ -f "$HOME/$1" ]]; then
    __profile_log_warn "the file '${HOME}/${1}' already exists. Skipping..."
  else
    ln -s "$dotfiles_dir/$1" "$HOME/$1"
    return "$?"
  fi

}

function link_dotfiles() {
  __profile_log_info "linking dot files..."
  for file in $(find "$dotfiles_dir" -type f | awk -F/ '{print $NF}'); do
    link_dotfile "$file" && __profile_log_success "done!" || __profile_log_warn "skipped!"
  done
}

function update_submodules() {
  __profile_log_info "updating submodules..."
  
  git submodule update --recursive --remote
  return "$?"
}


update_submodules && __profile_log_success "submodules updated successfully" || __profile_log_warn "failed to update submodules!"
link_dotfiles
validate && install && __profile_log_success "done!" || __profile_log_warn "skipped!"
