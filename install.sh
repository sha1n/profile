#!/usr/bin/env zsh

SHA1N_PROFILE_HOME="${${(%):-%x}:a:h}"
source "$SHA1N_PROFILE_HOME/scripts/lib.zsh"
source "$SHA1N_PROFILE_HOME/include/exports"

dotzshrc="$HOME/.zshrc"
agent_global_configs=("$HOME/.claude/CLAUDE.md" "$HOME/.codex/AGENTS.md" "$HOME/.gemini/GEMINI.md")
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

function install_agents_global() {
  __profile_log_info "linking global Agent instructions..."
  local agents_md="$SHA1N_PROFILE_HOME/agents/AGENTS.md"

  for target in "${agent_global_configs[@]}"; do
    create_directory "${target:h}"

    # Already linked to the profile — nothing to do.
    if [[ -L "$target" && "$(readlink "$target")" == "$agents_md" ]]; then
      __profile_log_warn "'$target' is already linked to the profile. Skipping..."
      continue
    fi

    # Existing file or link: replacing it is destructive, so ask first (default: Yes).
    if [[ -e "$target" || -L "$target" ]]; then
      local reply
      read "reply?'$target' already exists. Replace it with a link to the profile's AGENTS.md? [n/Y] "
      if [[ "$reply" == [nN] ]]; then
        __profile_log_info "keeping existing '$target'"
        continue
      fi
      rm -f "$target"
    fi

    __profile_log_info "linking AGENTS.md to $target..."
    ln -s "$agents_md" "$target"
  done
  return 0
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

install_agents_global

setup_neovim

__profile_log_info "compiling zsh files to bytecode..."
for f in "$SHA1N_PROFILE_HOME"/load.zsh "$SHA1N_PROFILE_HOME"/include/*(.) "$SHA1N_PROFILE_HOME"/scripts/lib.zsh; do
  [[ "$f" == *.zwc ]] && continue
  zcompile "$f" 2>/dev/null
done
__profile_log_success "bytecode compilation complete"

__profile_log_info "done!"
