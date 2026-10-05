#!/usr/bin/env zsh

source "$SHA1N_PROFILE_TESTS_HOME/sandbox.zsh"

wrapper="$profile_home/agents/claude/statusline_wrapper.sh"
payload='{"model":{"display_name":"Test Model"},"context_window":{"used_percentage":42}}'
child_path="${commands[zsh]:h}:${commands[jq]:h}:/usr/bin:/bin"

run_wrapper() {
  print -r -- "$payload" | env -i HOME="$HOME" PATH="$child_path" TERM=dumb "$wrapper"
}

write_orca_stub() {
  local body="$1"
  mkdir -p "$HOME/.orca/agent-hooks"
  print -r -- "$body" >"$HOME/.orca/agent-hooks/claude-statusline.sh"
}

function test_wrapper_renders_statusline() {
  test_case_title
  reset_home

  local output
  output="$(run_wrapper)"
  assert_equal "$?" "0"
  assert_contains "$output" "Test Model"
}

function test_wrapper_forwards_payload_to_orca() {
  test_case_title
  reset_home

  write_orca_stub 'cat >"$HOME/orca_received"
echo ORCA_NOISE'
  chmod +x "$HOME/.orca/agent-hooks/claude-statusline.sh"

  local output
  output="$(run_wrapper 2>&1)"
  assert_equal "$?" "0"
  assert_contains "$output" "Test Model"
  assert_not_contains "$output" "ORCA_NOISE"

  # The wrapper forwards in the background, so the file can appear after it exits.
  local i
  for i in {1..30}; do
    [[ -s "$HOME/orca_received" ]] && break
    sleep 0.1
  done
  assert_file_exists "$HOME/orca_received"
  assert_contains "$(<"$HOME/orca_received")" '"display_name":"Test Model"'
}

function test_wrapper_skips_non_executable_orca_script() {
  test_case_title
  reset_home

  write_orca_stub 'touch "$HOME/orca_ran"'
  chmod -x "$HOME/.orca/agent-hooks/claude-statusline.sh"

  local output
  output="$(run_wrapper)"
  assert_equal "$?" "0"
  assert_contains "$output" "Test Model"

  # A wrongly started background run would land after the wrapper exits.
  sleep 0.5
  assert_file_not_exists "$HOME/orca_ran"
}

function test_claude_function_injects_statusline_settings() {
  test_case_title
  reset_home

  local stub_dir="$HOME/stubs"
  mkdir -p "$stub_dir"
  print -r -- '#!/bin/sh
printf "%s\n" "$@" >"$HOME/claude_args"' >"$stub_dir/claude"
  chmod +x "$stub_dir/claude"

  env -i HOME="$HOME" PATH="$stub_dir:$child_path" TERM=dumb SHA1N_PROFILE_HOME="$profile_home" \
    "${commands[zsh]}" -c 'source "$SHA1N_PROFILE_HOME/include/functions"; claude --model x "two words"' \
    >/dev/null 2>&1

  assert_file_exists "$HOME/claude_args"
  local -a args=("${(@f)$(<"$HOME/claude_args")}")
  assert_equal "${#args}" "5"
  assert_equal "${args[1]}" "--settings"

  local settings="${args[2]}"
  assert_equal "$(print -r -- "$settings" | jq -r '.statusLine.type')" "command"

  local command_line
  command_line="$(print -r -- "$settings" | jq -r '.statusLine.command')"
  # Claude Code hands the command to a shell, so the path must survive shell parsing.
  assert_equal "$(sh -c 'eval "set -- $1"; printf %s "$1"' _ "$command_line")" "$wrapper"

  assert_equal "${args[3]}" "--model"
  assert_equal "${args[4]}" "x"
  assert_equal "${args[5]}" "two words"
}

setup
run_test test_wrapper_renders_statusline
run_test test_wrapper_forwards_payload_to_orca
run_test test_wrapper_skips_non_executable_orca_script
run_test test_claude_function_injects_statusline_settings
cleanup
finish_tests
