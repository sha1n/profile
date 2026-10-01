#!/usr/bin/env zsh

source "$SHA1N_PROFILE_TESTS_HOME/sandbox.zsh"

install_profile() {
  source "$SHA1N_PROFILE_TESTS_HOME/../install.sh"
  source "$SHA1N_PROFILE_TESTS_HOME/../load.zsh"
}

create_repo() {
  local repo_dir="$1" branch="$2"
  git init -q -b "$branch" "$repo_dir"
  git -C "$repo_dir" config user.email "test@example.com"
  git -C "$repo_dir" config user.name "Test"
  git -C "$repo_dir" commit -q --allow-empty -m "initial commit"
}

function test_default_branch_from_origin_head() {
  test_case_title
  create_repo "$HOME/upstream" develop
  git clone -q "$HOME/upstream" "$HOME/clone"
  cd "$HOME/clone"
  git checkout -q -b feature

  assert_equal "$(__profile_git_default_branch)" "develop"
}

function test_default_branch_local_main() {
  test_case_title
  create_repo "$HOME/repo-main" main
  cd "$HOME/repo-main"
  git checkout -q -b feature

  assert_equal "$(__profile_git_default_branch)" "main"
}

function test_default_branch_local_master() {
  test_case_title
  create_repo "$HOME/repo-master" master
  cd "$HOME/repo-master"
  git checkout -q -b feature

  assert_equal "$(__profile_git_default_branch)" "master"
}

function test_default_branch_prefers_main_over_master() {
  test_case_title
  create_repo "$HOME/repo-both" master
  cd "$HOME/repo-both"
  git branch main

  assert_equal "$(__profile_git_default_branch)" "main"
}

function test_default_branch_unknown() {
  test_case_title
  create_repo "$HOME/repo-other" develop
  cd "$HOME/repo-other"

  assert_exit_code 1 "__profile_git_default_branch"
}

function test_default_branch_not_git_repo() {
  test_case_title
  mkdir -p "$HOME/not-a-repo"
  cd "$HOME/not-a-repo"

  assert_exit_code 1 "__profile_git_default_branch"
}

function test_with_default_branch_reports_error_on_stderr() {
  test_case_title
  create_repo "$HOME/repo-stderr" develop
  cd "$HOME/repo-stderr"

  local stderr
  stderr=$(__profile_git_with_default_branch echo ran 2>&1 >/dev/null)
  assert_contains "$stderr" "git remote set-head origin --auto"
}

function test_with_default_branch_appends_branch() {
  test_case_title
  create_repo "$HOME/repo-append" main
  cd "$HOME/repo-append"

  assert_equal "$(__profile_git_with_default_branch echo checkout)" "checkout main"
}

function test_with_default_branch_skips_command_on_failure() {
  test_case_title
  create_repo "$HOME/repo-skip" develop
  cd "$HOME/repo-skip"

  local output
  output=$(__profile_git_with_default_branch echo ran 2>/dev/null)
  assert_exit_code 1 "__profile_git_with_default_branch echo ran"
  assert_empty "$output"
}

function test_trunk_checks_out_default_branch() {
  test_case_title
  create_repo "$HOME/repo-trunk" main
  cd "$HOME/repo-trunk"
  git checkout -q -b feature

  eval trunk >/dev/null 2>&1
  assert_equal "$(git branch --show-current)" "main"
}

function test_trunk_aliases_use_default_branch() {
  test_case_title

  assert_contains "$(alias trunk)" "__profile_git_with_default_branch git checkout"
  assert_contains "$(alias pull_trunk)" "__profile_git_with_default_branch git pull --rebase --autostash origin"
  assert_contains "$(alias pullt)" "__profile_git_with_default_branch git pull --ff-only --recurse-submodules origin"
}

function test_master_aliases_removed() {
  test_case_title

  assert_exit_code 1 "alias master"
  assert_exit_code 1 "alias pull_master"
  assert_exit_code 1 "alias pullmr"
}

setup
install_profile
run_test test_default_branch_from_origin_head
run_test test_default_branch_local_main
run_test test_default_branch_local_master
run_test test_default_branch_prefers_main_over_master
run_test test_default_branch_unknown
run_test test_default_branch_not_git_repo
run_test test_with_default_branch_reports_error_on_stderr
run_test test_with_default_branch_appends_branch
run_test test_with_default_branch_skips_command_on_failure
run_test test_trunk_checks_out_default_branch
run_test test_trunk_aliases_use_default_branch
run_test test_master_aliases_removed
cleanup
finish_tests
