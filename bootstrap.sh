#!/usr/bin/env zsh
# Usage: curl -fsSL https://raw.githubusercontent.com/sha1n/profile/master/bootstrap.sh | zsh -s -- [essentials|dev]

__BOOTSTRAP_REPO_URL="https://github.com/sha1n/profile.git"
__BOOTSTRAP_HOMEBREW_INSTALLER_URL="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"

function __bootstrap_log_error() {
  print -r -- "ERROR: $*" >&2
}

function __bootstrap_log_info() {
  print -r -- "INFO: $*"
}

# A copy of __profile_log_section: bootstrap runs before the repo, and so lib.zsh, exists.
function __bootstrap_log_section() {
  local title="$1"
  print
  print -P "%B%K{blue}%F{white} ${title//\%/%%} %f%k%b"
}

function __bootstrap_repo_dir() {
  print -r -- "$HOME/code/profile"
}

function __bootstrap_check_platform() {
  emulate -L zsh
  local kernel="$(uname -s)"
  if [[ "$kernel" != "Darwin" ]]; then
    __bootstrap_log_error "bootstrap.sh supports macOS only (uname -s: '$kernel')"
    return 1
  fi
}

function __bootstrap_brew_bin() {
  emulate -L zsh
  if [[ -x /opt/homebrew/bin/brew ]]; then
    print -r -- /opt/homebrew/bin/brew
  elif [[ -x /usr/local/bin/brew ]]; then
    print -r -- /usr/local/bin/brew
  elif (( $+commands[brew] )); then
    print -r -- "$commands[brew]"
  else
    return 1
  fi
}

function __bootstrap_install_homebrew() {
  local brew_bin
  if brew_bin="$(__bootstrap_brew_bin)"; then
    __bootstrap_log_info "Homebrew is already installed ($brew_bin). Skipping..."
  else
    __bootstrap_log_info "installing Homebrew..."
    # The installer runs with NONINTERACTIVE=1, so it needs cached sudo credentials.
    sudo -v || return 1
    # </dev/null: a child that reads stdin would consume the rest of a piped script.
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL "$__BOOTSTRAP_HOMEBREW_INSTALLER_URL")" </dev/null || return 1
    brew_bin="$(__bootstrap_brew_bin)" || return 1
  fi
  eval "$("$brew_bin" shellenv)"
}

function __bootstrap_clone() {
  emulate -L zsh
  local repo_dir="$(__bootstrap_repo_dir)"
  if [[ -e "$repo_dir" ]]; then
    __bootstrap_log_info "'$repo_dir' already exists. Skipping clone..."
  else
    __bootstrap_log_info "cloning profile to '$repo_dir'..."
    mkdir -p "${repo_dir:h}" || return 1
    git clone "$__BOOTSTRAP_REPO_URL" "$repo_dir" </dev/null || return 1
  fi
}

function __bootstrap_update_submodules() {
  emulate -L zsh
  # HTTPS only: a new Mac has no SSH key yet, and .gitmodules uses SSH URLs.
  # Runs on an existing checkout too, so a rerun completes submodules a failed run left behind.
  git -c url."https://github.com/".insteadOf=git@github.com: -C "$(__bootstrap_repo_dir)" submodule update --init </dev/null
}

function __bootstrap_print_next_steps() {
  __bootstrap_log_section "Next steps"
  print -r -- "  1. gh auth login
  2. Create an SSH key (ssh-keygen -t ed25519) and upload it with: gh ssh-key add ~/.ssh/id_ed25519.pub
  3. Open VS Code and turn on Settings Sync"
}

function __bootstrap_main() {
  local repo_dir="$(__bootstrap_repo_dir)"

  __bootstrap_check_platform || return 1

  __bootstrap_log_section "Homebrew"
  __bootstrap_install_homebrew || { __bootstrap_log_error "failed to install Homebrew"; return 1; }

  __bootstrap_log_section "Clone"
  __bootstrap_clone || { __bootstrap_log_error "failed to clone profile"; return 1; }

  __bootstrap_log_section "Submodules"
  __bootstrap_update_submodules || { __bootstrap_log_error "failed to update submodules"; return 1; }

  "$repo_dir/install.sh" </dev/null || { __bootstrap_log_error "install.sh failed"; return 1; }

  "$repo_dir/scripts/profile" install "$@" </dev/null
  local install_status=$?
  (( install_status == 0 )) || return $install_status

  __bootstrap_print_next_steps
}

# Main guard: ZSH_EVAL_CONTEXT ends with ':file' only when sourced. The `if` form keeps the
# status of a source at 0, where the `&&` form would return 1.
if [[ "$ZSH_EVAL_CONTEXT" != *:file* ]]; then __bootstrap_main "$@"; fi
