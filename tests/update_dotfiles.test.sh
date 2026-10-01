#!/usr/bin/env zsh

source "$SHA1N_PROFILE_TESTS_HOME/sandbox.zsh"
nvim_src="$profile_home/config/nvim"
nvim_link="$HOME/.config/nvim"

run_update() {
  update_out="$(env -i HOME="$HOME" PATH="/usr/bin:/bin" TERM=dumb zsh "$profile_home/update_dotfiles.sh" 2>&1)"
  update_rc="$?"
}

warnings_about_nvim() {
  print -r -- "$1" | grep 'WARNING' | grep -F '.config/nvim'
}

function test_empty_target_linked() {
  test_case_title
  reset_home

  run_update

  assert_equal "$update_rc" "0"
  assert_equal "$(readlink "$nvim_link")" "$nvim_src"
  assert_empty "$(warnings_about_nvim "$update_out")"
}

function test_repo_link_idempotent() {
  test_case_title
  reset_home
  mkdir -p "${nvim_link:h}"
  ln -s "$nvim_src" "$nvim_link"

  run_update

  assert_equal "$update_rc" "0"
  assert_equal "$(readlink "$nvim_link")" "$nvim_src"
  assert_empty "$(warnings_about_nvim "$update_out")"
}

function test_regular_file_at_target_kept_with_warning() {
  test_case_title
  reset_home
  mkdir -p "${nvim_link:h}"
  print -n "MINE" >"$nvim_link"

  run_update

  local is_link=false
  [[ -L "$nvim_link" ]] && is_link=true
  assert_equal "$update_rc" "0"
  assert_equal "$is_link" "false"
  assert_equal "$(cat "$nvim_link")" "MINE"
  assert_not_empty "$(warnings_about_nvim "$update_out")"
}

function test_foreign_link_at_target_kept_with_warning() {
  test_case_title
  reset_home
  mkdir -p "${nvim_link:h}" "$HOME/foreign-nvim"
  ln -s "$HOME/foreign-nvim" "$nvim_link"

  run_update

  assert_equal "$update_rc" "0"
  assert_equal "$(readlink "$nvim_link")" "$HOME/foreign-nvim"
  assert_not_empty "$(warnings_about_nvim "$update_out")"
}

function test_directory_at_target_kept_with_warning() {
  test_case_title
  reset_home
  mkdir -p "$nvim_link"
  print -n "MINE" >"$nvim_link/init.lua"

  run_update

  local is_link=false
  [[ -L "$nvim_link" ]] && is_link=true
  assert_equal "$update_rc" "0"
  assert_equal "$is_link" "false"
  assert_equal "$(cat "$nvim_link/init.lua")" "MINE"
  assert_not_empty "$(warnings_about_nvim "$update_out")"
}

setup
run_test test_empty_target_linked
run_test test_repo_link_idempotent
run_test test_regular_file_at_target_kept_with_warning
run_test test_foreign_link_at_target_kept_with_warning
run_test test_directory_at_target_kept_with_warning
cleanup
finish_tests
