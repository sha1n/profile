#!/usr/bin/env zsh

source "$SHA1N_PROFILE_TESTS_HOME/sandbox.zsh"
source "$SHA1N_PROFILE_TESTS_HOME/install_helpers.zsh"
repo_mise_dir="$profile_home/config/mise"
repo_config="$repo_mise_dir/profile.toml"
link="$HOME/.config/mise/conf.d/profile.toml"

warnings_about_link() {
  print -r -- "$1" | grep 'WARNING' | grep -F 'profile.toml'
}

# Prints "key=value" for each key of the given TOML table, with quotes and spaces removed.
table_entries() {
  awk -v table="[$2]" '
    /^[ \t]*\[/ { in_table = ($0 == table); next }
    in_table && /^[A-Za-z0-9_-]+[ \t]*=/ {
      key = $0; sub(/[ \t]*=.*/, "", key)
      value = $0; sub(/^[^=]*=[ \t]*/, "", value); gsub(/[" \t]/, "", value)
      print key "=" value
    }
  ' "$1" 2>/dev/null | sort
}

function test_repo_config() {
  test_case_title

  assert_equal "$(cd "$repo_mise_dir" && find . -mindepth 1 | sort | tr '\n' ' ')" "./profile.toml "
  assert_equal "$(table_entries "$repo_config" settings | tr '\n' ' ')" "idiomatic_version_file_enable_tools=[node,python] "
  local entries="$(table_entries "$repo_config" tools)"
  assert_equal "$(print -r -- "$entries" | cut -d= -f1 | tr '\n' ' ')" "go java maven node python "
  print -r -- "check: every [tools] value is a major or major.minor line"
  assert_empty "$(print -r -- "$entries" | grep -Ev '^[^=]+=[0-9]+(\.[0-9]+)?$')"
}

function test_first_and_second_run_link_config() {
  test_case_title
  reset_home

  run_install_with_rc
  local first_rc="$install_rc"
  local first_target="$(readlink "$link")"
  local output="$(run_install)"

  assert_equal "$first_rc" "0"
  assert_equal "$first_target" "$repo_config"
  assert_equal "$(readlink "$link")" "$repo_config"
  assert_empty "$(warnings_about_link "$output")"
}

function test_regular_file_at_target_kept_with_warning() {
  test_case_title
  reset_home
  mkdir -p "${link:h}"
  print -n "MINE" >"$link"

  run_install_with_rc
  local output="$install_out"

  local is_link=false
  [[ -L "$link" ]] && is_link=true
  assert_equal "$install_rc" "0"
  assert_equal "$is_link" "false"
  assert_equal "$(cat "$link")" "MINE"
  assert_not_empty "$(warnings_about_link "$output")"
}

# A link failure names its path, lets the remaining steps run, and fails the install.
function test_link_failure_fails_install() {
  test_case_title

  local row blocker named has_link stub_dir
  # <what blocks the link>|<path that the error names>
  for row in 'mise-file|.config/mise/conf.d' 'ln-stub|conf.d/profile.toml'; do
    IFS='|' read -r blocker named <<<"$row"
    print -r -- "row: $blocker"
    reset_home
    mkdir -p "$HOME/.config"
    stub_dir="$(mktemp -d)"
    case "$blocker" in
      mise-file) print -n "FILE" >"$HOME/.config/mise" ;;
      ln-stub) write_failing_stub "$stub_dir" ln conf.d/profile.toml ;;
    esac

    run_install_with_rc "$stub_dir"
    has_link=false
    [[ -L "$link" ]] && has_link=true
    # Removed before asserting because a failed assertion exits the case.
    rm -rf "$stub_dir"

    assert_equal "$install_rc" "1"
    assert_not_empty "$(errors_naming "$install_out" "$named")"
    assert_contains "$install_out" "Bytecode"
    assert_equal "$has_link" "false"
  done
}

setup
run_test test_repo_config
run_test test_first_and_second_run_link_config
run_test test_regular_file_at_target_kept_with_warning
run_test test_link_failure_fails_install
cleanup
finish_tests
