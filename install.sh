#!/usr/bin/env zsh

SHA1N_PROFILE_HOME="${${(%):-%x}:a:h}"
source "$SHA1N_PROFILE_HOME/scripts/lib.zsh"
source "$SHA1N_PROFILE_HOME/include/exports"

# zsh_eval_context is (toplevel) when executed and (toplevel file) when sourced.
# set -e in a sourced file would leak into the caller and abort the test harness.
if [[ "${#zsh_eval_context}" -eq 1 ]]; then
  set -euo pipefail
fi

dotzshrc="$HOME/.zshrc"
agent_global_configs=("$HOME/.agents/AGENTS.md" "$HOME/.claude/CLAUDE.md" "$HOME/.codex/AGENTS.md")
dotfiles_dir="$SHA1N_PROFILE_HOME/dotfiles"
dirs=("$HOME/.local/bin" "$CODE/w")

: "${PROFILE_ASSUME_YES:=}"
: "${PROFILE_NO_PROVISION:=}"
PROFILE_CHECK_ONLY=""
PROFILE_COMPOSE_ONLY=""
PROFILE_CHECK_UPGRADES=""
typeset -ga PROFILE_LAYERS=()

function usage() {
  cat <<'USAGE'
Usage: ./install.sh [options]

  --profile NAME     Add a provisioning layer (repeatable; comma-separated accepted).
                     Darwin only.
  --check            Report drift without mutating anything.
                     Exit 0 = satisfied, non-zero = drift.
  --upgrades         With --check, count outdated packages as drift.
  --compose          Print the effective Brewfile to stdout. Darwin only.
  --yes              Non-interactive; assume Yes for prompts.
                     Equivalent to PROFILE_ASSUME_YES=1.
  --no-provision     Skip the Homebrew step.
                     Equivalent to PROFILE_NO_PROVISION=1.
  --help             Show this message.
USAGE
}

function parse_args() {
  while (( $# > 0 )); do
    case "$1" in
      --profile)
        [[ -n "${2:-}" ]] || { print -u2 "--profile requires a value"; return 2; }
        PROFILE_LAYERS+=("${(@s:,:)2}")
        shift 2
        ;;
      --profile=*)
        PROFILE_LAYERS+=("${(@s:,:)1#--profile=}")
        shift
        ;;
      --check)        PROFILE_CHECK_ONLY=1; shift ;;
      --upgrades)     PROFILE_CHECK_UPGRADES=1; shift ;;
      --compose)      PROFILE_COMPOSE_ONLY=1; shift ;;
      --yes)          PROFILE_ASSUME_YES=1; shift ;;
      --no-provision) PROFILE_NO_PROVISION=1; shift ;;
      --help)         usage; return 10 ;;
      *)              print -u2 "unknown option: $1"; usage >&2; return 2 ;;
    esac
  done
  return 0
}

function run_step() {
  local label="$1"; shift
  if ! "$@"; then
    __profile_log_error "step failed: ${label}"
    __profile_log_error "re-run to resume: ./install.sh ${PROFILE_ARGV_ECHO}"
    return 1
  fi
}

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
  __profile_log_info "installed successfully!"
  __profile_log_info "to verify installation start new session or source $dotzshrc"
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
      local reply=""
      if [[ -z "$PROFILE_ASSUME_YES" ]]; then
        read "reply?'$target' already exists. Replace it with a link to the profile's AGENTS.md? [n/Y] "
      fi
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
    if [[ "$file" == "init.lua" || "$file" == "vscode-settings.json" ]]; then
      continue
    fi
    link_dotfile "$file" || __profile_log_error "failed to link '$file'!"
  done
}

function setup_neovim() {
  __profile_log_info "setting up neovim..."
  local nvim_config_dir="$HOME/.config/nvim"
  local target="$nvim_config_dir/init.lua"
  local source="$dotfiles_dir/init.lua"

  create_directory "$nvim_config_dir" || __profile_log_error "failed to create '$nvim_config_dir'!"

  if [[ "$(readlink "$target" 2>/dev/null)" == "$source" ]]; then
    __profile_log_warn "'$target' is already linked to the profile. Skipping..."
    return 0
  fi

  # A symlink pointing elsewhere is another installer's artifact (historically
  # ~/code/kickstart.nvim) and is safe to reclaim. A regular file is the user's
  # own and is never touched.
  if [[ -L "$target" ]]; then
    __profile_log_info "relinking init.lua (was: $(readlink "$target"))..."
    ln -sfn "$source" "$target"
    return "$?"
  fi

  if [[ -e "$target" ]]; then
    __profile_log_warn "'$target' is a regular file, not a link. Leaving it alone."
    __profile_log_warn "to adopt the profile's config: rm '$target' && ./install.sh"
    return 0
  fi

  __profile_log_info "linking init.lua..."
  ln -s "$source" "$target"
  return "$?"
}

function setup_vscode_settings() {
  profile_is_darwin || return 0

  __profile_log_info "setting up VS Code settings..."
  local user_dir="$HOME/Library/Application Support/Code/User"
  local target="$user_dir/settings.json"
  local source="$dotfiles_dir/vscode-settings.json"

  # The cask installs the app but never creates this directory; VS Code creates
  # it on first launch, which may not have happened yet.
  create_directory "$user_dir" || return 1

  if [[ "$(readlink "$target" 2>/dev/null)" == "$source" ]]; then
    __profile_log_warn "'$target' is already linked to the profile. Skipping..."
    return 0
  fi

  if [[ -L "$target" ]]; then
    ln -sfn "$source" "$target"
    return "$?"
  fi

  if [[ -e "$target" ]]; then
    __profile_log_warn "'$target' is a regular file, not a link. Leaving it alone."
    return 0
  fi

  ln -s "$source" "$target"
  return "$?"
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
    create_directory "$dir" || __profile_log_error "failed to create '$dir'!"
  done
}

function update_submodules() {
  __profile_log_info "updating submodules..."

  git -C "$SHA1N_PROFILE_HOME" submodule update --init
  return "$?"
}

function profile_is_darwin() {
  [[ "$OSTYPE" == darwin* ]]
}

function provision_packages() {
  __profile_log_info "provisioning packages..."
  __profile_provision_install "${PROFILE_LAYERS[@]}"
}

function check_dotfile_links() {
  local rc=0
  local file target
  for file in $(find "$dotfiles_dir" -type f | awk -F/ '{print $NF}'); do
    [[ "$file" == "init.lua" ]] && continue
    [[ "$file" == "vscode-settings.json" ]] && continue
    target="$HOME/$file"
    if [[ "$(readlink "$target" 2>/dev/null)" != "$dotfiles_dir/$file" ]]; then
      __profile_log_warn "not linked to the profile: $target"
      rc=1
    fi
  done

  if [[ "$(readlink "$HOME/.config/nvim/init.lua" 2>/dev/null)" != "$dotfiles_dir/init.lua" ]]; then
    __profile_log_warn "not linked to the profile: $HOME/.config/nvim/init.lua"
    rc=1
  fi

  return $rc
}

function run_check() {
  local rc=0

  if profile_is_darwin && [[ -z "$PROFILE_NO_PROVISION" ]]; then
    if [[ -n "$PROFILE_CHECK_UPGRADES" ]]; then
      __profile_provision_check_upgrades "${PROFILE_LAYERS[@]}" || rc=1
    else
      __profile_provision_check "${PROFILE_LAYERS[@]}" || rc=1
    fi
  fi

  check_dotfile_links || rc=1

  if (( rc == 0 )); then
    __profile_log_success "no drift detected"
  else
    __profile_log_warn "drift detected"
  fi
  return $rc
}

function compile_bytecode() {
  __profile_log_info "compiling zsh files to bytecode..."
  for f in "$SHA1N_PROFILE_HOME"/load.zsh "$SHA1N_PROFILE_HOME"/include/*(.) "$SHA1N_PROFILE_HOME"/scripts/lib.zsh; do
    [[ "$f" == *.zwc ]] && continue
    zcompile "$f" 2>/dev/null
  done
  __profile_log_success "bytecode compilation complete"
  return 0
}

function main() {
  if profile_is_darwin && [[ -z "$PROFILE_NO_PROVISION" ]]; then
    run_step "packages" provision_packages || return 1
  fi

  run_step "submodules" update_submodules || return 1
  __profile_log_success "submodules updated successfully"

  run_step "dotfiles" link_dotfiles || return 1
  run_step "directories" create_directories || return 1

  validate_shell_rc_file && install_source_command

  run_step "agent configs" install_agents_global || return 1
  run_step "neovim" setup_neovim || return 1
  run_step "vscode settings" setup_vscode_settings || return 1
  run_step "bytecode" compile_bytecode || return 1

  __profile_log_info "done!"
  return 0
}

PROFILE_ARGV_ECHO="$*"

# `|| rc=$?` rather than a bare call: under the strict mode above, errexit would
# abort the script on a non-zero return before $? could be inspected.
__profile_parse_rc=0
parse_args "$@" || __profile_parse_rc=$?
if (( __profile_parse_rc == 10 )); then
  return 0 2>/dev/null || exit 0
elif (( __profile_parse_rc != 0 )); then
  return $__profile_parse_rc 2>/dev/null || exit $__profile_parse_rc
fi

# provision/ is the platform boundary: it is never sourced off Darwin, so the
# rest of the repo stays dual-platform.
if profile_is_darwin; then
  source "$SHA1N_PROFILE_HOME/provision/provision.zsh"
  for __profile_layer in "${PROFILE_LAYERS[@]}"; do
    if ! __profile_provision_validate_layer "$__profile_layer"; then
      return 2 2>/dev/null || exit 2
    fi
  done
elif (( ${#PROFILE_LAYERS} > 0 )) || [[ -n "$PROFILE_COMPOSE_ONLY" ]]; then
  __profile_log_error "--profile and --compose are Darwin-only; provisioning is not supported on this platform"
  return 2 2>/dev/null || exit 2
fi

# Both short-circuit before main(): they are read-only modes and must never
# reach the provisioning step main() starts with.
if [[ -n "$PROFILE_COMPOSE_ONLY" ]]; then
  __profile_compose_rc=0
  __profile_provision_compose "${PROFILE_LAYERS[@]}" || __profile_compose_rc=$?
  return $__profile_compose_rc 2>/dev/null || exit $__profile_compose_rc
fi

if [[ -n "$PROFILE_CHECK_ONLY" ]]; then
  __profile_check_rc=0
  run_check || __profile_check_rc=$?
  return $__profile_check_rc 2>/dev/null || exit $__profile_check_rc
fi

__profile_main_rc=0
main || __profile_main_rc=$?
if [[ "${#zsh_eval_context}" -eq 1 ]]; then
  exit $__profile_main_rc
fi
