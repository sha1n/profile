#!/usr/bin/env zsh

source "$SHA1N_PROFILE_TESTS_HOME/sandbox.zsh"
completions_file="$profile_home/include/completions"
# Captured before any case narrows PATH, so the child always finds zsh.
zsh_bin="$(command -v zsh)"
# Holds no profile command on a developer Mac or a CI runner, so only the stub can answer.
system_path="/usr/bin:/bin"
stub_bin="$HOME/stubs/bin"
result_dir="$HOME/results"

# _describe and _wanted call the compdescribe and comptags builtins, which refuse to run
# outside a completion widget, so the child replaces them with functions that print the
# names they are given, one per line. The harness supports _describe with array names,
# _wanted and _requested in front of compadd, compadd with or without -a, and the
# `N:descr:(a b)` and `N:descr:((a\:d b\:d))` action specs of _arguments.
completion_shims='
_describe() {
  while [[ "$1" == -* ]]; do
    [[ "$1" == -t ]] && shift
    shift
  done
  shift
  local arg
  for arg in "$@"; do
    [[ "$arg" == -- ]] && break
    [[ "${(Pt)arg}" == array* ]] && print -rl -- "${(@)${(@P)arg}%%:*}"
  done
  return 0
}
_wanted() {
  while (( $# )) && [[ "$1" != compadd ]]; do shift; done
  (( $# )) && "$@"
}
_requested() { _wanted "$@"; }
compadd() {
  local -a opts=()
  zparseopts -D -E -a opts a J: X: x: V: P: S: p: s: r: R: d: D: O: A: M: i: I: W: F: E: l o: n Q U f e k 1 2
  [[ "$1" == -- ]] && shift
  local arg
  if (( ${opts[(Ie)-a]} )); then
    for arg in "$@"; do
      (( ${(P)#arg} )) && print -rl -- "${(@P)arg}"
    done
  else
    (( $# )) && print -rl -- "$@"
  fi
  return 0
}
_arguments() {
  local spec action
  for spec in "$@"; do
    [[ "$spec" == <->:*:* ]] || continue
    action="${spec#*:*:}"
    if [[ "$action" == "(("*"))" ]]; then
      action="${${action#\(\(}%\)\)}"
      print -rl -- "${(@)${(@z)action}%%\\:*}"
    elif [[ "$action" == "("*")" ]]; then
      print -rl -- ${(z)${${action#\(}%\)}}
    fi
  done
  return 0
}
'

# A profile command whose `profile list --names` prints <names>, one per line, and exits with
# <code>. Any other call prints the section format of plain `profile list` and fails, so a
# completion that calls plain `profile list` or parses its sections offers no name that the
# cases expect. A failing one also prints a line to stderr, as the real one does, so a
# completion that lets it through shows output.
write_profile_stub() {
  local names="$1" code="$2"
  mkdir -p "$stub_bin"
  {
    print -r -- "#!$zsh_bin -f"
    print -r -- "if [[ \$# -ne 2 || \"\$1\" != list || \"\$2\" != --names ]]; then"
    print -r -- "  print -r -- 'Tiers (each one includes the ones above it):'"
    print -r -- "  print -r -- '  wrong-call'"
    print -r -- "  exit 2"
    print -r -- "fi"
    print -r -- "print -rn -- ${(q)names}"
    (( code )) && print -r -- "print -r -- 'stub profile stderr' >&2"
    print -r -- "exit $code"
  } >"$stub_bin/profile"
  chmod +x "$stub_bin/profile"
}

# Completes the command line <words...> at <current>, the index of the word under the
# cursor, in a fresh env -i child, and reads into globals: registered (the function
# that _comps maps profile to), candidates (the names offered, one per line), out (any
# other stdout) and err. stdin is /dev/null, so a compinit question cannot block.
complete_words() {
  local current="$1"
  shift
  mkdir -p "$result_dir"
  env -i HOME="$HOME" PATH="$stub_bin:$system_path" TERM=dumb SHIMS="$completion_shims" \
    "$zsh_bin" -f -c '
    completions_file="$1" result_dir="$2" CURRENT="$3"
    shift 3
    autoload -U compinit && compinit -u -D
    source "$completions_file"
    print -rn -- "${_comps[profile]}" >"$result_dir/registered"
    eval "$SHIMS"
    words=("$@")
    _profile >"$result_dir/candidates"
    true' _ "$completions_file" "$result_dir" "$current" "$@" \
    </dev/null >"$result_dir/out" 2>"$result_dir/err"
  registered="$(cat "$result_dir/registered" 2>/dev/null)"
  candidates="$(cat "$result_dir/candidates" 2>/dev/null)"
  out="$(<"$result_dir/out")"
  err="$(<"$result_dir/err")"
  rm -rf "$result_dir"
}

# Prints the given words sorted, one per line, so that sets compare whatever order the
# completion offers them in.
sorted() {
  (( $# )) && print -rl -- "${(@o)@}"
}

real_list=$'essentials\ndev\ndev.home\naudio\n'

function test_registered_for_profile() {
  test_case_title
  reset_home
  write_profile_stub "$real_list" 0
  complete_words 2 profile ""

  assert_equal "$registered" "_profile"
}

# The names after install come from `profile list --names` alone: the stub lists no profile
# that the repo holds under brew/ except these, so a completion that globs brew/ fails.
function test_offered_names() {
  test_case_title

  local row line expected
  # <words, with _ for the empty word under the cursor>|<expected names, space separated>
  for row in 'profile _|cleanup install list update' \
    'profile install _|audio dev dev.home essentials' \
    'profile install dev _|audio dev.home essentials' \
    'profile install audio essentials _|dev dev.home' \
    'profile install essentials dev dev.home audio _|' \
    'profile install d|audio dev dev.home essentials' \
    'profile cleanup _|' 'profile list _|' 'profile update _|'; do
    IFS='|' read -r line expected <<<"$row"
    local -a words=(${=line})
    words=("${(@)words/#%_/}")
    reset_home
    write_profile_stub "$real_list" 0
    complete_words ${#words} "${words[@]}"

    print -r -- "row: $line"
    assert_equal "$registered" "_profile"
    assert_equal "$(sorted ${(f)candidates})" "$(sorted ${=expected})"
    assert_empty "$out"
    assert_empty "$err"
  done
}

function test_names_follow_profile_list() {
  test_case_title
  reset_home
  write_profile_stub $'base\nextra\nmusic\n' 0
  complete_words 3 profile install ""

  assert_equal "$(sorted ${(f)candidates})" "$(sorted base extra music)"
  assert_empty "$err"
}

# A failing `profile list --names`, or no profile command, offers nothing and prints nothing,
# because any output would corrupt the command line being edited.
function test_no_names_without_profile_list() {
  test_case_title

  local row
  for row in failing missing; do
    reset_home
    write_profile_stub "$real_list" 1
    [[ "$row" == missing ]] && rm -f "$stub_bin/profile"
    complete_words 3 profile install ""

    print -r -- "row: profile $row"
    assert_equal "$registered" "_profile"
    assert_empty "$candidates"
    assert_empty "$out"
    assert_empty "$err"
  done
}

setup
run_test test_registered_for_profile
run_test test_offered_names
run_test test_names_follow_profile_list
run_test test_no_names_without_profile_list
cleanup
finish_tests
