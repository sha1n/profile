#!/usr/bin/env zsh

source "$SHA1N_PROFILE_TESTS_HOME/sandbox.zsh"
# TERM=dumb drops the bold sequence, so a colour terminal type is used to make every sequence present.
section_term="xterm-256color"

prompt_escapes() {
  env -i HOME="$HOME" PATH="$PATH" TERM="$section_term" zsh -fc 'print -nP -- "$1"' zsh "$1"
}

function test_section_title_format() {
  test_case_title

  local start="$(prompt_escapes '%B%K{blue}%F{white}')"
  local reset="$(prompt_escapes '%f%k%b')"
  local bold="$(prompt_escapes '%B')"
  local background="$(prompt_escapes '%K{blue}')"

  # The trailing sentinel keeps command substitution from stripping the final newline.
  local output
  output="$(env -i HOME="$HOME" PATH="$PATH" TERM="$section_term" zsh -fc \
    'source "$1/scripts/lib.zsh" && __profile_log_section "a % b"' zsh "$profile_home" 2>&1; print -n x)"

  assert_not_empty "$bold"
  assert_not_empty "$background"
  assert_contains "$output" "$bold"
  assert_contains "$output" "$background"
  assert_equal "$output" $'\n'"${start} a % b ${reset}"$'\n'"x"
}

setup
run_test test_section_title_format
cleanup
finish_tests
