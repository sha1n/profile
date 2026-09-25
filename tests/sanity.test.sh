#!/usr/bin/env zsh

source "$SHA1N_PROFILE_TESTS_HOME/sandbox.zsh"

install_profile() {
  # install profile in the test sandbox HOME directory
  source "$SHA1N_PROFILE_TESTS_HOME/../install.sh"
  # source load.zsh at top level so exports are visible to all run_test subshells
  source "$SHA1N_PROFILE_TESTS_HOME/../load.zsh"
}

function test_source() {
  test_case_title

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

function test_agents_global_linked() {
  test_case_title

  # fresh install (empty sandbox HOME) symlinks ~/.claude/CLAUDE.md to the profile
  assert_equal "$(readlink "$HOME/.claude/CLAUDE.md")" "$SHA1N_PROFILE_HOME/agents/AGENTS.md"
  assert_equal "$(readlink "$HOME/.codex/AGENTS.md")" "$SHA1N_PROFILE_HOME/agents/AGENTS.md"
}

function test_agents_global_idempotent() {
  test_case_title

  # re-running against an already-correct link is a silent no-op (no prompt, no error)
  __profile_install_agents_global >/dev/null 2>&1
  assert_equal "$?" "0"
  assert_equal "$(readlink "$HOME/.claude/CLAUDE.md")" "$SHA1N_PROFILE_HOME/agents/AGENTS.md"
  assert_equal "$(readlink "$HOME/.codex/AGENTS.md")" "$SHA1N_PROFILE_HOME/agents/AGENTS.md"
}

function test_agents_global_keep_existing() {
  test_case_title

  # existing file + 'n' answer -> keep the user's own file untouched
  rm -f "$HOME/.claude/CLAUDE.md" "$HOME/.codex/AGENTS.md"
  print "KEEP MY OWN RULES" >"$HOME/.claude/CLAUDE.md"
  print "KEEP CODEX RULES" >"$HOME/.codex/AGENTS.md"

  print "n\nn\n" | __profile_install_agents_global >/dev/null 2>&1

  assert_empty "$(readlink "$HOME/.claude/CLAUDE.md" 2>/dev/null)"
  assert_contains "$(cat "$HOME/.claude/CLAUDE.md")" "KEEP MY OWN RULES"
  assert_empty "$(readlink "$HOME/.codex/AGENTS.md" 2>/dev/null)"
  assert_contains "$(cat "$HOME/.codex/AGENTS.md")" "KEEP CODEX RULES"
}

function test_agents_global_replace_existing() {
  test_case_title

  # existing file + 'Y' answer -> delete it and link to the profile
  rm -f "$HOME/.claude/CLAUDE.md" "$HOME/.codex/AGENTS.md"
  print "OLD CONTENT" >"$HOME/.claude/CLAUDE.md"
  print "OLD CONTENT" >"$HOME/.codex/AGENTS.md"

  print "Y\nY\n" | __profile_install_agents_global >/dev/null 2>&1

  assert_equal "$(readlink "$HOME/.claude/CLAUDE.md")" "$SHA1N_PROFILE_HOME/agents/AGENTS.md"
  assert_equal "$(readlink "$HOME/.codex/AGENTS.md")" "$SHA1N_PROFILE_HOME/agents/AGENTS.md"
}

function test_agents_global_default_replaces() {
  test_case_title

  # existing file + empty answer (Enter) -> default is Yes, so replace
  rm -f "$HOME/.claude/CLAUDE.md" "$HOME/.codex/AGENTS.md"
  print "OLD CONTENT" >"$HOME/.claude/CLAUDE.md"
  print "OLD CONTENT" >"$HOME/.codex/AGENTS.md"

  print "\n\n" | __profile_install_agents_global >/dev/null 2>&1

  assert_equal "$(readlink "$HOME/.claude/CLAUDE.md")" "$SHA1N_PROFILE_HOME/agents/AGENTS.md"
  assert_equal "$(readlink "$HOME/.codex/AGENTS.md")" "$SHA1N_PROFILE_HOME/agents/AGENTS.md"
}

setup
install_profile
run_test test_source
run_test test_locale_set
run_test test_env_vars
run_test test_dir_layout
run_test test_dir_path_elements
run_test test_agents_global_linked
run_test test_agents_global_idempotent
run_test test_agents_global_keep_existing
run_test test_agents_global_replace_existing
run_test test_agents_global_default_replaces
cleanup
finish_tests
