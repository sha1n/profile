#!/usr/bin/env zsh

source "$SHA1N_PROFILE_TESTS_HOME/sandbox.zsh"
profile_script="$profile_home/scripts/profile"
load_script="$profile_home/load.zsh"
# Captured before any case narrows PATH, so the stubs always find zsh.
zsh_bin="$(command -v zsh)"
# Holds no brew or mise on a developer Mac or a CI runner, so only the stubs can run.
system_path="/usr/bin:/bin"
# TERM=dumb drops some sequences, so a colour terminal type makes the section escapes present.
section_term="xterm-256color"
stub_dir="$HOME/stubs"
stub_bin="$stub_dir/bin"
# profile resolves its repo from its own path with :A, so the fake repo holds a copy
# of scripts/, not a link to it.
fake_repo="$HOME/fake"
stub_branch="feature-x"

section_background() {
  env -i HOME="$HOME" PATH="$system_path" TERM="$section_term" "$zsh_bin" -fc 'print -nP "%K{blue}"'
}

# Each stub appends its call to <stub_dir>/calls and one line of details to
# <stub_dir>/details: the call, its working directory, the value of
# HOMEBREW_PROFILE_INSTALL_PROFILES, and whether stdin is /dev/null. The stdin check
# compares the device number of fd 0 with that of /dev/null through zsh/stat, which
# works the same on macOS and Linux; the runner feeds a pipe, whose rdev is 0.
# Every stub that stands for a step prints "STUB <call>" to stdout, so the order of
# section titles and steps can be read from the output.
write_stub() {
  local target="$1" body="$2"
  {
    print -r -- "#!$zsh_bin -f"
    print -r -- "stub_dir=${(q)stub_dir}"
    cat <<'EOF'
zmodload zsh/stat
call="${0:t}${*:+ $*}"
stdin_kind=other
[[ "$(zstat -f 0 +rdev 2>/dev/null)" == "$(zstat +rdev /dev/null)" ]] && stdin_kind=devnull
profiles_value="${HOMEBREW_PROFILE_INSTALL_PROFILES-<unset>}"
print -r -- "$call" >>"$stub_dir/calls"
print -r -- "$call|cwd=$(pwd -P)|profiles=$profiles_value|stdin=$stdin_kind" >>"$stub_dir/details"
EOF
    print -r -- "$body"
  } >"$target"
  chmod +x "$target"
}

# The exit code of the stubbed step <name> (git_pull, git_submodule, brew_bundle, mise,
# brew_dry, brew_force, mise_dry, mise_yes).
stub_exit() {
  print -r -- "$2" >"$stub_dir/$1_exit"
}

# Makes the dry run of <tool> (brew or mise) print a list and exit with 1. The Homebrew
# output has a line before its first `Would ` line, a `--force` hint and a question,
# which profile cleanup must not print.
stub_items() {
  case "$1" in
    brew)
      print -rl -- "==> BREW-PREAMBLE" "Would uninstall casks:" "orphan-cask" \
        "Would uninstall formulae:" "orphan-formula    other-formula" \
        'Run `brew bundle cleanup --force` to make these changes.' \
        "Do you want to proceed? [y/n]" >"$stub_dir/brew_dry_out" ;;
    mise) print -r -- "would remove node@18.20.0" >"$stub_dir/mise_dry_out" ;;
  esac
  stub_exit "$1_dry" 1
}

# The real Brewfile, so the scripts read the list of profiles that ships in the repo.
prepare_case() {
  reset_home
  mkdir -p "$stub_bin" "$fake_repo/brew"
  cp -R "$profile_home/scripts" "$fake_repo/scripts"
  cp "$profile_home/brew/Brewfile" "$fake_repo/brew/Brewfile"

  local step
  for step in git_pull git_submodule brew_bundle mise brew_dry brew_force mise_dry mise_yes; do
    stub_exit "$step" 0
  done

  write_stub "$stub_bin/git" '
[[ "$1" == -C ]] && shift 2
case "$1" in
  branch)
    [[ "$2" == --show-current ]] && print -r -- "'"$stub_branch"'"
    exit 0 ;;
  pull|submodule)
    print -r -- "STUB $call"
    exit "$(<"$stub_dir/git_$1_exit")" ;;
esac
exit 0'
  # A cleanup or prune call prints <step>_out, if any, instead of a STUB line.
  write_stub "$stub_bin/brew" '
if [[ "$1" == bundle && "$2" == cleanup ]]; then
  step=brew_dry
  (( ${@[(Ie)--force]} )) && step=brew_force
  [[ -f "$stub_dir/${step}_out" ]] && cat "$stub_dir/${step}_out"
  exit "$(<"$stub_dir/${step}_exit")"
fi
print -r -- "STUB $call"
if [[ "$1" == bundle ]]; then
  [[ -f "$stub_dir/pending_mise" ]] && mv "$stub_dir/pending_mise" "$stub_dir/bin/mise"
  exit "$(<"$stub_dir/brew_bundle_exit")"
fi
exit 0'
  write_stub "$stub_bin/mise" '
if [[ "$1" == prune ]]; then
  step=mise_yes
  (( ${@[(Ie)--dry-run-code]} )) && step=mise_dry
  [[ -f "$stub_dir/${step}_out" ]] && cat "$stub_dir/${step}_out"
  exit "$(<"$stub_dir/${step}_exit")"
fi
print -r -- "STUB $call"
exit "$(<"$stub_dir/mise_exit")"'
  # profile install must not run install.sh; a stub in the fake repo records any call.
  write_stub "$fake_repo/install.sh" 'exit 0'

  repo="${fake_repo:A}"
  brewfile="$repo/brew/Brewfile"
}

# The call that each step makes, by short name.
step_call() {
  case "$1" in
    pull) print -r -- "git -C $repo pull origin $stub_branch" ;;
    submodule) print -r -- "git -C $repo submodule update --init --recursive" ;;
    brew) print -r -- "brew bundle --no-upgrade --file $brewfile" ;;
    mise) print -r -- "mise install" ;;
    brew_dry) print -r -- "brew bundle cleanup --file $brewfile" ;;
    brew_force) print -r -- "brew bundle cleanup --force --file $brewfile" ;;
    mise_dry) print -r -- "mise prune --tools --dry-run-code" ;;
    mise_yes) print -r -- "mise prune --tools --yes" ;;
  esac
}

step_calls_of() {
  local step
  for step in "$@"; do
    step_call "$step"
  done
}

# The output that <steps> must print: a section title before each step.
expected_sequence() {
  local step
  for step in "$@"; do
    print -r -- "TITLE"
    step_call "$step"
  done
}

# Runs <command> from <run_dir> in a fresh env -i child whose stdin is a pipe with data.
# With answer=<lines>, the pipe holds only those lines (e.g. answer=$'y\n\n' holds a yes,
# then an empty line); with answer='<devnull>', stdin is /dev/null. SHA1N_PROFILE_HOME points to a missing directory, so a script that reads it
# fails. With merge_streams=1, stderr goes to the stdout file; both are opened for
# append, so the lines keep the order in which they were written.
run_command() {
  local run_dir="$1"
  shift
  local err_file="$stub_dir/err"
  (( ${merge_streams:-0} )) && err_file="$stub_dir/out"
  : >"$stub_dir/out" >"$stub_dir/err"
  local -a feed=("LEAKED"{1..50})
  (( ${+answer} )) && feed=("$answer")
  if [[ "${answer-}" == "<devnull>" ]]; then
    run_child "$run_dir" "$@" </dev/null
  else
    print -rl -- "${feed[@]}" | run_child "$run_dir" "$@"
  fi
  print -r -- "$?" >"$stub_dir/rc"
}

run_child() {
  local run_dir="$1"
  shift
  (cd "$run_dir" && env -i HOME="$HOME" PATH="$stub_bin:$system_path" TERM="$section_term" \
    SHA1N_PROFILE_HOME="$HOME/missing" "$@") >>"$stub_dir/out" 2>>"$err_file"
}

run_profile() {
  local run_dir="$1"
  shift
  run_command "$run_dir" "$fake_repo/scripts/profile" "$@"
}

# Reads the results into globals, then clears HOME, because a failed assertion exits the case.
collect_and_reset() {
  rc="$(<"$stub_dir/rc")"
  out="$(<"$stub_dir/out")"
  err="$(<"$stub_dir/err")"
  details="$(cat "$stub_dir/details" 2>/dev/null)"
  config_dir_exists=false
  [[ -e "$HOME/.config/profile" ]] && config_dir_exists=true
  # The branch query is left out: the update step may make it in any way it likes.
  local -a lines=("${(@f)$(cat "$stub_dir/calls" 2>/dev/null)}")
  calls="$(print -rl -- "${(@)lines:#git -C * branch --show-current}")"
  reset_home
}

# Prints the details line of each call that matches <pattern>.
details_of() {
  local -a lines=("${(f)details}")
  print -rl -- "${(@M)lines:#${~1}}"
}

# Prints the output as a sequence: TITLE for each section title line, and the call of
# each STUB line, in order.
title_and_step_sequence() {
  local background="$(section_background)"
  local line
  for line in "${(@f)out}"; do
    if [[ "$line" == *"$background"* ]]; then
      print -r -- "TITLE"
    elif [[ "$line" == "STUB "* ]]; then
      print -r -- "${line#STUB }"
    fi
  done
}

function test_script_contract() {
  test_case_title

  assert_file_exists "$profile_script"
  assert_equal "$([[ -x "$profile_script" ]] && print executable)" "executable"
  # zsh reads a script while it runs, so one call on the last line must start all the
  # logic; a pull that changes the file then cannot change the run in progress.
  local -a lines=("${(@f)$(<"$profile_script")}")
  lines=("${(@)lines:#[[:space:]]#}")
  assert_match "${lines[-1]}" '^[A-Za-z_][A-Za-z0-9_]*[[:space:]]+"\$@"[[:space:]]*$'
}

function test_usage() {
  test_case_title

  local row args expected_rc stream usage
  # <arguments>|<exit code>|<stream that holds the usage>
  for row in '|0|out' 'help|0|out' '-h|0|out' '--help|0|out' \
    'sync|2|err' '--bogus|2|err' 'update dev|2|err' 'install --yes dev|2|err' \
    'cleanup essentials|2|err' 'cleanup --yes|2|err'; do
    IFS='|' read -r args expected_rc stream <<<"$row"
    prepare_case
    run_profile "$HOME" ${=args}
    collect_and_reset

    print -r -- "row: profile $args"
    usage="${(P)stream}"
    assert_equal "$rc" "$expected_rc"
    assert_contains "$usage" "update"
    assert_contains "$usage" "install"
    assert_contains "$usage" "cleanup"
    assert_empty "$calls"
  done
}

function test_update() {
  test_case_title
  prepare_case
  run_profile "$HOME" update
  collect_and_reset

  assert_equal "$rc" "0"
  assert_equal "$calls" "$(step_calls_of pull submodule)"
  assert_equal "$(title_and_step_sequence)" "$(expected_sequence pull submodule)"
}

function test_failing_step_stops_the_run() {
  test_case_title

  local row failing command steps
  # <stub that fails>|<command>|<steps that ran>
  for row in 'git_pull|update|pull' 'git_submodule|update|pull submodule' \
    'brew_bundle|install essentials dev|brew' 'mise|install dev|brew mise'; do
    IFS='|' read -r failing command steps <<<"$row"
    prepare_case
    stub_exit "$failing" 1
    run_profile "$HOME" ${=command}
    collect_and_reset

    print -r -- "row: $failing fails in profile $command"
    assert_equal "$rc" "1"
    assert_equal "$calls" "$(step_calls_of ${=steps})"
  done
}

# The profiles that each set of arguments applies. Unknown names are rejected before any step.
function test_install_arguments() {
  test_case_title

  local row args expected_rc steps word
  # <arguments>|<exit code>|<steps>|<HOMEBREW_PROFILE_INSTALL_PROFILES, or the name the error gives>
  for row in '|0|brew|essentials' 'essentials|0|brew|essentials' \
    'essentials dev|0|brew mise|essentials dev' \
    'bogus|2||bogus' 'essentials bogus|2||bogus' 'base|2||base'; do
    IFS='|' read -r args expected_rc steps word <<<"$row"
    prepare_case
    run_profile "$HOME" install ${=args}
    collect_and_reset

    print -r -- "row: profile install $args"
    assert_equal "$rc" "$expected_rc"
    assert_equal "$calls" "$(step_calls_of ${=steps})"
    if (( expected_rc == 0 )); then
      assert_equal "$(title_and_step_sequence)" "$(expected_sequence ${=steps})"
      assert_contains "$(details_of 'brew bundle*')" "|profiles=$word|"
    else
      assert_contains "$err" "$word"
    fi
  done
}

# One successful dev run, started through a link in another directory from a project
# directory that pins a runtime. The repo must come from the resolved script path, and
# the project pins must not steer mise: a child cannot change its caller's $PWD, so the
# check is that mise ran in /.
function test_install_dev() {
  test_case_title
  prepare_case
  local project_dir="$HOME/project" link_dir="$HOME/elsewhere"
  mkdir -p "$project_dir" "$link_dir"
  print -r -- "18" >"$project_dir/.nvmrc"
  ln -s "$fake_repo/scripts/profile" "$link_dir/profile"
  run_command "$project_dir" "$link_dir/profile" install dev
  collect_and_reset

  assert_equal "$rc" "0"
  # Exact calls, so neither brew bundle cleanup nor install.sh ran.
  assert_equal "$calls" "$(step_calls_of brew mise)"
  assert_equal "$(title_and_step_sequence)" "$(expected_sequence brew mise)"
  assert_contains "$(details_of 'brew bundle*')" "|profiles=dev|stdin=devnull"
  assert_contains "$(details_of 'mise install*')" "mise install|cwd=/|"
  assert_contains "$(details_of 'mise install*')" "|stdin=devnull"
  assert_equal "$config_dir_exists" "false"
}

function test_install_finds_mise_from_brew_bundle() {
  test_case_title
  prepare_case
  mv "$stub_bin/mise" "$stub_dir/pending_mise"
  run_profile "$HOME" install dev
  collect_and_reset

  assert_equal "$rc" "0"
  assert_equal "$calls" "$(step_calls_of brew mise)"
}

# A skipped step prints its title, then a warning that names the missing tool, and
# does not change the exit code.
function test_install_missing_tools() {
  test_case_title

  local background="$(section_background)"
  local row removed args steps expected line entry
  local -a sequence
  # <stubs removed>|<arguments>|<steps that ran>|<titles, and lines that name brew or mise>
  for row in 'brew mise|dev||TITLE brew TITLE mise' 'brew|essentials||TITLE brew' \
    'mise|dev|brew|TITLE brew TITLE mise'; do
    IFS='|' read -r removed args steps expected <<<"$row"
    prepare_case
    for entry in ${=removed}; do
      rm -f "$stub_bin/$entry"
    done
    merge_streams=1 run_profile "$HOME" install ${=args}
    collect_and_reset

    sequence=()
    for line in "${(@f)out}"; do
      entry=""
      if [[ "$line" == *"$background"* ]]; then
        entry="TITLE"
      elif [[ "$line" == *brew* ]]; then
        entry="brew"
      elif [[ "$line" == *mise* ]]; then
        entry="mise"
      fi
      [[ -n "$entry" && "$entry" != "${sequence[-1]}" ]] && sequence+=("$entry")
    done

    print -r -- "row: no $removed, profile install $args"
    assert_equal "$rc" "0"
    assert_equal "$calls" "$(step_calls_of ${=steps})"
    assert_equal "${(j: :)sequence}" "$expected"
  done
}

# The Brewfile `known` line is the only list of profiles: a name added there is accepted,
# and a Brewfile without the line, or no Brewfile, stops the run.
function test_install_reads_known_list_from_brewfile() {
  test_case_title

  local row content args expected_rc steps word
  # <Brewfile content, or - for no file>|<arguments>|<exit code>|<steps>|<profiles value or error word>
  for row in 'known = %w[essentials dev extra]|extra|0|brew|extra' \
    '# no profile list here||1||Brewfile' '-|essentials|1||Brewfile'; do
    IFS='|' read -r content args expected_rc steps word <<<"$row"
    prepare_case
    if [[ "$content" == - ]]; then
      rm -f "$brewfile"
    else
      print -r -- "$content" >"$brewfile"
    fi
    run_profile "$HOME" install ${=args}
    collect_and_reset

    print -r -- "row: Brewfile '$content', profile install $args"
    assert_equal "$rc" "$expected_rc"
    assert_equal "$calls" "$(step_calls_of ${=steps})"
    if (( expected_rc == 0 )); then
      assert_contains "$(details_of 'brew bundle*')" "|profiles=$word|"
    else
      assert_contains "$err" "$word"
    fi
  done
}

# Prints the cleanup output as one line of words, in order: TITLE-brew and TITLE-mise
# for the section titles, brew-list and mise-list for a line of the stubbed lists,
# brew-question and mise-question for the questions, and none, no-runtimes and kept for
# the "nothing to remove", "no unused runtime versions" and "nothing removed" lines.
# A question does not end its line, so one line can hold several words.
cleanup_sequence() {
  local background="$(section_background)"
  local -A base_markers=(
    'orphan-cask' brew-list
    'node@18.20.0' mise-list
    'Homebrew packages? [y/N]' brew-question
    'runtime versions? [y/N]' mise-question
    'nothing to remove' none
    'no unused runtime versions' no-runtimes
    'nothing removed' kept)
  local line text head best_text
  local -i best_len
  local -a words=()
  for line in "${(@f)out}"; do
    local -A markers=("${(@kv)base_markers}")
    [[ "$line" == *"$background"* ]] &&
      markers+=('Homebrew cleanup' TITLE-brew 'mise prune' TITLE-mise)
    while true; do
      best_text="" best_len=-1
      for text in "${(@k)markers}"; do
        [[ "$line" == *"$text"* ]] || continue
        head="${line%%"$text"*}"
        if (( best_len < 0 || ${#head} < best_len )); then
          best_len=${#head}
          best_text="$text"
        fi
      done
      (( best_len >= 0 )) || break
      words+=("${markers[$best_text]}")
      line="${line#*"$best_text"}"
    done
  done
  print -r -- "${(j: :)words}"
}

# Both dry runs, with the caller's environment narrowing the profiles, and the answer No
# to each question. Each question follows its own list and comes before the next title.
function test_cleanup_dry_runs() {
  test_case_title
  prepare_case
  stub_items brew
  stub_items mise
  answer=$'n\nn' run_command "$HOME" /usr/bin/env HOMEBREW_PROFILE_INSTALL_PROFILES=essentials \
    "$fake_repo/scripts/profile" cleanup
  collect_and_reset

  assert_equal "$rc" "0"
  assert_equal "$calls" "$(step_calls_of brew_dry mise_dry)"
  assert_equal "$(details_of 'brew bundle cleanup*')" \
    "$(step_call brew_dry)|cwd=/|profiles=essentials dev|stdin=devnull"
  assert_contains "$(details_of 'mise prune*')" "$(step_call mise_dry)|cwd=/|"
  assert_contains "$(details_of 'mise prune*')" "|stdin=devnull"
  assert_equal "$(cleanup_sequence)" \
    "TITLE-brew brew-list brew-question kept TITLE-mise mise-list mise-question kept"
  local word
  for word in "Would uninstall casks:" "orphan-formula    other-formula" \
    "Remove these 3 Homebrew packages? [y/N] " "Remove these 1 runtime versions? [y/N] "; do
    assert_contains "$out" "$word"
  done
  for word in "BREW-PREAMBLE" "--force" "proceed"; do
    assert_not_contains "$out" "$word"
  done
}

# <answers> are the stdin lines, separated by commas, or <devnull>. Each section with
# items asks its own question and reads the next line; a removal runs only after a yes to
# its own question. A section with no items asks nothing and reads no line.
function test_cleanup_answers() {
  test_case_title

  local both="TITLE-brew brew-list brew-question TITLE-mise mise-list mise-question"
  local row given items steps sequence tool
  local newline=$'\n'
  # <answers>|<tools with items>|<calls>|<cleanup sequence>
  for row in \
    "y,y|brew mise|brew_dry brew_force mise_dry mise_yes|$both" \
    "Y,Y|brew mise|brew_dry brew_force mise_dry mise_yes|$both" \
    "y,|brew mise|brew_dry brew_force mise_dry|$both kept" \
    "y|brew mise|brew_dry brew_force mise_dry|$both kept" \
    ",y|brew mise|brew_dry mise_dry mise_yes|TITLE-brew brew-list brew-question kept TITLE-mise mise-list mise-question" \
    "n,n|brew mise|brew_dry mise_dry|TITLE-brew brew-list brew-question kept TITLE-mise mise-list mise-question kept" \
    "|brew mise|brew_dry mise_dry|TITLE-brew brew-list brew-question kept TITLE-mise mise-list mise-question kept" \
    "<devnull>|brew mise|brew_dry mise_dry|TITLE-brew brew-list brew-question kept TITLE-mise mise-list mise-question kept" \
    "yes please,yes|brew mise|brew_dry mise_dry|TITLE-brew brew-list brew-question kept TITLE-mise mise-list mise-question kept" \
    "y|brew|brew_dry brew_force mise_dry|TITLE-brew brew-list brew-question TITLE-mise no-runtimes" \
    "y|mise|brew_dry mise_dry mise_yes|TITLE-brew none TITLE-mise mise-list mise-question" \
    "n,y|mise|brew_dry mise_dry|TITLE-brew none TITLE-mise mise-list mise-question kept" \
    "y,y||brew_dry mise_dry|TITLE-brew none TITLE-mise no-runtimes"; do
    IFS='|' read -r given items steps sequence <<<"$row"
    prepare_case
    for tool in ${=items}; do
      stub_items "$tool"
    done
    answer="${given//,/$newline}" run_profile "$HOME" cleanup
    collect_and_reset

    print -r -- "row: answers '$given', items from '$items'"
    assert_equal "$rc" "0"
    assert_equal "$calls" "$(step_calls_of ${=steps})"
    assert_not_contains "$calls" "--zap"
    assert_equal "$(cleanup_sequence)" "$sequence"
    if (( ${${=items}[(Ie)brew]} )); then
      assert_contains "$out" "Remove these 3 Homebrew packages? [y/N] "
    else
      assert_not_contains "$out$err" "Homebrew packages?"
    fi
    if (( ${${=items}[(Ie)mise]} )); then
      assert_contains "$out" "Remove these 1 runtime versions? [y/N] "
    else
      assert_not_contains "$out$err" "runtime versions?"
    fi
    if [[ "$steps" == *brew_force* ]]; then
      assert_equal "$(details_of 'brew bundle cleanup --force*')" \
        "$(step_call brew_force)|cwd=/|profiles=essentials dev|stdin=devnull"
    fi
    if [[ "$steps" == *mise_yes* ]]; then
      assert_contains "$(details_of 'mise prune --tools --yes*')" "$(step_call mise_yes)|cwd=/|"
      assert_contains "$(details_of 'mise prune --tools --yes*')" "|stdin=devnull"
    fi
  done
}

# A failure stops the command: a failed Homebrew step leaves the mise section out,
# title included.
function test_cleanup_failures() {
  test_case_title

  local row failing code steps
  # <stub>|<its exit code>|<calls>
  for row in 'brew_dry|3|brew_dry' 'brew_force|1|brew_dry brew_force' \
    'mise_dry|3|brew_dry brew_force mise_dry' \
    'mise_yes|1|brew_dry brew_force mise_dry mise_yes'; do
    IFS='|' read -r failing code steps <<<"$row"
    prepare_case
    stub_items brew
    stub_items mise
    stub_exit "$failing" "$code"
    answer=$'y\ny' run_profile "$HOME" cleanup
    collect_and_reset

    print -r -- "row: $failing exits with $code"
    assert_equal "$rc" "1"
    assert_equal "$calls" "$(step_calls_of ${=steps})"
    if [[ "$steps" != *mise* ]]; then
      assert_not_contains "$(cleanup_sequence)" "TITLE-mise"
    fi
  done
}

# A list-only run that exits with 1 always prints a `Would ` line, so exit code 1 with
# no list means Homebrew failed (e.g. an invalid Brewfile).
function test_cleanup_homebrew_fails_with_no_list() {
  test_case_title
  prepare_case
  stub_exit brew_dry 1
  stub_items mise
  answer=$'y\ny' run_profile "$HOME" cleanup
  collect_and_reset

  assert_equal "$rc" "1"
  assert_equal "$calls" "$(step_calls_of brew_dry)"
  assert_not_contains "$out$err" "Homebrew packages?"
  assert_not_contains "$(cleanup_sequence)" "TITLE-mise"
  assert_contains "$err" "ERROR"
}

# A skipped tool prints its title, then a warning that names it, asks no question, reads
# no answer line and does not change the exit code.
function test_cleanup_missing_tools() {
  test_case_title

  local background="$(section_background)"
  local row removed items steps expected line entry
  local -a sequence
  # <stubs removed>|<tools with items>|<calls>|<titles, and lines that name brew or mise>
  for row in 'brew mise|||TITLE brew TITLE mise' 'brew||mise_dry|TITLE brew TITLE' \
    'mise||brew_dry|TITLE TITLE mise' 'brew|mise|mise_dry mise_yes|TITLE brew TITLE' \
    'mise|brew|brew_dry brew_force|TITLE TITLE mise'; do
    IFS='|' read -r removed items steps expected <<<"$row"
    prepare_case
    for entry in ${=items}; do
      stub_items "$entry"
    done
    for entry in ${=removed}; do
      rm -f "$stub_bin/$entry"
    done
    answer=y merge_streams=1 run_profile "$HOME" cleanup
    collect_and_reset

    # Whole words only, because "Homebrew" in the Homebrew question does not name brew.
    sequence=()
    for line in "${(@f)out}"; do
      entry=""
      if [[ "$line" == *"$background"* ]]; then
        entry="TITLE"
      elif [[ "$line" =~ '(^|[^[:alnum:]])brew([^[:alnum:]]|$)' ]]; then
        entry="brew"
      elif [[ "$line" =~ '(^|[^[:alnum:]])mise([^[:alnum:]]|$)' ]]; then
        entry="mise"
      fi
      [[ "$entry" == TITLE || ( -n "$entry" && "$entry" != "${sequence[-1]}" ) ]] &&
        sequence+=("$entry")
    done

    print -r -- "row: no $removed, items from '$items'"
    assert_equal "$rc" "0"
    assert_equal "$calls" "$(step_calls_of ${=steps})"
    assert_equal "${(j: :)sequence}" "$expected"
    if (( ${${=removed}[(Ie)brew]} )); then
      assert_not_contains "$out" "Homebrew packages?"
    fi
    if (( ${${=removed}[(Ie)mise]} )); then
      assert_not_contains "$out" "runtime versions?"
    fi
    if [[ -z "$items" ]]; then
      assert_not_contains "$out" "Remove these"
    fi
  done
}

# Each run reads the file from disk, so a change (e.g. from profile update) takes
# effect on the next run with no reload.
function test_changed_script_takes_effect_next_run() {
  test_case_title
  prepare_case
  local fake_script="$fake_repo/scripts/profile"
  run_profile "$HOME" install
  local first_out="$(<"$stub_dir/out")"

  local -a lines=("${(@f)$(<"$fake_script")}")
  lines=("${(@)lines:#[[:space:]]#}")
  local last_line="${lines[-1]}"
  lines[-1]='print -r -- "CHANGED-SCRIPT-MARKER"'
  lines+=("$last_line")
  print -rl -- "${lines[@]}" >"$fake_script"

  run_profile "$HOME" install
  collect_and_reset

  assert_not_contains "$first_out" "CHANGED-SCRIPT-MARKER"
  assert_equal "$rc" "0"
  assert_contains "$out" "CHANGED-SCRIPT-MARKER"
}

function test_load_exposes_profile_command_without_alias() {
  test_case_title

  local -a result=("${(@f)$(env -i HOME="$HOME" PATH="$system_path" TERM=dumb "$zsh_bin" -f -c '
    source "$1"
    alias update_profile >/dev/null 2>&1 && print alias-present || print alias-absent
    whence -w profile
    whence -p profile' _ "$load_script" 2>/dev/null)}")

  assert_equal "${result[1]}" "alias-absent"
  assert_equal "${result[2]}" "profile: command"
  assert_equal "${result[3]:A}" "${profile_script:A}"
}

setup
run_test test_script_contract
run_test test_usage
run_test test_update
run_test test_failing_step_stops_the_run
run_test test_install_arguments
run_test test_install_dev
run_test test_install_finds_mise_from_brew_bundle
run_test test_install_missing_tools
run_test test_install_reads_known_list_from_brewfile
run_test test_cleanup_dry_runs
run_test test_cleanup_answers
run_test test_cleanup_failures
run_test test_cleanup_homebrew_fails_with_no_list
run_test test_cleanup_missing_tools
run_test test_changed_script_takes_effect_next_run
run_test test_load_exposes_profile_command_without_alias
cleanup
finish_tests
