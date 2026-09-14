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
finish_tests
cleanup
