#!/usr/bin/env zsh

source "$SHA1N_PROFILE_TESTS_HOME/sandbox.zsh"
brew_dir="$profile_home/brew"
brew_bin="$(command -v brew)"
entry_keywords='tap|brew|cask|uv|mas|vscode|whalebrew|go|cargo|npm|flatpak|krew'
# Work-only apps and a few desktop apps are installed by hand; the runtimes come from
# mise, not Homebrew.
never_listed='slack zoom go nvm node maven pipx vim brave-browser claude codex cmux'
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

assert_lacks_listed() {
  local output="$1" entry
  for entry in ${=never_listed}; do
    assert_not_contains $'\n'"$output"$'\n' $'\n'"$entry"$'\n'
  done
  assert_empty "$(print -r -- "$output" | grep -E '^(python|openjdk)@' || true)"
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

# The order of the tier numbers is the chain: a tier applies every tier before it.
# Add-ons stand outside the chain: each applies only itself.
function test_profile_chain() {
  test_case_title

  local file
  local -a tiers=() addons=()
  for file in ${(f)"$(tier_files_of "$brew_dir")"}; do
    tiers+=("$(profile_name_of "$file")")
  done
  for file in ${(f)"$(addon_files_of "$brew_dir")"}; do
    addons+=("$(profile_name_of "$file")")
  done
  assert_equal "${(j: :)tiers}" "essentials dev dev.home"
  assert_equal "${(j: :)addons}" "audio"
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

# Hand-installed apps and the language runtimes (mise owns them) are listed by no profile.
# Neovim is in essentials; its toolchain belongs to dev, whose profile install runs plugin
# sync.
function test_package_lists() {
  test_case_title

  local -A expected=(
    essentials 'sha1n/tap starship font-jetbrains-mono-nerd-font coreutils gnu-time parallel rsync watch wget tree bat sha1n/tap/bert fzf jq yq ripgrep poppler neovim sublime-text git gh'
    dev 'sha1n/tap mise uv make go-task shellcheck openspec antigravity-cli acdc-mcp repulse gopls basedpyright typescript lua-language-server stylua tree-sitter-cli'
    dev.home 'llvm goreleaser git-lfs git-filter-repo gnupg warp docker-desktop visual-studio-code orca'
    audio 'blackhole-2ch au-lab'
  )
  local file name output exit_code
  assert_not_empty "$(all_files)"
  for file in ${(f)"$(all_files)"}; do
    name="$(profile_name_of "$file")"
    output="$(brew_bundle_list "$file")"
    exit_code="$?"

    print -r -- "file: ${file#$profile_home/}"
    assert_equal "$exit_code" "0"
    assert_equal "$(print -r -- "$output" | LC_ALL=C sort)" \
      "$(print -rl -- ${=expected[$name]} | LC_ALL=C sort)"
    assert_empty "$(print -r -- "$output" | sort | uniq -d)"
    assert_lacks_listed "$output"
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
  assert_lacks_listed "$output"
}

setup
run_test test_brewfile_layout
run_test test_profile_chain
run_test test_brewfile_lines
run_test test_no_duplicate_entries
run_test test_sha1n_tap
if [[ -z "$brew_bin" ]]; then
  echo "# brew is not on PATH; skipping Brewfile evaluation cases"
else
  run_test test_package_lists
  run_test test_concatenation
fi
cleanup
finish_tests
