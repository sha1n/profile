#!/usr/bin/env zsh

source "$__ZSH_SCRIPTEST_HOME/matchers.sh"
source "$__ZSH_SCRIPTEST_HOME/test_util.sh"


function test_source() {
  test_case_title

  source "$SHA1N_PROFILE_TESTS_HOME/../.include"

  assert_not_empty "$SHA1N_PROFILE_HOME"
}

function test_locale_set() {
  test_case_title

  assert_contains "$LANG" "en_US.UTF-8"
  assert_contains "$LC_CTYPE" "en_US.UTF-8"
}

function test_env_vars() {
  test_case_title

  assert_not_empty "$CODE"
  assert_contains "$CODE" "$HOME"
}

function test_dir_layout() {
  test_case_title

  assert_dir_exists "$CODE"
  assert_dir_exists "$HOME/.local/bin"
}

function test_dir_path_elements() {
  test_case_title

  assert_contains "$PATH" "$HOME/.local/bin"
  assert_contains "$PATH" "$SHA1N_PROFILE_HOME/scripts"
}

test_source
test_locale_set
test_env_vars
test_dir_layout
test_dir_path_elements
