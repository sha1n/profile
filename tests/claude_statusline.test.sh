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

function test_context_color_bands() {
  test_case_title
  reset_home

  local green=$'\e[38;2;133;153;0m' yellow=$'\e[38;2;181;137;0m'
  local orange=$'\e[38;2;203;75;22m' red=$'\e[38;2;220;50;47m'
  local -A expected=(
    0 "$green" 19 "$green"
    20 "$yellow" 29 "$yellow"
    30 "$orange" 49 "$orange"
    50 "$red" 100 "$red"
  )

  local pct output
  for pct in ${(k)expected}; do
    output="$(print -r -- "{\"model\":{\"display_name\":\"M\"},\"context_window\":{\"used_percentage\":$pct}}" |
      env -i HOME="$HOME" PATH="$child_path" TERM=dumb "$profile_home/agents/claude/statusline.sh")"
    assert_contains "$output" "${expected[$pct]}${pct}%"
  done
}

function test_context_segment_has_bar() {
  test_case_title
  reset_home

  local output
  output="$(run_wrapper)"
  assert_contains "$output" "CTX "
  assert_contains "$output" "████"
  assert_contains "$output" "░░░░░░"
  assert_not_contains "$output" "CW "
}

# statusline.sh finds disk_free relative to its own path, so a copy in a temporary
# tree runs against a stub instead of the real disk.
build_statusline_tree() {
  mkdir -p "$HOME/tree/agents/claude" "$HOME/tree/scripts"
  cp "$profile_home/agents/claude/statusline.sh" "$HOME/tree/agents/claude/statusline.sh"
}

write_disk_free_stub() {
  print -r -- "#!/bin/sh
$1" >"$HOME/tree/scripts/disk_free"
  chmod +x "$HOME/tree/scripts/disk_free"
}

run_tree_statusline() {
  print -r -- "$payload" | env -i HOME="$HOME" PATH="$child_path" TERM=dumb "$HOME/tree/agents/claude/statusline.sh"
}

assert_no_disk_segment() {
  local output="$1" stripped
  assert_contains "$output" "Test Model"
  assert_not_contains "$output" "⛁"
  stripped="$(print -r -- "$output" | sed $'s/\e\\[[0-9;]*m//g; s/[[:space:]]*$//')"
  assert_not_equal "${stripped[-1]}" "|"
}

function test_disk_color_bands() {
  test_case_title
  reset_home

  local light_orange=$'\e[38;2;255;175;95m' red=$'\e[38;2;220;50;47m'
  local -A expected=(
    100Gi "$light_orange" 100G "$light_orange" 100.0G "$light_orange" 99Gi "$light_orange"
    51Gi "$light_orange" 50.5G "$light_orange"
    50Gi "$red" 50G "$red" 50.0G "$red" 49.9Gi "$red" 49Gi "$red" 900Mi "$red" 0B "$red"
  )

  build_statusline_tree
  local value output
  for value in ${(k)expected}; do
    write_disk_free_stub "echo $value"
    output="$(run_tree_statusline)"
    assert_contains "$output" "${expected[$value]}⛁ ${value}"
  done
}

function test_disk_segment_hidden_above_100_gib() {
  test_case_title
  reset_home

  build_statusline_tree
  local value
  for value in 100.5G 101Gi 156Gi 1.5Ti 2T 1,5T 3P; do
    write_disk_free_stub "echo $value"
    assert_no_disk_segment "$(run_tree_statusline)"
  done
}

function test_disk_segment_omitted_when_disk_free_prints_nothing() {
  test_case_title
  reset_home

  build_statusline_tree
  write_disk_free_stub ":"
  assert_no_disk_segment "$(run_tree_statusline)"
}

function test_disk_segment_omitted_when_disk_free_is_missing() {
  test_case_title
  reset_home

  build_statusline_tree
  assert_no_disk_segment "$(run_tree_statusline)"
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
run_test test_context_color_bands
run_test test_context_segment_has_bar
run_test test_disk_color_bands
run_test test_disk_segment_hidden_above_100_gib
run_test test_disk_segment_omitted_when_disk_free_prints_nothing
run_test test_disk_segment_omitted_when_disk_free_is_missing
run_test test_wrapper_forwards_payload_to_orca
run_test test_wrapper_skips_non_executable_orca_script
run_test test_claude_function_injects_statusline_settings
cleanup
finish_tests
