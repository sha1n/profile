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

create_test_repo() {
  local repo_dir="$HOME/test-repo"
  mkdir -p "$repo_dir"
  cd "$repo_dir"
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test"
  git commit -q --allow-empty -m "initial commit"
}

# ------ wt tests ------

function test_wt_no_args() {
  test_case_title
  create_test_repo

  local output
  output=$(wt 2>&1)
  assert_exit_code 1 "wt"
  assert_contains "$output" "Usage: wt"
}

function test_wt_new_branch() {
  test_case_title
  create_test_repo

  wt test-branch >/dev/null 2>&1
  local repo_dir="$HOME/test-repo"

  assert_dir_exists "$repo_dir/.worktree/test-branch"
  assert_contains "$PWD" ".worktree/test-branch"

  # verify branch was created
  cd "$repo_dir"
  local branches
  branches=$(git branch --list test-branch)
  assert_not_empty "$branches"
}

function test_wt_existing_branch() {
  test_case_title
  create_test_repo

  # create branch first without a worktree
  git branch existing-branch

  wt existing-branch >/dev/null 2>&1
  local repo_dir="$HOME/test-repo"

  assert_dir_exists "$repo_dir/.worktree/existing-branch"
  assert_contains "$PWD" ".worktree/existing-branch"
}

function test_wt_reenter_existing() {
  test_case_title
  create_test_repo

  local repo_dir="$HOME/test-repo"

  wt reenter-branch >/dev/null 2>&1
  assert_dir_exists "$repo_dir/.worktree/reenter-branch"

  # go back to repo root, then re-enter
  cd "$repo_dir"
  wt reenter-branch >/dev/null 2>&1
  assert_contains "$PWD" ".worktree/reenter-branch"
}

function test_wt_not_git_repo() {
  test_case_title

  local non_repo="$HOME/not-a-repo"
  mkdir -p "$non_repo"
  cd "$non_repo"

  assert_exit_code 1 "wt some-branch"
}

function test_wt_slash_branch() {
  test_case_title
  create_test_repo

  local repo_dir="$HOME/test-repo"

  wt feature/foo >/dev/null 2>&1

  assert_dir_exists "$repo_dir/.worktree/feature/foo"
  assert_contains "$PWD" ".worktree/feature/foo"
}

# ------ wt_rm tests ------

function test_wt_rm_no_args() {
  test_case_title
  create_test_repo

  local output
  output=$(wt_rm 2>&1)
  assert_exit_code 1 "wt_rm"
  assert_contains "$output" "Usage: wt_rm"
}

function test_wt_rm_nonexistent() {
  test_case_title
  create_test_repo

  assert_exit_code 1 "wt_rm no-such-branch"
}

function test_wt_rm_removes_worktree() {
  test_case_title
  create_test_repo

  local repo_dir="$HOME/test-repo"

  wt rm-wt-branch >/dev/null 2>&1
  cd "$repo_dir"

  assert_dir_exists "$repo_dir/.worktree/rm-wt-branch"

  # answer y to remove worktree, n to keep branch
  echo "y\nn" | wt_rm rm-wt-branch >/dev/null 2>&1

  assert_dir_not_exists "$repo_dir/.worktree/rm-wt-branch"

  # branch should still exist
  local branches
  branches=$(git branch --list rm-wt-branch)
  assert_not_empty "$branches"
}

function test_wt_rm_removes_branch() {
  test_case_title
  create_test_repo

  local repo_dir="$HOME/test-repo"

  wt rm-both-branch >/dev/null 2>&1
  cd "$repo_dir"

  # answer y to both prompts (remove worktree + delete branch)
  echo "y\ny" | wt_rm rm-both-branch >/dev/null 2>&1

  assert_dir_not_exists "$repo_dir/.worktree/rm-both-branch"

  # branch should be gone
  local branches
  branches=$(git branch --list rm-both-branch)
  assert_empty "$branches"
}

function test_wt_rm_from_inside_worktree() {
  test_case_title
  create_test_repo

  local repo_dir="$HOME/test-repo"

  # create the worktree and manually cd into it
  wt inside-branch >/dev/null 2>&1
  cd "$repo_dir/.worktree/inside-branch"

  # remove while cwd is inside the worktree — function should cd out first
  echo "y\nn" | wt_rm inside-branch >/dev/null 2>&1

  assert_dir_not_exists "$repo_dir/.worktree/inside-branch"
}

function test_wt_rm_decline() {
  test_case_title
  create_test_repo

  local repo_dir="$HOME/test-repo"

  wt decline-branch >/dev/null 2>&1
  cd "$repo_dir"

  # answer n to first prompt — nothing should be removed
  echo "n" | wt_rm decline-branch >/dev/null 2>&1

  assert_dir_exists "$repo_dir/.worktree/decline-branch"
}

setup
run_test test_wt_no_args
run_test test_wt_new_branch
run_test test_wt_existing_branch
run_test test_wt_reenter_existing
run_test test_wt_not_git_repo
run_test test_wt_slash_branch
run_test test_wt_rm_no_args
run_test test_wt_rm_nonexistent
run_test test_wt_rm_removes_worktree
run_test test_wt_rm_removes_branch
run_test test_wt_rm_from_inside_worktree
run_test test_wt_rm_decline
finish_tests
cleanup
