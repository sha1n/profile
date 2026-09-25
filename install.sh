#!/usr/bin/env zsh

SHA1N_PROFILE_HOME="${${(%):-%x}:a:h}"
source "$SHA1N_PROFILE_HOME/scripts/lib.zsh"
source "$SHA1N_PROFILE_HOME/include/exports"

__profile_install_dotzshrc="$HOME/.zshrc"
__profile_install_dotzprofile="$HOME/.zprofile"
__profile_install_agent_global_configs=("$HOME/.agents/AGENTS.md" "$HOME/.claude/CLAUDE.md" "$HOME/.codex/AGENTS.md")
__profile_install_dotfiles_dir="$SHA1N_PROFILE_HOME/dotfiles"
__profile_install_dirs=("$HOME/.local/bin" "$CODE/w")

# Each step function returns 0 when done or skipped and 1 when it failed; a failed step logs its own error.

# Appends a line to a file, creating the file when missing. Logs an error naming the file on failure.
function __profile_install_append_line() {
  local file="$1" line="$2"
  if [[ ! -e "$file" ]] && ! touch "$file"; then
    __profile_log_error "failed to create '$file'!"
    return 1
  fi
  # The group silences the shell's own redirection error; the error below names the file instead.
  if ! { print -r -- "$line" >>"$file" } 2>/dev/null; then
    __profile_log_error "failed to write '$file'!"
    return 1
  fi
}

function __profile_install_shell_rc() {
  __profile_log_info "Observing $__profile_install_dotzshrc..."
  local existing_source
  if [[ -f "$__profile_install_dotzshrc" ]] && existing_source="$(grep -e '^source .*/\load.zsh' "$__profile_install_dotzshrc")"; then
    __profile_log_warn "the following 'source' command is already in your .zshrc profile: $existing_source"
    return 0
  fi
  if [[ ! -e "$__profile_install_dotzshrc" ]]; then
    __profile_log_warn "the file '$__profile_install_dotzshrc' does not exist. An empty one will be created."
  fi

  __profile_log_info "installing profile..."
  __profile_install_append_line "$__profile_install_dotzshrc" "source '$SHA1N_PROFILE_HOME/load.zsh'" || return 1
  __profile_log_info "installed successfully!"
  __profile_log_info "to verify installation start new session or source $__profile_install_dotzshrc"
}

function __profile_install_agents_global() {
  local agents_md="$SHA1N_PROFILE_HOME/agents/AGENTS.md"
  local target failed=0

  for target in "${__profile_install_agent_global_configs[@]}"; do
    if ! __profile_install_create_directory "${target:h}"; then
      failed=1
      continue
    fi

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
      if ! rm -f "$target"; then
        __profile_log_error "failed to remove '$target'!"
        failed=1
        continue
      fi
    fi

    __profile_log_info "linking AGENTS.md to $target..."
    if ! ln -s "$agents_md" "$target"; then
      __profile_log_error "failed to link '$target'!"
      failed=1
    fi
  done
  return "$failed"
}

# Links $2 to $1, skipping any existing target. Logs an error naming the target on failure.
function __profile_install_link_file() {
  local src="$1" dst="$2"
  if [[ -e "$dst" || -L "$dst" ]]; then
    __profile_log_warn "the file '$dst' already exists. Skipping..."
    return 0
  fi
  __profile_log_info "linking ${dst:t}..."
  if ! ln -s "$src" "$dst"; then
    __profile_log_error "failed to link '$dst'!"
    return 1
  fi
}

function __profile_install_link_dotfiles() {
  local file failed=0

  for file in "$__profile_install_dotfiles_dir"/**/*(.DN:t); do
    if [[ "$file" == "init.lua" ]]; then
      continue
    fi
    __profile_install_link_file "$__profile_install_dotfiles_dir/$file" "$HOME/$file" || failed=1
  done
  return "$failed"
}

function __profile_install_setup_neovim() {
  local nvim_config_dir="$HOME/.config/nvim"

  __profile_install_create_directory "$nvim_config_dir" || return 1
  __profile_install_link_file "$__profile_install_dotfiles_dir/init.lua" "$nvim_config_dir/init.lua"
}

function __profile_install_link_mise_config() {
  # conf.d, not config.toml: `mise use -g` writes to config.toml, and a write through the link would change the repo.
  local src="$SHA1N_PROFILE_HOME/config/mise/profile.toml"
  local dst_dir="$HOME/.config/mise/conf.d"
  local dst="$dst_dir/profile.toml"

  __profile_install_create_directory "$dst_dir" || return 1

  if [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]]; then
    return 0
  fi
  if [[ -e "$dst" || -L "$dst" ]]; then
    __profile_log_warn "the file '$dst' already exists and is not linked to the profile. Skipping..."
    return 0
  fi
  __profile_log_info "linking profile.toml..."
  if ! ln -s "$src" "$dst"; then
    __profile_log_error "failed to link '$dst'!"
    return 1
  fi
}

# Creates a directory, skipping an existing one. Logs an error naming the directory on failure.
function __profile_install_create_directory() {
  if [[ -d "$1" ]]; then
    __profile_log_warn "the directory '$1' already exists. Skipping..."
    return 0
  fi
  __profile_log_info "creating directory $1..."
  if ! mkdir -p "$1"; then
    __profile_log_error "failed to create '$1'!"
    return 1
  fi
}

function __profile_install_create_directories() {
  local dir failed=0

  for dir in "${__profile_install_dirs[@]}"; do
    __profile_install_create_directory "$dir" || failed=1
  done
  return "$failed"
}

function __profile_install_brew_shellenv() {
  if [[ "$OSTYPE" != darwin* ]]; then
    __profile_log_warn "brew shellenv is macOS only. Skipping..."
    return 0
  fi

  local brew_prefix
  if [[ -x "/opt/homebrew/bin/brew" ]]; then
    brew_prefix="/opt/homebrew"
  elif (( $+commands[brew] )); then
    brew_prefix="$(brew --prefix)"
  else
    __profile_log_warn "Homebrew was not found. Skipping brew shellenv..."
    return 0
  fi

  if [[ -f "$__profile_install_dotzprofile" ]] && grep -q 'brew shellenv' "$__profile_install_dotzprofile"; then
    __profile_log_warn "a 'brew shellenv' line is already in $__profile_install_dotzprofile. Skipping..."
    return 0
  fi

  __profile_install_append_line "$__profile_install_dotzprofile" "eval \"\$(${brew_prefix}/bin/brew shellenv)\"" || return 1
  __profile_log_success "added brew shellenv to $__profile_install_dotzprofile"
}

function __profile_install_update_submodules() {
  if ! git -C "$SHA1N_PROFILE_HOME" submodule update --init; then
    __profile_log_error "failed to update submodules!"
    return 1
  fi
  __profile_log_success "submodules updated successfully"
}

function __profile_install_compile_bytecode() {
  local f
  for f in "$SHA1N_PROFILE_HOME"/load.zsh "$SHA1N_PROFILE_HOME"/include/*(.) "$SHA1N_PROFILE_HOME"/scripts/lib.zsh; do
    [[ "$f" == *.zwc ]] && continue
    # Some files cannot be compiled by design, so a failure here never fails the install.
    zcompile "$f" 2>/dev/null
  done
  __profile_log_success "bytecode compilation complete"
}

# Usage: __profile_install_run_step <title> <function> — prints the section title and records the title when the step fails.
function __profile_install_run_step() {
  local title="$1" step="$2"
  __profile_log_section "$title"
  "$step" || __profile_install_failed_steps+=("$title")
}

__profile_install_failed_steps=()

__profile_install_run_step "Submodules" __profile_install_update_submodules
__profile_install_run_step "Dotfiles" __profile_install_link_dotfiles
__profile_install_run_step "Directories" __profile_install_create_directories
__profile_install_run_step "Homebrew shellenv (~/.zprofile)" __profile_install_brew_shellenv
__profile_install_run_step "Shell rc (~/.zshrc)" __profile_install_shell_rc
__profile_install_run_step "Agent instructions" __profile_install_agents_global
__profile_install_run_step "Neovim" __profile_install_setup_neovim
__profile_install_run_step "mise config" __profile_install_link_mise_config
__profile_install_run_step "Bytecode" __profile_install_compile_bytecode

__profile_log_info "done!"

# A top-level return ends an executed script with this status and, unlike exit, leaves a sourcing shell running.
if (( ${#__profile_install_failed_steps} )); then
  __profile_log_error "failed steps: ${(j:, :)__profile_install_failed_steps}"
  return 1
fi
return 0
