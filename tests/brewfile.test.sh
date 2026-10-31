#!/usr/bin/env zsh

source "$SHA1N_PROFILE_TESTS_HOME/sandbox.zsh"
brew_dir="$profile_home/brew"
brew_bin="$(command -v brew)"
entry_keywords='tap|brew|cask|uv|mas|vscode|whalebrew|go|cargo|npm|flatpak|krew'
mise_config="$profile_home/config/mise/profile.toml"
sha1n_tap_line='tap "sha1n/tap", trusted: true'

all_files() {
  tier_files_of "$brew_dir"
  addon_files_of "$brew_dir"
}

# `brew bundle list` only evaluates the Brewfile and prints entry names: it does
# not tap, fetch or trust anything, so it works in the sandbox HOME without the
# `brew ruby` + Homebrew::Bundle::Dsl fallback. HOMEBREW_NO_INSTALL_FROM_API
# stops the JSON API download that brew otherwise makes on a cold HOME cache,
# and HOMEBREW_CACHE outside HOME keeps brew's bootsnap cache out of the sandbox.
# env -i so the caller's HOMEBREW_* settings cannot change the result.
brew_bundle_list() {
  local brewfile="$1"
  local cache_dir="$(mktemp -d "${TMPDIR:-/tmp}/brewfile_test_cache.XXXXXX")"
  env -i HOME="$HOME" PATH="${brew_bin:h}:/usr/bin:/bin" TERM=dumb \
    HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ANALYTICS=1 HOMEBREW_NO_ENV_HINTS=1 \
    HOMEBREW_NO_INSTALL_FROM_API=1 HOMEBREW_CACHE="$cache_dir" \
    "$brew_bin" bundle list --all --file "$brewfile" </dev/null 2>&1
  local exit_code="$?"
  rm -rf "$cache_dir"
  return "$exit_code"
}

# Prints `<keyword> "<name>"` for each entry line of <file> other than a tap.
package_entries_of() {
  sed -nE "s/^[[:space:]]*(${entry_keywords})[[:space:]]+(\"[^\"]*\").*$/\\1 \\2/p" "$1" | grep -v '^tap ' || true
}

# Usage: homebrew_formula_of <name>
# Prints the formula that Homebrew installs for <name>, which may be an alias (java is
# openjdk), and fails when Homebrew knows no such formula. Unlike brew_bundle_list, this
# needs the formula index from the JSON API, read from api_cache_dir, outside HOME.
homebrew_formula_of() {
  env -i HOME="$HOME" PATH="${brew_bin:h}:/usr/bin:/bin" TERM=dumb \
    HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ANALYTICS=1 HOMEBREW_NO_ENV_HINTS=1 \
    HOMEBREW_CACHE="$api_cache_dir" \
    "$brew_bin" info --json=v2 --formula "$1" </dev/null 2>/dev/null |
    sed -nE 's/^[[:space:]]*"name":[[:space:]]*"([^"]*)".*$/\1/p' | head -n 1 | grep .
}

# Prints the formula name of each `brew` entry of <file>, without its tap.
formulae_of() {
  sed -nE 's/^[[:space:]]*brew[[:space:]]+"([^"]*)".*$/\1/p' "$1" | sed 's|.*/||'
}

# Prints the tool names of the [tools] table of the mise config.
mise_tools() {
  awk '/^[ \t]*\[/ { in_tools = ($0 == "[tools]"); next }
    in_tools && /^[A-Za-z0-9_-]+[ \t]*=/ { sub(/[ \t]*=.*/, ""); print }' "$mise_config"
}

# Prints the tier files up to and including dev, in chain order.
tiers_through_dev() {
  local file
  for file in ${(f)"$(tier_files_of "$brew_dir")"}; do
    print -r -- "$file"
    [[ "$(profile_name_of "$file")" == dev ]] && return 0
  done
}

# Reads files only, so it runs without brew (e.g. on Linux CI).
function test_brewfile_layout() {
  test_case_title

  local -a brew_dir_entries=("$brew_dir"/*(DN:t))
  assert_equal "${(j: :)brew_dir_entries}" "addons tiers"

  print -r -- "check: each directory holds only its kind of Brewfile"
  local -a tier_entries=("$brew_dir"/tiers/*(DN:t)) addon_entries=("$brew_dir"/addons/*(DN:t))
  assert_not_empty "${tier_entries[*]}"
  assert_not_empty "${addon_entries[*]}"
  assert_empty "$(print -rl -- "${tier_entries[@]}" | grep -vE '^[1-9][0-9]*-[a-z][a-z.]*\.Brewfile$' || true)"
  assert_empty "$(print -rl -- "${addon_entries[@]}" | grep -vE '^[a-z][a-z.]*\.Brewfile$' || true)"
  assert_empty "$(print -rl -- "${tier_entries[@]%%-*}" | sort | uniq -d)"

  print -r -- "check: tier and add-on names are unique"
  local file
  local -a names=()
  for file in ${(f)"$(all_files)"}; do
    names+=("$(profile_name_of "$file")")
  done
  assert_empty "$(print -rl -- "${names[@]}" | sort | uniq -d)"
}

# scripts/profile knows two tiers by name: install applies essentials when given no
# profile, and dev starts the nvim sync and mise install. Every other name is free.
function test_tiers_known_to_the_script() {
  test_case_title

  local file
  local -a tiers=()
  for file in ${(f)"$(tier_files_of "$brew_dir")"}; do
    tiers+=("$(profile_name_of "$file")")
  done
  assert_not_equal "${tiers[(Ie)essentials]}" "0"
  assert_not_equal "${tiers[(Ie)dev]}" "0"
}

# Each file is a plain list that Homebrew reads as is, so it holds no other Ruby. It ends
# with a line break, because profile install hands brew the files joined end to end.
function test_brewfile_lines() {
  test_case_title

  local file
  for file in ${(f)"$(all_files)"}; do
    print -r -- "file: ${file#$profile_home/}"
    assert_not_empty "$(package_entries_of "$file")"
    assert_empty "$(grep -nvE "^[[:space:]]*(#.*)?\$|^[[:space:]]*(${entry_keywords})[[:space:]]+\"[^\"#\\\\]+\"(,[[:space:]]*[a-z_]+:[[:space:]]*(true|false|:[a-z_]+|\"[^\"#\\\\]*\"))*[[:space:]]*(#.*)?\$" "$file" || true)"
    assert_equal "$(tail -c 1 "$file" | od -An -c | tr -d ' ')" '\n'
  done
}

function test_no_duplicate_entries() {
  test_case_title

  local file
  assert_empty "$(for file in ${(f)"$(all_files)"}; do package_entries_of "$file"; done | sort | uniq -d)"
}

# A file that installs from sha1n/tap taps it itself, so that any selection of files
# taps it; a file that does not, never taps it.
function test_sha1n_tap() {
  test_case_title

  local file
  for file in ${(f)"$(all_files)"}; do
    print -r -- "file: ${file#$profile_home/}"
    if grep -qE '^[[:space:]]*[a-z]+[[:space:]]+"sha1n/tap/' "$file"; then
      assert_equal "$(grep -E 'sha1n/tap"' "$file")" "$sha1n_tap_line"
    else
      assert_empty "$(grep -E '"sha1n/tap"' "$file" || true)"
    fi
  done
}

# Usage: assert_no_formula_named <name...>
# No profile lists a formula with one of the names, in any version (<name>@<version>).
assert_no_formula_named() {
  local file formula
  local -a found
  for file in ${(f)"$(all_files)"}; do
    print -r -- "file: ${file#$profile_home/}"
    found=()
    for formula in ${(f)"$(formulae_of "$file")"}; do
      (( ${@[(Ie)${formula%%@*}]} )) && found+=("$formula")
    done
    assert_empty "${found[*]}"
  done
}

# mise owns the language runtimes, so no profile installs a tool that
# config/mise/profile.toml pins. The Python Policy of AGENTS.md also bans pipx.
function test_no_runtime_formulae() {
  test_case_title

  local -a tools=(${(f)"$(mise_tools)"})
  assert_not_empty "${tools[*]}"
  assert_no_formula_named "${tools[@]}" pipx
}

# The same, by the formula Homebrew installs for each mise tool, so a runtime cannot come
# in under another name (openjdk for java, python@3.x for python). A tool that Homebrew
# has no formula for is skipped, but at least one must resolve, or the lookup is broken.
function test_no_runtime_formulae_by_homebrew_name() {
  test_case_title

  local tool formula
  local -a formulae=()
  for tool in ${(f)"$(mise_tools)"}; do
    if formula="$(homebrew_formula_of "$tool")"; then
      print -r -- "tool: $tool is formula $formula"
      formulae+=("${formula%%@*}")
    else
      print -r -- "tool: $tool has no Homebrew formula"
    fi
  done
  assert_not_empty "${formulae[*]}"
  assert_no_formula_named "${formulae[@]}"
}

# :ProfileSync, which install runs from dev on, builds the treesitter parsers with
# tree-sitter-cli, so a tier no later than dev must install it.
function test_nvim_sync_toolchain_reaches_dev() {
  test_case_title

  local file
  local -a files=(${(f)"$(tiers_through_dev)"})
  assert_equal "$(profile_name_of "${files[-1]}")" "dev"
  assert_not_empty "$(for file in "${files[@]}"; do formulae_of "$file"; done | grep -x tree-sitter-cli)"
}

# Each file evaluates on its own and lists at least one package, none twice.
function test_profile_files_evaluate() {
  test_case_title

  local file output exit_code
  assert_not_empty "$(all_files)"
  for file in ${(f)"$(all_files)"}; do
    output="$(brew_bundle_list "$file")"
    exit_code="$?"

    print -r -- "file: ${file#$profile_home/}"
    assert_equal "$exit_code" "0"
    assert_not_empty "$output"
    assert_empty "$(print -r -- "$output" | sort | uniq -d)"
  done
}

# profile install and cleanup hand brew the files joined end to end, so every file
# together must evaluate. Each file that installs from sha1n/tap taps it, so the
# joined list names that tap once per such file.
function test_concatenation() {
  test_case_title

  local -a files=(${(f)"$(all_files)"})
  assert_not_empty "${files[*]}"
  local output exit_code
  output="$(brew_bundle_list =(cat "${files[@]}"))"
  exit_code="$?"

  assert_equal "$exit_code" "0"
  local file each=""
  for file in "${files[@]}"; do
    each+="$(brew_bundle_list "$file")"$'\n'
  done
  assert_equal "$(print -r -- "$output" | LC_ALL=C sort)" "$(print -rn -- "$each" | LC_ALL=C sort)"
  assert_empty "$(print -r -- "$output" | grep -vx 'sha1n/tap' | sort | uniq -d)"
}

setup
run_test test_brewfile_layout
run_test test_tiers_known_to_the_script
run_test test_brewfile_lines
run_test test_no_duplicate_entries
run_test test_sha1n_tap
run_test test_no_runtime_formulae
run_test test_nvim_sync_toolchain_reaches_dev
if [[ -z "$brew_bin" ]]; then
  echo "# brew is not on PATH; skipping Brewfile evaluation cases"
else
  run_test test_profile_files_evaluate
  run_test test_concatenation
  # A fresh cache, never the caller's, so the case reads no state of the machine; brew
  # fills it from the network. git always has a formula, so a failed lookup of it means
  # that the index cannot be downloaded, not that a runtime is missing.
  api_cache_dir="$(mktemp -d "${TMPDIR:-/tmp}/brewfile_test_api.XXXXXX")"
  if homebrew_formula_of git >/dev/null; then
    run_test test_no_runtime_formulae_by_homebrew_name
  else
    echo "# Homebrew cannot download its formula index; skipping the Homebrew-name runtime case"
  fi
  rm -rf "$api_cache_dir"
fi
cleanup
finish_tests
