#!/usr/bin/env zsh

source "$SHA1N_PROFILE_TESTS_HOME/sandbox.zsh"
bootstrap_script="$profile_home/bootstrap.sh"
repo_dir="$HOME/code/profile"
repo_url="https://github.com/sha1n/profile.git"
submodule_call="git -c url.https://github.com/.insteadOf=git@github.com: -C $repo_dir submodule update --init"
# Captured before any case narrows PATH, so the child shell and the stubs always find zsh.
zsh_bin="$(command -v zsh)"
# /usr/bin holds a real sudo, curl and git, so the stub dir must stay first on PATH.
system_path="/usr/bin:/bin"
# TERM=dumb drops some sequences, so a colour terminal type makes the section escapes present.
section_term="xterm-256color"

section_background() {
  env -i HOME="$HOME" PATH="$system_path" TERM="$section_term" "$zsh_bin" -fc 'print -nP "%K{blue}"'
}

# Writes a zsh stub that appends "CALL <label> <args>" to <stub_dir>/events, the file
# that also receives the output of bootstrap.sh, so one file holds the order of section
# titles and steps. With <track_stdin>=yes the line ends with "|stdin=devnull" or
# "|stdin=other": fd 0 and /dev/null are compared by device number through zsh/stat,
# which works the same on macOS and Linux; the runner feeds a pipe, whose rdev is 0.
write_stub() {
  local target="$1" label="$2" track_stdin="$3" body="$4"
  {
    print -r -- "#!$zsh_bin -f"
    print -r -- "stub_dir=${(q)stub_dir}"
    print -r -- "label=${(q)label}"
    print -r -- "track_stdin=$track_stdin"
    cat <<'EOF'
zmodload zsh/stat
line="CALL $label${*:+ $*}"
if [[ "$track_stdin" == yes ]]; then
  stdin_kind=other
  [[ "$(zstat -f 0 +rdev 2>/dev/null)" == "$(zstat +rdev /dev/null)" ]] && stdin_kind=devnull
  line+="|stdin=$stdin_kind"
fi
print -r -- "$line" >>"$stub_dir/events"
EOF
    print -r -- "$body"
  } >"$target"
  chmod +x "$target"
}

# Sets the global stub_dir to a new directory with a stub for each outside command, and
# a fake repo that the stub `git clone` copies to the clone target. The exit code of a
# step is in <stub_dir>/<step>_exit (install, profile, clone), and uname prints
# <stub_dir>/kernel.
new_stub_dir() {
  stub_dir="$(mktemp -d "${TMPDIR:-/tmp}/bootstrap_test_stubs.XXXXXX")"
  local fake_repo="$stub_dir/fake_repo" step
  print -r -- "Darwin" >"$stub_dir/kernel"
  for step in install profile clone; do
    print -r -- "0" >"$stub_dir/${step}_exit"
  done

  print -r -- "#!/bin/sh" >"$stub_dir/uname"
  print -r -- "cat ${(q)stub_dir}/kernel" >>"$stub_dir/uname"
  # curl only fetches the installer text, so it logs nothing; the text runs the installer stub.
  print -r -- "#!/bin/sh" >"$stub_dir/curl"
  print -r -- "echo 'exec ${(q)zsh_bin} -f ${(q)stub_dir}/installer'" >>"$stub_dir/curl"
  chmod +x "$stub_dir/uname" "$stub_dir/curl"

  write_stub "$stub_dir/sudo" "sudo" no 'exit 0'
  write_stub "$stub_dir/sleep" "sleep" no 'exit 0'
  write_stub "$stub_dir/brew" "brew" no \
    '[[ "$1" == shellenv ]] && print -r -- "export PATH=\"$stub_dir:\$PATH\""; exit 0'
  write_stub "$stub_dir/git" "git" yes '
if [[ "$1" == clone ]]; then
  (( $(<"$stub_dir/clone_exit") == 0 )) || exit "$(<"$stub_dir/clone_exit")"
  cp -R "$stub_dir/fake_repo" "$3" || exit 1
fi
exit 0'
  write_stub "$stub_dir/installer" "installer" yes \
    'print -r -- "NONINTERACTIVE=$NONINTERACTIVE" >"$stub_dir/installer_env"; exit 0'

  mkdir -p "$fake_repo/scripts"
  write_stub "$fake_repo/install.sh" "install.sh" yes 'exit "$(<"$stub_dir/install_exit")"'
  write_stub "$fake_repo/scripts/profile" "profile" yes \
    'print -r -- "$#" >"$stub_dir/profile_argc"; exit "$(<"$stub_dir/profile_exit")"'
}

existing_checkout() {
  mkdir -p "${repo_dir:h}"
  cp -R "$stub_dir/fake_repo" "$repo_dir"
}

# bootstrap.sh checks /opt/homebrew/bin/brew first, which is the real Homebrew on a
# developer Mac, so every run replaces the lookup. With <brew>=found it returns the stub;
# with <brew>=missing the first lookup fails, as on a Mac without Homebrew, and later
# lookups find the stub.
brew_override() {
  if [[ "$1" == found ]]; then
    print -r -- "__bootstrap_brew_bin() { print -r -- ${(q)stub_dir}/brew; }"
  else
    print -r -- "__bootstrap_brew_bin() {
      local counter=${(q)stub_dir}/brew_bin_lookups
      print -r -- x >>\"\$counter\"
      (( \$(wc -l <\"\$counter\") > 1 )) || return 1
      print -r -- ${(q)stub_dir}/brew
    }"
  fi
}

# Runs __bootstrap_main <args> in a fresh env -i child whose stdin is a pipe full of script
# text, as in `curl ... | zsh -s`, with Homebrew <brew> (found or missing). After main
# returns, the child records its zshexit_functions and its live child processes, before
# its own exit could stop them. Output goes to files, not a pipe, so a leftover background
# process cannot hold a command-substitution pipe open.
# Then reads the results into globals, stops any leftover child and clears HOME, because
# a failed assertion exits the case.
run_bootstrap_main() {
  local brew="$1"
  shift
  print -rl -- "echo LEAKED"{1..50} | env -i HOME="$HOME" PATH="$stub_dir:$system_path" TERM="$section_term" \
    "$zsh_bin" -f -c '
      b="$1"; o="$2"; d="$3"; shift 3
      source "$b" || exit 99
      eval "$o"
      __bootstrap_main "$@"
      rc=$?
      print -r -- "${#zshexit_functions}" >"$d/zshexit_count"
      pgrep -P $$ >"$d/children"
      exit $rc' \
    _ "$bootstrap_script" "$(brew_override "$brew")" "$stub_dir" "$@" >>"$stub_dir/events" 2>&1
  rc="$?"

  children="$(cat "$stub_dir/children" 2>/dev/null)"
  local pid
  for pid in ${(f)children}; do
    [[ "$pid" == <-> ]] && kill "$pid" 2>/dev/null
  done
  events="$(timeline)"
  after_next_steps="$(sed -n '/Next steps/,$p' "$stub_dir/events")"
  zshexit_count="$(cat "$stub_dir/zshexit_count" 2>/dev/null)"
  installer_env="$(cat "$stub_dir/installer_env" 2>/dev/null)"
  profile_argc="$(cat "$stub_dir/profile_argc" 2>/dev/null)"
  home_entries="$(ls -A "$HOME")"
  rm -rf "${stub_dir:?}"
  reset_home
}

# Prints the events in order: "CALL ..." lines as logged, and each section title as
# "TITLE <text>" with its escape sequences removed. Other output lines are left out.
timeline() {
  emulate -L zsh
  setopt extendedglob
  local background="$(section_background)" line text
  [[ -f "$stub_dir/events" ]] || return 0
  while IFS= read -r line; do
    if [[ "$line" == CALL\ * ]]; then
      print -r -- "$line"
    elif [[ "$line" == *"$background"* ]]; then
      text="${line//$'\e'\[[0-9;]#m/}"
      text="${${text##[[:space:]]#}%%[[:space:]]#}"
      print -r -- "TITLE $text"
    fi
  done <"$stub_dir/events"
}

# The section function is a copy of __profile_log_section, so both must print the same bytes.
function test_sourcing_runs_no_step() {
  test_case_title
  reset_home
  new_stub_dir

  local -a result=("${(@f)$(env -i HOME="$HOME" PATH="$stub_dir:$system_path" TERM="$section_term" \
    "$zsh_bin" -f -c 'source "$1" || exit 99; whence -w __bootstrap_main; __bootstrap_log_section "Clone 100%"' \
    _ "$bootstrap_script" </dev/null 2>/dev/null)}")
  local lib_title="$(env -i HOME="$HOME" PATH="$system_path" TERM="$section_term" \
    "$zsh_bin" -f -c 'source "$1" || exit 99; __profile_log_section "Clone 100%"' _ "$profile_home/scripts/lib.zsh" 2>&1)"
  local events="$(timeline)"
  local home_entries="$(ls -A "$HOME")"

  # Removed before asserting because a failed assertion exits the case.
  rm -rf "${stub_dir:?}"
  reset_home

  assert_equal "${result[1]}" "__bootstrap_main: function"
  assert_empty "$events"
  assert_equal "$home_entries" "$fingerprint"
  assert_not_empty "$lib_title"
  assert_equal "${(F)result[2,-1]}" "$lib_title"
}

function test_linux_exits_1_before_any_step() {
  test_case_title
  reset_home
  new_stub_dir
  print -r -- "Linux" >"$stub_dir/kernel"
  run_bootstrap_main missing essentials

  assert_equal "$rc" "1"
  assert_empty "$events"
  assert_equal "$home_entries" "$fingerprint"
}

# A full run on a Mac without Homebrew. It must run to the end although stdin holds
# more script text, and leave no exit hook or background process (such as a sudo keep-alive).
function test_new_machine() {
  test_case_title
  reset_home
  new_stub_dir
  run_bootstrap_main missing essentials dev

  assert_equal "$rc" "0"
  assert_equal "$events" "TITLE Homebrew
CALL sudo -v
CALL installer|stdin=devnull
CALL brew shellenv
TITLE Clone
CALL git clone $repo_url $repo_dir|stdin=devnull
TITLE Submodules
CALL $submodule_call|stdin=devnull
CALL install.sh|stdin=devnull
CALL profile install essentials dev|stdin=devnull
TITLE Next steps"
  assert_equal "$installer_env" "NONINTERACTIVE=1"
  assert_equal "$zshexit_count" "0"
  assert_empty "$children"
  assert_contains "$after_next_steps" "gh auth login"
  assert_contains "$after_next_steps" "gh ssh-key add"
  assert_contains "$after_next_steps" "Settings Sync"
}

# A second run skips the Homebrew install and the clone, still updates the submodules,
# passes its arguments to profile install unchanged, and exits with its exit code.
# The manual steps follow only a successful profile install.
function test_existing_checkout() {
  test_case_title

  local row profile_exit args expected
  local -a words
  # <profile install exit code>|<bootstrap.sh arguments, shell-quoted>
  for row in "0|'two words' bogus" '1|' '2|bogus'; do
    IFS='|' read -r profile_exit args <<<"$row"
    words=(${(Q)${(z)args}})
    reset_home
    new_stub_dir
    existing_checkout
    print -r -- "$profile_exit" >"$stub_dir/profile_exit"
    run_bootstrap_main found "${words[@]}"

    expected="TITLE Homebrew
CALL brew shellenv
TITLE Clone
TITLE Submodules
CALL $submodule_call|stdin=devnull
CALL install.sh|stdin=devnull
CALL profile install${words:+ ${words[*]}}|stdin=devnull"
    (( profile_exit == 0 )) && expected+=$'\n'"TITLE Next steps"

    print -r -- "row: profile install exits with $profile_exit, bootstrap.sh $args"
    assert_equal "$rc" "$profile_exit"
    assert_equal "$events" "$expected"
    assert_equal "$profile_argc" "$(( 1 + ${#words} ))"
  done
}

function test_failing_step_stops_the_run() {
  test_case_title

  local failing expected
  for failing in clone install; do
    reset_home
    new_stub_dir
    expected="TITLE Homebrew
CALL brew shellenv
TITLE Clone"
    if [[ "$failing" == clone ]]; then
      print -r -- "128" >"$stub_dir/clone_exit"
      expected+=$'\n'"CALL git clone $repo_url $repo_dir|stdin=devnull"
    else
      existing_checkout
      print -r -- "3" >"$stub_dir/install_exit"
      expected+=$'\n'"TITLE Submodules
CALL $submodule_call|stdin=devnull
CALL install.sh|stdin=devnull"
    fi
    run_bootstrap_main found essentials

    print -r -- "row: $failing fails"
    assert_equal "$rc" "1"
    assert_equal "$events" "$expected"
  done
}

setup
run_test test_sourcing_runs_no_step
run_test test_linux_exits_1_before_any_step
run_test test_new_machine
run_test test_existing_checkout
run_test test_failing_step_stops_the_run
cleanup
finish_tests
