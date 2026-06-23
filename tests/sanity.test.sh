#!/usr/bin/env zsh

source "$__ZSH_SCRIPTEST_HOME/matchers.sh"
source "$__ZSH_SCRIPTEST_HOME/test_util.sh"
fingerprint=$(cat /dev/urandom | base64 | tr -dc '0-9a-zA-Z' | head -c50)

install_profile() {
  if [[ "$(ls -A $HOME)" ]]; then
    echo "the test $$HOME directory is expected to be a temporary empty directory"
    exit 1
  else
    test_setup_title
    touch "$HOME/$fingerprint"
    # install profile in the test sandbox HOME directory
    source "$SHA1N_PROFILE_TESTS_HOME/../install.sh"
    # source load.zsh at top level so exports are visible to all run_test subshells
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

function test_claude_global_linked() {
  test_case_title

  # fresh install (empty sandbox HOME) symlinks ~/.claude/CLAUDE.md to the profile
  assert_equal "$(readlink "$HOME/.claude/CLAUDE.md")" "$SHA1N_PROFILE_HOME/claude/CLAUDE.md"
}

function test_claude_global_idempotent() {
  test_case_title

  # re-running against an already-correct link is a silent no-op (no prompt, no error)
  install_claude_global >/dev/null 2>&1
  assert_equal "$?" "0"
  assert_equal "$(readlink "$HOME/.claude/CLAUDE.md")" "$SHA1N_PROFILE_HOME/claude/CLAUDE.md"
}

function test_claude_global_keep_existing() {
  test_case_title

  # existing file + 'n' answer -> keep the user's own file untouched
  rm -f "$HOME/.claude/CLAUDE.md"
  print "KEEP MY OWN RULES" >"$HOME/.claude/CLAUDE.md"

  print "n" | install_claude_global >/dev/null 2>&1

  assert_empty "$(readlink "$HOME/.claude/CLAUDE.md" 2>/dev/null)"
  assert_contains "$(cat "$HOME/.claude/CLAUDE.md")" "KEEP MY OWN RULES"
}

function test_claude_global_replace_existing() {
  test_case_title

  # existing file + 'Y' answer -> delete it and link to the profile
  rm -f "$HOME/.claude/CLAUDE.md"
  print "OLD CONTENT" >"$HOME/.claude/CLAUDE.md"

  print "Y" | install_claude_global >/dev/null 2>&1

  assert_equal "$(readlink "$HOME/.claude/CLAUDE.md")" "$SHA1N_PROFILE_HOME/claude/CLAUDE.md"
}

function test_claude_global_default_replaces() {
  test_case_title

  # existing file + empty answer (Enter) -> default is Yes, so replace
  rm -f "$HOME/.claude/CLAUDE.md"
  print "OLD CONTENT" >"$HOME/.claude/CLAUDE.md"

  print "" | install_claude_global >/dev/null 2>&1

  assert_equal "$(readlink "$HOME/.claude/CLAUDE.md")" "$SHA1N_PROFILE_HOME/claude/CLAUDE.md"
}

install_profile
run_test test_source
run_test test_locale_set
run_test test_env_vars
run_test test_dir_layout
run_test test_dir_path_elements
run_test test_claude_global_linked
run_test test_claude_global_idempotent
run_test test_claude_global_keep_existing
run_test test_claude_global_replace_existing
run_test test_claude_global_default_replaces
finish_tests
cleanup
