#!/usr/bin/env zsh

source "$SHA1N_PROFILE_TESTS_HOME/sandbox.zsh"

disk_free="$profile_home/scripts/disk_free"

function test_prints_free_space_of_root() {
  test_case_title

  local output exit_code
  output="$(env -i HOME="$HOME" PATH=/usr/bin:/bin TERM=dumb "$disk_free" 2>&1)"
  exit_code="$?"

  assert_equal "$exit_code" "0"
  assert_match "$output" '^[0-9.,]+[A-Za-z]*$'
}

setup
run_test test_prints_free_space_of_root
cleanup
finish_tests
