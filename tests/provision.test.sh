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

setup
run_test test_all_submodules_use_https
run_test test_all_submodules_are_checked_out
finish_tests
cleanup
