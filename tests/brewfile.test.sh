#!/usr/bin/env zsh

source "$SHA1N_PROFILE_TESTS_HOME/sandbox.zsh"
brewfile="$profile_home/brew/Brewfile"
brew_bin="$(command -v brew)"
known_profiles=(essentials dev)
entry_keywords='brew|cask|uv|mas|vscode|whalebrew|go|cargo|npm|flatpak|krew'
process_or_file_load='`|%x|\b(IO\.|File\.|Open3|Kernel\.|Process\.|system|exec|spawn|fork|popen|require|require_relative|load|eval|instance_eval|class_eval|zsh|bash)\b'

# `brew bundle list` only evaluates the Brewfile and prints entry names: it does
# not tap, fetch or trust anything, so it works in the sandbox HOME without the
# `brew ruby` + Homebrew::Bundle::Dsl fallback. HOMEBREW_NO_INSTALL_FROM_API
# stops the JSON API download that brew otherwise makes on a cold HOME cache,
# and HOMEBREW_CACHE outside HOME keeps brew's bootsnap cache out of the sandbox.
# env -i so the caller's HOMEBREW_* settings cannot change the result.
# With no argument HOMEBREW_PROFILE_INSTALL_PROFILES is left unset.
brew_bundle_list() {
  local -a profiles_env=()
  (( $# )) && profiles_env=("HOMEBREW_PROFILE_INSTALL_PROFILES=$1")
  local cache_dir="$(mktemp -d "${TMPDIR:-/tmp}/brewfile_test_cache.XXXXXX")"
  env -i HOME="$HOME" PATH="${brew_bin:h}:/usr/bin:/bin" TERM=dumb \
    HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ANALYTICS=1 HOMEBREW_NO_ENV_HINTS=1 \
    HOMEBREW_NO_INSTALL_FROM_API=1 HOMEBREW_CACHE="$cache_dir" \
    "${profiles_env[@]}" \
    "$brew_bin" bundle list --all --file "$brewfile" </dev/null 2>&1
  local exit_code="$?"
  rm -rf "$cache_dir"
  return "$exit_code"
}

# Quoted strings and comments are removed first, so package names such as
# "gnu-time" and prose in comments cannot match the Ruby patterns.
strip_strings_and_comments() {
  sed -E -e 's/"([^"\\]|\\.)*"/""/g' -e "s/'([^'\\\\]|\\\\.)*'/''/g" -e 's/(^|[[:space:]])#.*$//'
}

# Prints the lines of the Brewfile outside any `if ... end` block that match <pattern>.
top_level_lines() {
  awk -v pattern="$1" '
    /^[[:space:]]*(if|unless)[[:space:]]/ { depth++; next }
    /^[[:space:]]*end([[:space:]]|$)/ { depth--; next }
    depth == 0 && $0 ~ pattern { print NR ": " $0 }
  '
}

assert_has_entry() {
  assert_contains $'\n'"$1"$'\n' $'\n'"$2"$'\n'
}

assert_lacks_entry() {
  assert_not_contains $'\n'"$1"$'\n' $'\n'"$2"$'\n'
}

# Reads files only, so it runs without brew (e.g. on Linux CI).
function test_brewfile_layout() {
  test_case_title

  local -a brew_dir_files=("$profile_home"/brew/*(DN:t))
  assert_equal "${(j: :)brew_dir_files}" "Brewfile"

  local -a block_names=(
    ${(f)"$(grep -E '^[[:space:]]*if profiles\.include\?\("[^"]*"\)[[:space:]]*$' "$brewfile" | sed -E 's/^[[:space:]]*if profiles\.include\?\("(.*)"\)[[:space:]]*$/\1/')"}
  )
  assert_not_empty "${block_names[*]}"
  assert_empty "${(@)block_names:|known_profiles}"
  assert_empty "$(print -rl -- "${block_names[@]}" | sort | uniq -d)"

  print -r -- "check: every entry is inside a profile block"
  assert_empty "$(strip_strings_and_comments <"$brewfile" | top_level_lines "^[[:space:]]*($entry_keywords)[[:space:]]")"
  assert_match "$(top_level_lines '^[[:space:]]*tap[[:space:]]+"sha1n/tap"' <"$brewfile")" \
    '^[0-9]+: [[:space:]]*tap "sha1n/tap", trusted: true[[:space:]]*$'
}

# Reads files only, so it runs without brew (e.g. on Linux CI).
function test_no_process_or_file_load() {
  test_case_title

  assert_empty "$(strip_strings_and_comments <"$brewfile" | grep -nE "$process_or_file_load" || true)"

  print -r -- "check: the pattern ignores DSL lines whose strings name a keyword"
  local dsl_sample=$'brew "gnu-time"\ncask "load-exec-system"\ntap "sha1n/tap", trusted: true\nuv "poetry"\nprofiles = ENV.fetch("HOMEBREW_PROFILE_INSTALL_PROFILES", "").split'
  assert_empty "$(print -r -- "$dsl_sample" | strip_strings_and_comments | grep -nE "$process_or_file_load" || true)"
}

function test_profile_selection() {
  test_case_title

  local row value expected_rc present absent output exit_code entry
  # <HOMEBREW_PROFILE_INSTALL_PROFILES, or <unset>>|<exit code>|<present entries or text>|<absent entries>
  for row in '<unset>|0|bat goreleaser shellcheck mise sha1n/tap|' \
    '|0|bat goreleaser shellcheck mise sha1n/tap|' \
    'essentials|0|bat uv sha1n/tap|goreleaser shellcheck mise' \
    'dev|0|bat uv goreleaser shellcheck mise sha1n/tap|' \
    'essentials dev|0|bat mise|go nvm node maven pipx' \
    'dev bogus|1|bogus|'; do
    IFS='|' read -r value expected_rc present absent <<<"$row"
    if [[ "$value" == "<unset>" ]]; then
      output="$(brew_bundle_list)"
    else
      output="$(brew_bundle_list "$value")"
    fi
    exit_code="$?"

    print -r -- "row: HOMEBREW_PROFILE_INSTALL_PROFILES=$value"
    if (( expected_rc == 0 )); then
      assert_equal "$exit_code" "0"
      for entry in ${=present}; do
        assert_has_entry "$output" "$entry"
      done
      for entry in ${=absent}; do
        assert_lacks_entry "$output" "$entry"
      done
      assert_empty "$(print -r -- "$output" | sort | uniq -d)"
      assert_empty "$(print -r -- "$output" | grep -E '^(python|openjdk)@' || true)"
    else
      assert_not_equal "$exit_code" "0"
      assert_contains "$output" "$present"
    fi
  done
}

setup
run_test test_brewfile_layout
run_test test_no_process_or_file_load
if [[ -z "$brew_bin" ]]; then
  echo "# brew is not on PATH; skipping Brewfile evaluation cases"
else
  run_test test_profile_selection
fi
cleanup
finish_tests
