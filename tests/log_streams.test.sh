#!/usr/bin/env zsh

source "$SHA1N_PROFILE_TESTS_HOME/sandbox.zsh"

log_stdout() {
  env -i HOME="$HOME" PATH="$PATH" TERM=dumb zsh -fc \
    'source "$1/scripts/lib.zsh" && "$2" message' zsh "$profile_home" "$1" 2>/dev/null
}

log_stderr() {
  env -i HOME="$HOME" PATH="$PATH" TERM=dumb zsh -fc \
    'source "$1/scripts/lib.zsh" && "$2" message' zsh "$profile_home" "$1" 2>&1 >/dev/null
}

function test_diagnostics_go_to_stderr() {
  test_case_title

  local fn
  for fn in __profile_log_error __profile_log_warn; do
    assert_empty "$(log_stdout "$fn")"
    assert_contains "$(log_stderr "$fn")" "message"
  done
}

function test_progress_goes_to_stdout() {
  test_case_title

  local fn
  for fn in __profile_log_info __profile_log_success __profile_log_section; do
    assert_contains "$(log_stdout "$fn")" "message"
    assert_empty "$(log_stderr "$fn")"
  done
}

setup
run_test test_diagnostics_go_to_stderr
run_test test_progress_goes_to_stdout
cleanup
finish_tests
