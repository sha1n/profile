#!/usr/bin/env zsh

source "$SHA1N_PROFILE_TESTS_HOME/sandbox.zsh"
profile_script="$profile_home/scripts/profile"
load_script="$profile_home/load.zsh"
# Captured before any case narrows PATH, so the stubs always find zsh.
zsh_bin="$(command -v zsh)"
# Linked into the stub directory, because a developer Mac may hold jq outside system_path.
jq_bin="$(command -v jq)"
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
# Every known profile, so cleanup compares against the full list, whatever the caller set.
all_profiles="$(known_profiles_of "$profile_home/brew/Brewfile")"

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
# brew_dry, brew_force, brew_list, brew_rm_cask, brew_rm_formula, brew_untap, mise_ls,
# mise_yes).
stub_exit() {
  print -r -- "$2" >"$stub_dir/$1_exit"
}

# Makes the list of <tool> (brew or mise) hold items. The Homebrew dry run exits with 1
# and has, as Homebrew 6 prints them, a line before its first `Would ` line, a
# `brew cleanup` section with its paths, a `--force` hint and a question, which
# profile cleanup must not print. `mise ls --prunable --json` exits with 0 either way.
stub_items() {
  case "$1" in
    brew)
      print -rl -- "==> BREW-PREAMBLE" "Would uninstall casks:" "orphan-cask" \
        "Would uninstall formulae:" "orphan-formula    other-formula" \
        "Would untap:" "orphan/tap" \
        'Would `brew cleanup`:' "Would remove: /x/y.tar.gz (1MB)" \
        'Run `brew bundle cleanup --force` to make these changes.' \
        "Do you want to proceed? [y/n]" >"$stub_dir/brew_dry_out"
      stub_exit brew_dry 1 ;;
    mise)
      print -r -- '{"node":[{"version":"18.20.0","requested_version":"18","installed":true}]}' \
        >"$stub_dir/mise_ls_out" ;;
  esac
}

# Makes the profile entries of `brew bundle list` hold the <type>:<name> words
# (type: cask, formula or tap).
stub_entries() {
  local word
  for word in "$@"; do
    print -r -- "${word#*:}" >>"$stub_dir/brew_list_${word%%:*}_out"
  done
}

# Makes the Homebrew dry run list the <type>:<name> words as candidates, one section per
# type, and exit with 1.
stub_candidates() {
  local -A heading=(cask "Would uninstall casks:" formula "Would uninstall formulae:" tap "Would untap:")
  local type
  local -a names
  : >"$stub_dir/brew_dry_out"
  for type in cask formula tap; do
    names=(${${(M)@:#$type:*}#*:})
    (( ${#names} )) || continue
    print -rl -- "${heading[$type]}" "${names[@]}" >>"$stub_dir/brew_dry_out"
  done
  stub_exit brew_dry 1
}

# Leaves jq out of PATH: the stub directory loses its link, and system_path is replaced
# by a directory that links every command of system_path except jq, because both
# runners and macOS ship jq in /usr/bin, which the child cannot drop alone.
remove_jq() {
  rm -f "$stub_bin/jq"
  no_jq_path="$HOME/no-jq-bin"
  mkdir -p "$no_jq_path"
  local dir entry
  for dir in ${(s.:.)system_path}; do
    for entry in "$dir"/*(N); do
      [[ -e "$no_jq_path/${entry:t}" || -L "$no_jq_path/${entry:t}" ]] ||
        ln -s "$entry" "$no_jq_path/${entry:t}"
    done
  done
  rm -f "$no_jq_path/jq"
}

# The real Brewfile, so the scripts read the list of profiles that ships in the repo.
prepare_case() {
  reset_home
  mkdir -p "$stub_bin" "$fake_repo/brew"
  cp -R "$profile_home/scripts" "$fake_repo/scripts"
  cp "$profile_home/brew/Brewfile" "$fake_repo/brew/Brewfile"

  local step
  for step in git_pull git_submodule brew_bundle mise brew_dry brew_force brew_list \
    brew_rm_cask brew_rm_formula brew_untap mise_ls mise_yes; do
    stub_exit "$step" 0
  done
  print -r -- '{}' >"$stub_dir/mise_ls_out"
  # A link, not a stub: jq is a helper, not a step, so it records no call.
  ln -s "$jq_bin" "$stub_bin/jq"

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
  # A cleanup, list or prune call prints <step>_out, if any, and <step>_err to stderr,
  # instead of a STUB line. The brew_force step stays, so that a `--force` run shows up
  # as an unexpected call. `brew bundle list --<type>` prints brew_list_<type>_out, and
  # `brew info --json=v2 --<kind> <name>` prints brew_info_<name>_out, or exits with
  # brew_info_<name>_exit, or names only <name>, as Homebrew does for a plain package.
  write_stub "$stub_bin/brew" '
if [[ "$1" == bundle && "$2" == cleanup ]]; then
  step=brew_dry
  (( ${@[(Ie)--force]} )) && step=brew_force
  [[ -f "$stub_dir/${step}_out" ]] && cat "$stub_dir/${step}_out"
  exit "$(<"$stub_dir/${step}_exit")"
fi
if [[ "$1" == bundle && "$2" == list ]]; then
  [[ -f "$stub_dir/brew_list_${3#--}_out" ]] && cat "$stub_dir/brew_list_${3#--}_out"
  exit "$(<"$stub_dir/brew_list_exit")"
fi
if [[ "$1" == info ]]; then
  name="$4"
  if [[ -f "$stub_dir/brew_info_${name}_out" ]]; then
    cat "$stub_dir/brew_info_${name}_out"
  elif [[ -f "$stub_dir/brew_info_${name}_exit" ]]; then
    exit "$(<"$stub_dir/brew_info_${name}_exit")"
  elif [[ "$3" == --cask ]]; then
    print -r -- "{\"formulae\":[],\"casks\":[{\"token\":\"$name\",\"full_token\":\"$name\",\"old_tokens\":[]}]}"
  else
    print -r -- "{\"formulae\":[{\"name\":\"$name\",\"full_name\":\"$name\",\"aliases\":[],\"oldnames\":[]}],\"casks\":[]}"
  fi
  exit 0
fi
if [[ "$1" == uninstall ]]; then
  print -r -- "STUB $call"
  step=brew_rm_formula
  [[ "$2" == --cask ]] && step=brew_rm_cask
  exit "$(<"$stub_dir/${step}_exit")"
fi
if [[ "$1" == untap ]]; then
  print -r -- "STUB $call"
  exit "$(<"$stub_dir/brew_untap_exit")"
fi
print -r -- "STUB $call"
if [[ "$1" == bundle ]]; then
  [[ -f "$stub_dir/pending_mise" ]] && mv "$stub_dir/pending_mise" "$stub_dir/bin/mise"
  exit "$(<"$stub_dir/brew_bundle_exit")"
fi
exit 0'
  write_stub "$stub_bin/mise" '
if [[ "$1" == ls || "$1" == prune ]]; then
  step=mise_yes
  [[ "$1" == ls ]] && step=mise_ls
  [[ -f "$stub_dir/${step}_out" ]] && cat "$stub_dir/${step}_out"
  [[ -f "$stub_dir/${step}_err" ]] && cat "$stub_dir/${step}_err" >&2
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
    brew_dry) print -r -- "brew bundle cleanup --formula --cask --tap --file $brewfile" ;;
    brew_rm_cask) print -r -- "brew uninstall --cask orphan-cask" ;;
    brew_rm_formula) print -r -- "brew uninstall --formula orphan-formula other-formula" ;;
    brew_untap) print -r -- "brew untap orphan/tap" ;;
    mise_ls) print -r -- "mise ls --prunable --json" ;;
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
  # The branch query and the read-only git calls of the orphan step are left out: the
  # update may make them in any way it likes, and the stub answers them with no orphans.
  # So are the read-only Homebrew queries of the cleanup guard; cases check them
  # through details_of.
  setopt local_options extended_glob
  local -a lines=("${(@f)$(cat "$stub_dir/calls" 2>/dev/null)}")
  lines=("${(@)lines:#git -C * branch --show-current}")
  lines=("${(@)lines:#brew bundle list *}")
  lines=("${(@)lines:#brew info *}")
  calls="$(print -rl -- "${(@)lines:#git( -C [^ ]##| --git-dir=[^ ]##)# (config|rev-parse|status|rev-list)(| *)}")"
  reset_home
}

# Prints the details line of each call that matches <pattern>.
details_of() {
  local -a lines=("${(f)details}")
  print -rl -- "${(@M)lines:#${~1}}"
}

# Prints the details lines of the calls that match <pattern> and lack <text>.
details_lacking() {
  local -a lines=("${(@f)$(details_of "$1")}")
  print -rl -- "${(@)lines:#*$2*}"
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
  # The orphan step makes only read-only calls here, so its title stands alone.
  assert_equal "$(title_and_step_sequence)" "$(expected_sequence pull submodule; print -r -- TITLE)"
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
    # The calls above hide the read-only orphan step, so only its title shows that it ran.
    assert_equal "$(title_and_step_sequence)" "$(expected_sequence ${=steps})"
  done
}

# The profiles that each set of arguments applies. Unknown names are rejected before any step.
function test_install_arguments() {
  test_case_title

  local row args expected_rc steps word
  # <arguments>|<exit code>|<steps>|<HOMEBREW_PROFILE_INSTALL_PROFILES, or the name the error gives>
  for row in '|0|brew|essentials' 'essentials|0|brew|essentials' \
    'essentials dev|0|brew mise|essentials dev' \
    'workstation|0|brew mise|workstation' \
    'essentials workstation|0|brew mise|essentials workstation' \
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
# and a Brewfile without the line, or no Brewfile, stops the run. The order of the line
# is the chain, so a name after dev applies dev and runs mise, and a name before it does not.
function test_install_reads_known_list_from_brewfile() {
  test_case_title

  local row content args expected_rc steps word
  # <Brewfile content, or - for no file>|<arguments>|<exit code>|<steps>|<profiles value or error word>
  for row in 'known = %w[essentials dev extra]|extra|0|brew mise|extra' \
    'known = %w[pre essentials dev]|pre|0|brew|pre' \
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
# A question does not end its line, so one line can hold several words. The Homebrew
# list marker keeps its two-space indent, because the removal STUB line names the
# cask too, after one space.
cleanup_sequence() {
  local background="$(section_background)"
  local -A base_markers=(
    '  orphan-cask' brew-list
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
  assert_equal "$calls" "$(step_calls_of brew_dry mise_ls)"
  assert_equal "$(details_of 'brew bundle cleanup*')" \
    "$(step_call brew_dry)|cwd=/|profiles=$all_profiles|stdin=devnull"
  assert_contains "$(details_of 'mise ls*')" "$(step_call mise_ls)|cwd=/|"
  assert_contains "$(details_of 'mise ls*')" "|stdin=devnull"
  assert_equal "$(cleanup_sequence)" \
    "TITLE-brew brew-list brew-question kept TITLE-mise mise-list mise-question kept"
  # The candidates are printed by type, one per line, not as Homebrew printed them.
  local word
  for word in $'casks:\n  orphan-cask\nformulae:\n  orphan-formula\n  other-formula\ntaps:\n  orphan/tap' \
    "Remove these 4 Homebrew packages? [y/N] " "Remove these 1 runtime versions? [y/N] "; do
    assert_contains "$out" "$word"
  done
  for word in "BREW-PREAMBLE" "--force" "proceed" '`brew cleanup`' "Would remove" "Would "; do
    assert_not_contains "$out" "$word"
  done
  assert_not_contains "$err" "kept"
}

# <answers> are the stdin lines, separated by commas, or <devnull>. Each section with
# items asks its own question and reads the next line; a removal runs only after a yes to
# its own question. A section with no items asks nothing and reads no line.
function test_cleanup_answers() {
  test_case_title

  local both="TITLE-brew brew-list brew-question TITLE-mise mise-list mise-question"
  local brew_rm="brew_rm_cask brew_rm_formula brew_untap"
  local row given items steps sequence tool step
  local newline=$'\n'
  # <answers>|<tools with items>|<calls>|<cleanup sequence>
  for row in \
    "y,y|brew mise|brew_dry $brew_rm mise_ls mise_yes|$both" \
    "Y,Y|brew mise|brew_dry $brew_rm mise_ls mise_yes|$both" \
    "y,|brew mise|brew_dry $brew_rm mise_ls|$both kept" \
    "y|brew mise|brew_dry $brew_rm mise_ls|$both kept" \
    ",y|brew mise|brew_dry mise_ls mise_yes|TITLE-brew brew-list brew-question kept TITLE-mise mise-list mise-question" \
    "n,n|brew mise|brew_dry mise_ls|TITLE-brew brew-list brew-question kept TITLE-mise mise-list mise-question kept" \
    "|brew mise|brew_dry mise_ls|TITLE-brew brew-list brew-question kept TITLE-mise mise-list mise-question kept" \
    "<devnull>|brew mise|brew_dry mise_ls|TITLE-brew brew-list brew-question kept TITLE-mise mise-list mise-question kept" \
    "yes please,yes|brew mise|brew_dry mise_ls|TITLE-brew brew-list brew-question kept TITLE-mise mise-list mise-question kept" \
    "y|brew|brew_dry $brew_rm mise_ls|TITLE-brew brew-list brew-question TITLE-mise no-runtimes" \
    "y|mise|brew_dry mise_ls mise_yes|TITLE-brew none TITLE-mise mise-list mise-question" \
    "n,y|mise|brew_dry mise_ls|TITLE-brew none TITLE-mise mise-list mise-question kept" \
    "y,y||brew_dry mise_ls|TITLE-brew none TITLE-mise no-runtimes"; do
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
    # The removal is one command per type, never a `brew bundle cleanup --force` run.
    assert_not_contains "$calls" "--force"
    assert_equal "$(cleanup_sequence)" "$sequence"
    if (( ${${=items}[(Ie)brew]} )); then
      assert_contains "$out" "Remove these 4 Homebrew packages? [y/N] "
    else
      assert_not_contains "$out$err" "Homebrew packages?"
    fi
    if (( ${${=items}[(Ie)mise]} )); then
      assert_contains "$out" "Remove these 1 runtime versions? [y/N] "
    else
      assert_not_contains "$out$err" "runtime versions?"
    fi
    if [[ "$steps" == *brew_rm_cask* ]]; then
      for step in ${=brew_rm}; do
        assert_contains "$(details_of "$(step_call "$step")|*")" "$(step_call "$step")|cwd=/|"
        assert_contains "$(details_of "$(step_call "$step")|*")" "|stdin=devnull"
      done
    fi
    if [[ "$steps" == *mise_yes* ]]; then
      assert_contains "$(details_of 'mise prune --tools --yes*')" "$(step_call mise_yes)|cwd=/|"
      assert_contains "$(details_of 'mise prune --tools --yes*')" "|stdin=devnull"
    fi
  done
}

# A failure stops the command: a failed Homebrew step leaves the mise section out,
# title included, and a failed removal command leaves the later removals out. A failed
# `brew bundle list` (brew_list) means the guard cannot tell what a profile lists, so
# nothing is offered.
function test_cleanup_failures() {
  test_case_title

  local brew_rm="brew_rm_cask brew_rm_formula brew_untap"
  local row failing code steps
  # <stub>|<its exit code>|<calls>
  for row in 'brew_dry|3|brew_dry' 'brew_list|1|brew_dry' \
    'brew_rm_cask|1|brew_dry brew_rm_cask' \
    'brew_rm_formula|1|brew_dry brew_rm_cask brew_rm_formula' \
    "brew_untap|1|brew_dry $brew_rm" \
    "mise_ls|3|brew_dry $brew_rm mise_ls" "mise_ls|1|brew_dry $brew_rm mise_ls" \
    "mise_yes|1|brew_dry $brew_rm mise_ls mise_yes"; do
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
    assert_not_contains "$calls" "--force"
    assert_contains "$err" "ERROR"
    if [[ "$steps" != *brew_rm_cask* ]]; then
      assert_not_contains "$out$err" "Homebrew packages?"
    fi
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

# The guard of the Homebrew section: a candidate that a profile lists is kept, with a
# warning before the question, so that the name match of Homebrew alone (a cask under
# its old token, a tapped formula by its short name) can never remove a profile package.
# The entries come from `brew bundle list` with every profile, and the names of a
# candidate from `brew info`; a candidate whose names cannot be read is kept too.
# stderr is merged, so the order of the warnings and the result line can be read.
function test_cleanup_keeps_profile_packages() {
  test_case_title

  local vscode="cask:visual-studio-code" bert="formula:sha1n/tap/bert"
  local row entries candidates unreadable kept count removals word name head
  local -a kept_lines listed
  # <profile entries>|<candidates of the dry run>|<candidate whose names cannot be read, or ->|<kept warnings, separated by commas>|<count in the question, or - for none>|<removal calls, separated by commas>
  for row in \
    "$vscode cask:docker-desktop|cask:visual-studio-code cask:docker cask:orphan-cask formula:orphan-formula|-|visual-studio-code: a profile lists it,docker: a profile lists it|2|brew uninstall --cask orphan-cask,brew uninstall --formula orphan-formula" \
    "$bert|formula:bert formula:orphan-formula|-|bert: a profile lists it|1|brew uninstall --formula orphan-formula" \
    "$bert|cask:orphan-cask formula:orphan-formula|orphan-cask|orphan-cask: its names could not be read|1|brew uninstall --formula orphan-formula" \
    "$vscode $bert|cask:visual-studio-code formula:bert|-|visual-studio-code: a profile lists it,bert: a profile lists it|-|" \
    "tap:sha1n/tap|tap:sha1n/tap tap:orphan/tap|-|sha1n/tap: a profile lists it|1|brew untap orphan/tap" \
    "$bert|tap:sha1n/tap tap:orphan/tap|-|sha1n/tap: a profile lists it|1|brew untap orphan/tap"; do
    IFS='|' read -r entries candidates unreadable kept count removals <<<"$row"
    prepare_case
    stub_entries ${=entries}
    stub_candidates ${=candidates}
    # Docker Desktop installed under its old cask token.
    print -r -- '{"formulae":[],"casks":[{"token":"docker-desktop","full_token":"docker-desktop","old_tokens":["docker"]}]}' \
      >"$stub_dir/brew_info_docker_out"
    [[ "$unreadable" == - ]] || print -r -- 1 >"$stub_dir/brew_info_${unreadable}_exit"
    answer=y merge_streams=1 run_profile "$HOME" cleanup
    collect_and_reset

    print -r -- "row: entries '$entries', candidates '$candidates', $unreadable unreadable"
    assert_equal "$rc" "0"
    assert_equal "$calls" "$(step_call brew_dry
      [[ -n "$removals" ]] && print -rl -- "${(@s:,:)removals}"
      step_call mise_ls)"
    assert_not_contains "$calls" "--force"
    assert_contains "$(cleanup_sequence)" "TITLE-mise"

    print -r -- "check: the warnings, in list order, come before the result"
    kept_lines=("${(@M)${(f)out}:#*kept *}")
    assert_equal "${(j:,:)${kept_lines[@]#*kept }}" "$kept"
    if [[ "$count" == - ]]; then
      assert_not_contains "$out" "Homebrew packages?"
      assert_equal "$(cleanup_sequence)" "TITLE-brew none TITLE-mise no-runtimes"
      head="${out%%nothing to remove*}"
    else
      assert_contains "$out" "Remove these $count Homebrew packages? [y/N] "
      head="${out%%Remove these*}"
    fi
    for word in "${(@s:,:)kept}"; do
      assert_contains "$head" "kept $word"
    done

    print -r -- "check: a kept candidate is neither listed nor removed"
    listed=("${(@)${(@M)${(f)out}:#  *}#  }")
    for word in "${(@s:,:)kept}"; do
      name="${word%%:*}"
      assert_equal "${listed[(Ie)$name]}" "0"
      assert_equal "${${=calls}[(Ie)$name]}" "0"
    done

    print -r -- "check: the entries of every profile, and the names of each candidate"
    assert_equal "$(details_of 'brew bundle list*' | sort)" "$(for word in formula cask tap; do
      print -r -- "brew bundle list --$word --file $brewfile|cwd=/|profiles=$all_profiles|stdin=devnull"
    done | sort)"
    for word in ${=candidates}; do
      [[ "$word" == tap:* ]] && continue
      assert_contains "$(details_of 'brew info*')" "brew info --json=v2 --${word%%:*} ${word#*:}|cwd=/|"
    done
    assert_empty "$(details_lacking 'brew info*' '|stdin=devnull')"
  done
}

# Prints the lines of the output that hold only a <tool>@<version>, in order.
listed_versions() {
  local line
  for line in "${(@f)out}"; do
    [[ "$line" =~ '^[[:alnum:]_-]+@[0-9][0-9.]*$' ]] && print -r -- "$line"
  done
}

# The list and its count come from the JSON on stdout of `mise ls --prunable --json`,
# never from stderr, where mise writes its warnings and its dry-run list.
function test_cleanup_mise_lists() {
  test_case_title

  local several='{"node":[{"version":"18.20.0","installed":true},{"version":"20.1.0","installed":true}],"go":[{"version":"1.22.0","installed":true}]}'
  local one='{"node":[{"version":"18.20.0","installed":true}]}'
  local row json noise given versions count steps sequence
  local comma=','
  local newline=$'\n'
  # <mise ls stdout>|<mise ls stderr lines, separated by commas>|<answer>|<listed versions>|<count in the question, or - for none>|<calls>|<cleanup sequence>
  for row in \
    "$several||y|node@18.20.0 node@20.1.0 go@1.22.0|3|brew_dry mise_ls mise_yes|TITLE-brew none TITLE-mise mise-list mise-question" \
    "$several||n|node@18.20.0 node@20.1.0 go@1.22.0|3|brew_dry mise_ls|TITLE-brew none TITLE-mise mise-list mise-question kept" \
    "$one|mise WARN  deprecated setting${comma}go@1.21.0 would be pruned${comma}node@16.0.0 would be pruned|n|node@18.20.0|1|brew_dry mise_ls|TITLE-brew none TITLE-mise mise-list mise-question kept" \
    "{}|mise WARN  deprecated setting|y||-|brew_dry mise_ls|TITLE-brew none TITLE-mise no-runtimes"; do
    IFS='|' read -r json noise given versions count steps sequence <<<"$row"
    prepare_case
    print -r -- "$json" >"$stub_dir/mise_ls_out"
    [[ -n "$noise" ]] && print -r -- "${noise//$comma/$newline}" >"$stub_dir/mise_ls_err"
    answer="$given" run_profile "$HOME" cleanup
    collect_and_reset

    print -r -- "row: mise ls prints '$json', answer '$given'"
    assert_equal "$rc" "0"
    assert_equal "$calls" "$(step_calls_of ${=steps})"
    assert_equal "$(cleanup_sequence)" "$sequence"
    assert_equal "$(listed_versions)" "$(print -rl -- ${=versions})"
    if [[ "$count" == - ]]; then
      assert_not_contains "$out$err" "runtime versions?"
    else
      assert_contains "$out" "Remove these $count runtime versions? [y/N] "
    fi
    assert_contains "$(details_of 'mise ls*')" "$(step_call mise_ls)|cwd=/|"
    assert_contains "$(details_of 'mise ls*')" "|stdin=devnull"
    if [[ "$steps" == *mise_yes* ]]; then
      assert_contains "$(details_of 'mise prune*')" "$(step_call mise_yes)|cwd=/|"
      assert_contains "$(details_of 'mise prune*')" "|stdin=devnull"
    fi
  done
}

# mise exits with 1 on a config error too, and an unreadable list cannot be counted, so
# each of these fails the command before any question or removal.
function test_cleanup_mise_list_fails() {
  test_case_title

  local one='{"node":[{"version":"18.20.0","installed":true}]}'
  local row json code jq_kind child_path
  # <mise ls stdout, or - for none>|<mise ls exit code>|<jq: real, failing or missing>
  for row in '-|1|real' 'not json {|0|real' "$one|0|failing" "$one|0|missing"; do
    IFS='|' read -r json code jq_kind <<<"$row"
    prepare_case
    if [[ "$json" == - ]]; then
      : >"$stub_dir/mise_ls_out"
      # No "ERROR" here, so the check below sees the error of profile itself.
      print -r -- "mise failed to parse config.toml: invalid TOML" >"$stub_dir/mise_ls_err"
    else
      print -r -- "$json" >"$stub_dir/mise_ls_out"
    fi
    stub_exit mise_ls "$code"
    child_path="$system_path"
    case "$jq_kind" in
      failing)
        rm -f "$stub_bin/jq"
        print -rl -- "#!$zsh_bin -f" 'print -r -- "jq: stub failure" >&2' 'exit 5' >"$stub_bin/jq"
        chmod +x "$stub_bin/jq" ;;
      missing)
        remove_jq
        child_path="$no_jq_path"
        assert_empty "$(env -i PATH="$stub_bin:$child_path" "$zsh_bin" -fc 'whence -p jq')" ;;
    esac
    answer=$'y\ny' system_path="$child_path" run_profile "$HOME" cleanup
    collect_and_reset

    print -r -- "row: mise ls prints '$json' and exits with $code, jq $jq_kind"
    assert_equal "$rc" "1"
    assert_equal "$calls" "$(step_calls_of brew_dry mise_ls)"
    assert_contains "$(cleanup_sequence)" "TITLE-mise"
    assert_not_contains "$out$err" "runtime versions?"
    assert_contains "$err" "ERROR"
  done
}

# A skipped tool prints its title, then a warning that names it, asks no question, reads
# no answer line and does not change the exit code.
function test_cleanup_missing_tools() {
  test_case_title

  local background="$(section_background)"
  local row removed items steps expected line entry
  local -a sequence
  # <stubs removed>|<tools with items>|<calls>|<titles, and lines that name brew or mise>
  for row in 'brew mise|||TITLE brew TITLE mise' 'brew||mise_ls|TITLE brew TITLE' \
    'mise||brew_dry|TITLE TITLE mise' 'brew|mise|mise_ls mise_yes|TITLE brew TITLE' \
    'mise|brew|brew_dry brew_rm_cask brew_rm_formula brew_untap|TITLE brew TITLE mise'; do
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
run_test test_cleanup_keeps_profile_packages
run_test test_cleanup_mise_lists
run_test test_cleanup_mise_list_fails
run_test test_cleanup_missing_tools
run_test test_changed_script_takes_effect_next_run
run_test test_load_exposes_profile_command_without_alias
cleanup
finish_tests
