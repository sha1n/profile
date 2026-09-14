#!/usr/bin/env zsh

source "$__ZSH_SCRIPTEST_HOME/matchers.sh"
source "$__ZSH_SCRIPTEST_HOME/test_util.sh"
fingerprint=$(cat /dev/urandom | base64 | tr -dc '0-9a-zA-Z' | head -c50)

setup() {
  if [[ "$(ls -A $HOME)" ]]; then
    echo "the test \$HOME directory is expected to be a temporary empty directory"
    exit 1
  else
    test_setup_title
    touch "$HOME/$fingerprint"
    source "$SHA1N_PROFILE_TESTS_HOME/../install.sh" --no-provision
    source "$SHA1N_PROFILE_TESTS_HOME/../load.zsh"
  fi
}

cleanup() {
  test_teardown_title
  assert_file_exists "$HOME/$fingerprint"
  if [[ -f "$HOME/$fingerprint" ]]; then
    echo
    rm -rf "$HOME"
    mkdir -p "$HOME"
  fi
}

function test_all_submodules_use_https() {
  test_case_title

  local ssh_urls
  ssh_urls="$(grep -c 'url = git@' "$SHA1N_PROFILE_HOME/.gitmodules" || true)"
  assert_equal "$ssh_urls" "0"
}

function test_all_submodules_are_checked_out() {
  test_case_title

  # A bare '-' prefix in `git submodule status` means the submodule is not initialised.
  local uninitialised
  uninitialised="$(git -C "$SHA1N_PROFILE_HOME" submodule status | grep -c '^-' || true)"
  assert_equal "$uninitialised" "0"
}

function test_available_layers_discovered_by_glob() {
  test_case_title

  source "$SHA1N_PROFILE_HOME/provision/provision.zsh"
  local layers
  layers="$(__profile_provision_available_layers | sort | tr '\n' ' ')"
  assert_contains "$layers" "dev-go"
  assert_contains "$layers" "dev-java"
  assert_contains "$layers" "dev-node"
  assert_contains "$layers" "dev-ops"
  assert_contains "$layers" "dev-python"
  # essentials is implicit, never a selectable layer
  assert_not_contains "$layers" "essentials"
}

function test_validate_layer_rejects_unknown() {
  test_case_title

  source "$SHA1N_PROFILE_HOME/provision/provision.zsh"
  __profile_provision_validate_layer "dev-cobol" >/dev/null 2>&1
  assert_equal "$?" "1"

  __profile_provision_validate_layer "dev-go" >/dev/null 2>&1
  assert_equal "$?" "0"
}

function test_compose_always_includes_essentials() {
  test_case_title

  source "$SHA1N_PROFILE_HOME/provision/provision.zsh"
  local composed
  composed="$(__profile_provision_compose)"
  assert_contains "$composed" 'brew "coreutils"'
  assert_not_contains "$composed" 'brew "golangci-lint"'
}

function test_compose_appends_selected_layers() {
  test_case_title

  source "$SHA1N_PROFILE_HOME/provision/provision.zsh"
  local composed
  composed="$(__profile_provision_compose dev-go dev-node)"
  assert_contains "$composed" 'brew "coreutils"'
  assert_contains "$composed" 'brew "golangci-lint"'
  assert_contains "$composed" 'brew "yarn"'
  assert_not_contains "$composed" 'brew "poetry"'
}

function test_profile_flag_rejected_on_linux() {
  test_case_title

  # The Darwin boundary is what protects the dual-platform contract in AGENTS.md.
  if [[ "$OSTYPE" == darwin* ]]; then
    echo "  skipped on darwin"
    return 0
  fi

  zsh "$SHA1N_PROFILE_TESTS_HOME/../install.sh" --profile dev-go --no-provision >/dev/null 2>&1
  assert_equal "$?" "2"
}

function test_unknown_layer_rejected_on_darwin() {
  test_case_title

  if [[ "$OSTYPE" != darwin* ]]; then
    echo "  skipped off darwin"
    return 0
  fi

  local out
  out="$(zsh "$SHA1N_PROFILE_TESTS_HOME/../install.sh" --profile dev-cobol --no-provision 2>&1)"
  assert_equal "$?" "2"
  assert_contains "$out" "dev-cobol"
}

function test_no_provision_skips_homebrew() {
  test_case_title

  local out
  out="$(zsh "$SHA1N_PROFILE_TESTS_HOME/../install.sh" --no-provision --yes 2>&1)"
  assert_not_contains "$out" "provisioning packages"
}

function test_compose_prints_effective_brewfile() {
  test_case_title

  if [[ "$OSTYPE" != darwin* ]]; then
    echo "  skipped off darwin"
    return 0
  fi

  local out
  out="$(zsh "$SHA1N_PROFILE_TESTS_HOME/../install.sh" --compose --profile dev-go 2>/dev/null)"
  assert_equal "$?" "0"
  assert_contains "$out" 'brew "coreutils"'
  assert_contains "$out" 'brew "golangci-lint"'
  assert_not_contains "$out" 'brew "poetry"'
}

function test_check_is_non_mutating() {
  test_case_title

  if [[ "$OSTYPE" != darwin* ]]; then
    echo "  skipped off darwin"
    return 0
  fi

  # A fingerprint of installed state must be identical before and after --check.
  local before after
  before="$(brew list --formula --versions; brew list --cask --versions)"
  zsh "$SHA1N_PROFILE_TESTS_HOME/../install.sh" --check >/dev/null 2>&1
  after="$(brew list --formula --versions; brew list --cask --versions)"

  assert_equal "$before" "$after"
}

function test_check_does_not_link_dotfiles() {
  test_case_title

  rm -f "$HOME/.vimrc"
  zsh "$SHA1N_PROFILE_TESTS_HOME/../install.sh" --check --no-provision >/dev/null 2>&1
  assert_equal "$(test -e "$HOME/.vimrc" && echo present || echo absent)" "absent"
}

function test_neovim_relinks_a_foreign_symlink() {
  test_case_title

  local nvim_dir="$HOME/.config/nvim"
  local foreign="$HOME/foreign-init.lua"
  mkdir -p "$nvim_dir"
  print -r -- "-- not ours" >"$foreign"
  ln -sfn "$foreign" "$nvim_dir/init.lua"

  PROFILE_ASSUME_YES=1 setup_neovim >/dev/null 2>&1

  assert_equal "$(readlink "$nvim_dir/init.lua")" "$SHA1N_PROFILE_HOME/dotfiles/init.lua"
}

function test_neovim_preserves_a_real_file() {
  test_case_title

  local nvim_dir="$HOME/.config/nvim"
  mkdir -p "$nvim_dir"
  rm -f "$nvim_dir/init.lua"
  print -r -- "-- hand written" >"$nvim_dir/init.lua"

  PROFILE_ASSUME_YES=1 setup_neovim >/dev/null 2>&1

  # A regular file is the user's own work; never clobber it silently.
  assert_empty "$(readlink "$nvim_dir/init.lua" 2>/dev/null)"
  assert_contains "$(cat "$nvim_dir/init.lua")" "hand written"
}

function test_vscode_settings_not_linked_into_home_root() {
  test_case_title

  # dotfiles/ is linked by basename, so this file must be excluded from the loop.
  assert_equal "$(test -e "$HOME/vscode-settings.json" && echo present || echo absent)" "absent"
}

function test_vscode_settings_linked_to_application_support() {
  test_case_title

  if [[ "$OSTYPE" != darwin* ]]; then
    echo "  skipped off darwin"
    return 0
  fi

  local target="$HOME/Library/Application Support/Code/User/settings.json"
  assert_equal "$(readlink "$target")" "$SHA1N_PROFILE_HOME/dotfiles/vscode-settings.json"
}

function test_go_bin_on_path() {
  test_case_title

  assert_contains "$PATH" "$HOME/go/bin"
}

function test_solarized_colorscheme_is_tracked() {
  test_case_title

  # dotfiles/.vimrc:4 sets `colorscheme solarized`; the file must ship with the repo.
  assert_file_exists "$SHA1N_PROFILE_HOME/dotfiles/colors/solarized.vim"
}

function test_solarized_linked_where_vim_looks() {
  test_case_title

  # dotfiles/ is linked into $HOME by basename, which would put the colorscheme at
  # ~/solarized.vim where vim never looks. It is linked into ~/.vim/colors instead,
  # keeping vim's stock runtimepath and no repo path literal in .vimrc.
  assert_equal "$(readlink "$HOME/.vim/colors/solarized.vim")" "$SHA1N_PROFILE_HOME/dotfiles/colors/solarized.vim"
  assert_equal "$(test -e "$HOME/solarized.vim" && echo present || echo absent)" "absent"
}

function test_nvm_sourced_when_present() {
  test_case_title

  if ! command -v brew >/dev/null 2>&1 || [[ ! -s "$(brew --prefix nvm 2>/dev/null)/nvm.sh" ]]; then
    echo "  skipped: nvm not installed"
    return 0
  fi

  assert_equal "$(type -w nvm | cut -d: -f2 | tr -d ' ')" "function"
}

setup
run_test test_all_submodules_use_https
run_test test_all_submodules_are_checked_out
run_test test_available_layers_discovered_by_glob
run_test test_validate_layer_rejects_unknown
run_test test_compose_always_includes_essentials
run_test test_compose_appends_selected_layers
run_test test_profile_flag_rejected_on_linux
run_test test_unknown_layer_rejected_on_darwin
run_test test_no_provision_skips_homebrew
run_test test_compose_prints_effective_brewfile
run_test test_check_is_non_mutating
run_test test_check_does_not_link_dotfiles
run_test test_neovim_relinks_a_foreign_symlink
run_test test_neovim_preserves_a_real_file
run_test test_vscode_settings_not_linked_into_home_root
run_test test_vscode_settings_linked_to_application_support
run_test test_go_bin_on_path
run_test test_solarized_colorscheme_is_tracked
run_test test_solarized_linked_where_vim_looks
run_test test_nvm_sourced_when_present
finish_tests
cleanup
