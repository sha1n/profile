#!/usr/bin/env zsh

source "$SHA1N_PROFILE_TESTS_HOME/sandbox.zsh"
load_script="$profile_home/load.zsh"
# Captured before any case narrows PATH, so the child shell is always found.
zsh_bin="$(command -v zsh)"
# Excludes Homebrew and other user prefixes so the real mise/fzf cannot be found.
system_path="/usr/bin:/bin"

# Each case loads the profile in a fresh child shell so stubs and PATH changes
# cannot leak between cases or into the test runner. -f keeps the child from
# reading rc files outside the sandbox.
# env -i so variables exported by the caller's own profile (e.g. NVM_DIR,
# BAZEL_*) cannot mask what load.zsh itself exports.
load_and_eval() {
  local search_path="$1" snippet="$2"
  env -i HOME="$HOME" PATH="$search_path" TERM=dumb \
    "$zsh_bin" -f -c 'source "$1"; eval "$2"' _ "$load_script" "$snippet"
}

eval_load_eval() {
  local search_path="$1" before="$2" after="$3" term="${4:-dumb}"
  env -i HOME="$HOME" PATH="$search_path" TERM="$term" \
    "$zsh_bin" -f -c 'eval "$2"; source "$1"; eval "$3"' _ "$load_script" "$before" "$after"
}

load_stderr() {
  local search_path="$1" term="${2:-dumb}"
  env -i HOME="$HOME" PATH="$search_path" TERM="$term" \
    "$zsh_bin" -f -c 'source "$1" 2>&1 >/dev/null' _ "$load_script"
}

new_stub_dir() {
  mktemp -d "${TMPDIR:-/tmp}/env_test_stubs.XXXXXX"
}

write_starship_stub() {
  local stub_dir="$1" init_status="$2"
  cat >"$stub_dir/starship" <<EOF
#!/bin/sh
if [ "\$1" = "init" ] && [ "\$2" = "zsh" ]; then
  [ $init_status -eq 0 ] || exit $init_status
  echo "PROMPT='starship-stub> '"
fi
EOF
  chmod +x "$stub_dir/starship"
}

function test_pip_require_virtualenv() {
  test_case_title

  local exported="$(load_and_eval "$system_path" 'print -r -- "${(t)PIP_REQUIRE_VIRTUALENV}"')"
  local value="$(load_and_eval "$system_path" 'print -r -- "$PIP_REQUIRE_VIRTUALENV"')"

  assert_equal "$value" "true"
  assert_contains "$exported" "export"
}

function test_homebrew_bundle_file() {
  test_case_title

  local exported="$(load_and_eval "$system_path" 'print -r -- "${(t)HOMEBREW_BUNDLE_FILE}"')"
  local value="$(load_and_eval "$system_path" 'print -r -- "$HOMEBREW_BUNDLE_FILE"')"
  local profiles_type="$(load_and_eval "$system_path" 'print -r -- "${(t)HOMEBREW_PROFILE_INSTALL_PROFILES}"')"

  assert_equal "$value" "$profile_home/brew/Brewfile"
  assert_contains "$exported" "export"
  assert_equal "$profiles_type" ""
}

function test_starship_config() {
  test_case_title

  local exported="$(load_and_eval "$system_path" 'print -r -- "${(t)STARSHIP_CONFIG}"')"
  local value="$(load_and_eval "$system_path" 'print -r -- "$STARSHIP_CONFIG"')"

  assert_equal "$value" "$profile_home/config/starship.toml"
  assert_contains "$exported" "export"
  assert_file_exists "$value"
}

function test_go_bin_on_path() {
  test_case_title

  local loaded_path="$(load_and_eval "$system_path" 'print -r -- "$PATH"')"

  assert_contains ":$loaded_path:" ":$HOME/go/bin:"
}

function test_mise_activated() {
  test_case_title

  local stub_dir="$(new_stub_dir)"
  cat >"$stub_dir/mise" <<'EOF'
#!/bin/sh
if [ "$1" = "activate" ] && [ "$2" = "zsh" ]; then
  echo 'export __MISE_STUB=1'
fi
EOF
  chmod +x "$stub_dir/mise"

  local marker="$(load_and_eval "$stub_dir:$system_path" 'print -r -- "$__MISE_STUB"')"

  # Removed before asserting because a failed assertion exits the case.
  rm -rf "$stub_dir"

  assert_equal "$marker" "1"
}

function test_mise_absent_is_silent() {
  test_case_title

  local stub_dir="$(new_stub_dir)"

  local err="$(load_stderr "$stub_dir:$system_path")"

  rm -rf "$stub_dir"

  assert_empty "$err"
}

function test_fzf_without_zsh_flag_is_silent() {
  test_case_title

  local stub_dir="$(new_stub_dir)"
  cat >"$stub_dir/fzf" <<'EOF'
#!/bin/sh
if [ "$1" = "--zsh" ]; then
  exit 1
fi
EOF
  chmod +x "$stub_dir/fzf"

  local err="$(load_stderr "$stub_dir:$system_path")"

  rm -rf "$stub_dir"

  assert_empty "$err"
}

function test_prompt_not_set_without_starship() {
  test_case_title

  local before="PROMPT='sentinel> '; RPROMPT='right-sentinel'"
  # A theme can assign the prompt from a precmd hook, which a non-interactive
  # shell never runs, so run the hooks as an interactive shell would first.
  local run_hooks='local hook; for hook in $precmd_functions; do $hook; done 2>/dev/null'
  local prompt="$(eval_load_eval "$system_path" "$before" "$run_hooks"'; print -r -- "$PROMPT"')"
  local rprompt="$(eval_load_eval "$system_path" "$before" "$run_hooks"'; print -r -- "$RPROMPT"')"

  assert_equal "$prompt" "sentinel> "
  assert_equal "$rprompt" "right-sentinel"
}

function test_starship_init_sets_prompt() {
  test_case_title

  local stub_dir="$(new_stub_dir)"
  write_starship_stub "$stub_dir" 0

  local prompt="$(eval_load_eval "$stub_dir:$system_path" "PROMPT='sentinel> '" 'print -r -- "$PROMPT"' xterm-256color)"

  rm -rf "$stub_dir"

  assert_equal "$prompt" "starship-stub> "
}

function test_starship_skipped_on_dumb_terminal() {
  test_case_title

  local stub_dir="$(new_stub_dir)"
  write_starship_stub "$stub_dir" 0

  local prompt="$(eval_load_eval "$stub_dir:$system_path" "PROMPT='sentinel> '" 'print -r -- "$PROMPT"' dumb)"

  rm -rf "$stub_dir"

  assert_equal "$prompt" "sentinel> "
}

function test_starship_init_failure_is_silent() {
  test_case_title

  local stub_dir="$(new_stub_dir)"
  write_starship_stub "$stub_dir" 1

  local prompt="$(eval_load_eval "$stub_dir:$system_path" "PROMPT='sentinel> '" 'print -r -- "$PROMPT"' xterm-256color)"
  local err="$(load_stderr "$stub_dir:$system_path" xterm-256color)"

  rm -rf "$stub_dir"

  assert_equal "$prompt" "sentinel> "
  assert_empty "$err"
}

function test_no_theme_functions() {
  test_case_title

  local kinds="$(load_and_eval "$system_path" 'whence -w prompt_end build_prompt')"

  assert_not_contains "$kinds" ": function"
}

setup
run_test test_pip_require_virtualenv
run_test test_homebrew_bundle_file
run_test test_starship_config
run_test test_go_bin_on_path
run_test test_mise_activated
run_test test_mise_absent_is_silent
run_test test_fzf_without_zsh_flag_is_silent
run_test test_prompt_not_set_without_starship
run_test test_starship_init_sets_prompt
run_test test_starship_skipped_on_dumb_terminal
run_test test_starship_init_failure_is_silent
run_test test_no_theme_functions
cleanup
finish_tests
