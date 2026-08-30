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
    source "$SHA1N_PROFILE_TESTS_HOME/../install.sh"
    source "$SHA1N_PROFILE_TESTS_HOME/../load.zsh"
    export CLAUDE_MCP_LOG_ROOT="$HOME/claude-log-root"
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

create_test_logs() {
  local project_dir="$HOME/test-project"
  mkdir -p "$project_dir"

  local log_dir
  log_dir="$(__profile_claude_mcp_log_dir "$project_dir")/mcp-logs-acdc-dev"
  mkdir -p "$log_dir"
  mkdir -p "$(__profile_claude_mcp_log_dir "$project_dir")/mcp-logs-other-server"

  # Claude Code replaces every character that is not a letter or a digit in a
  # server name, so a plugin server 'plugin:x:y' logs to 'mcp-logs-plugin-x-y'.
  local plugin_dir
  plugin_dir="$(__profile_claude_mcp_log_dir "$project_dir")/mcp-logs-plugin-sha1n-corpus-acdc-corpus"
  mkdir -p "$plugin_dir"
  cat > "$plugin_dir/2026-01-02T00-00-00-000Z.jsonl" <<'EOF'
{"error":"Server stderr: level=INFO msg=\"plugin session line\"","timestamp":"2026-01-02T00:00:01.000Z"}
EOF

  cat > "$log_dir/2026-01-01T00-00-00-000Z.jsonl" <<'EOF'
{"debug":"Connection established","timestamp":"2026-01-01T00:00:00.000Z"}
{"error":"Server stderr: level=INFO msg=\"older session line\"","timestamp":"2026-01-01T00:00:01.000Z"}
EOF

  cat > "$log_dir/2026-01-02T00-00-00-000Z.jsonl" <<'EOF'
{"debug":"MCP server process exited cleanly","timestamp":"2026-01-02T00:00:00.000Z"}
{"error":"Server stderr: level=INFO msg=\"newest session line\"","timestamp":"2026-01-02T00:00:01.000Z"}
EOF
  touch -t 202601010000 "$log_dir/2026-01-01T00-00-00-000Z.jsonl"
  touch -t 202601020000 "$log_dir/2026-01-02T00-00-00-000Z.jsonl"

  cd "$project_dir"
}

# ------ claude_mcp_logs tests ------

function test_claude_mcp_log_dir_slug() {
  test_case_title

  local dir
  dir=$(CLAUDE_MCP_LOG_ROOT=/log-root __profile_claude_mcp_log_dir "/Users/x/code/my.proj")

  assert_equal "$dir" "/log-root/-Users-x-code-my-proj"
}

function test_claude_mcp_logs_unknown_project() {
  test_case_title
  mkdir -p "$HOME/no-logs-here"
  cd "$HOME/no-logs-here"

  local output
  output=$(claude_mcp_logs some-server 2>&1)
  assert_exit_code 1 "claude_mcp_logs some-server"
  assert_contains "$output" "no Claude Code logs"
}

function test_claude_mcp_logs_no_args_lists_servers() {
  test_case_title
  create_test_logs

  local output
  output=$(claude_mcp_logs 2>&1)
  assert_exit_code 1 "claude_mcp_logs"
  assert_contains "$output" "acdc-dev"
  assert_contains "$output" "other-server"
}

function test_claude_mcp_logs_unknown_server() {
  test_case_title
  create_test_logs

  local output
  output=$(claude_mcp_logs nope 2>&1)
  assert_exit_code 1 "claude_mcp_logs nope"
  assert_contains "$output" "no logs for MCP server 'nope'"
  assert_contains "$output" "acdc-dev"
}

function test_claude_mcp_logs_prints_newest_session_only() {
  test_case_title
  create_test_logs

  local output
  output=$(claude_mcp_logs -n acdc-dev 2>&1)
  assert_contains "$output" "newest session line"
  assert_not_contains "$output" "older session line"
}

function test_claude_mcp_logs_strips_stderr_prefix() {
  test_case_title
  create_test_logs

  local output
  output=$(claude_mcp_logs -n acdc-dev 2>&1)
  assert_not_contains "$output" "Server stderr:"
}

function test_claude_mcp_logs_hides_debug_lines_by_default() {
  test_case_title
  create_test_logs

  local output
  output=$(claude_mcp_logs -n acdc-dev 2>&1)
  assert_not_contains "$output" "exited cleanly"
}

function test_claude_mcp_logs_debug_flag_shows_connection_lines() {
  test_case_title
  create_test_logs

  local output
  output=$(claude_mcp_logs -n -d acdc-dev 2>&1)
  assert_contains "$output" "exited cleanly"
  assert_contains "$output" "newest session line"
}

function test_claude_mcp_logs_all_flag_reads_every_session() {
  test_case_title
  create_test_logs

  local output
  output=$(claude_mcp_logs -n -a acdc-dev 2>&1)
  assert_contains "$output" "older session line"
  assert_contains "$output" "newest session line"
}

function test_claude_mcp_logs_project_dir_flag() {
  test_case_title
  create_test_logs
  cd "$HOME"

  local output
  output=$(claude_mcp_logs -n -C "$HOME/test-project" acdc-dev 2>&1)
  assert_contains "$output" "newest session line"
}

function test_claude_mcp_logs_rejects_unknown_flag() {
  test_case_title
  create_test_logs

  local output
  output=$(claude_mcp_logs -Z acdc-dev 2>&1)
  assert_exit_code 1 "claude_mcp_logs -Z acdc-dev"
  assert_contains "$output" "Usage: claude_mcp_logs"
}

function test_claude_mcp_logs_plugin_server_name() {
  test_case_title
  create_test_logs

  local output
  output=$(claude_mcp_logs -n "plugin:sha1n-corpus:acdc-corpus" 2>&1)
  assert_contains "$output" "plugin session line"
}

function test_claude_mcp_logs_sanitized_server_name() {
  test_case_title
  create_test_logs

  local output
  output=$(claude_mcp_logs -n "plugin-sha1n-corpus-acdc-corpus" 2>&1)
  assert_contains "$output" "plugin session line"
}

setup
run_test test_claude_mcp_log_dir_slug
run_test test_claude_mcp_logs_unknown_project
run_test test_claude_mcp_logs_no_args_lists_servers
run_test test_claude_mcp_logs_unknown_server
run_test test_claude_mcp_logs_prints_newest_session_only
run_test test_claude_mcp_logs_strips_stderr_prefix
run_test test_claude_mcp_logs_hides_debug_lines_by_default
run_test test_claude_mcp_logs_debug_flag_shows_connection_lines
run_test test_claude_mcp_logs_all_flag_reads_every_session
run_test test_claude_mcp_logs_project_dir_flag
run_test test_claude_mcp_logs_rejects_unknown_flag
run_test test_claude_mcp_logs_plugin_server_name
run_test test_claude_mcp_logs_sanitized_server_name
finish_tests
cleanup
