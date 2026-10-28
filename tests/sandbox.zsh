# Sandbox contract for every *.test.sh: the runner gives an empty temporary $HOME,
# setup refuses any other $HOME, and cleanup removes it only when the fingerprint
# proves that this file created its content.

source "$__ZSH_SCRIPTEST_HOME/matchers.sh"
source "$__ZSH_SCRIPTEST_HOME/test_util.sh"

# install.sh resolves its own home with :a, so link targets are compared in that form.
profile_home="${SHA1N_PROFILE_TESTS_HOME:a:h}"
fingerprint=$(cat /dev/urandom | base64 | tr -dc '0-9a-zA-Z' | head -c50)

setup() {
  if [[ "$(ls -A $HOME)" ]]; then
    echo "the test \$HOME directory is expected to be a temporary empty directory"
    exit 1
  fi
  test_setup_title
  touch "$HOME/$fingerprint"
}

# Call before finish_tests: finish_tests exits on failure, and a skipped cleanup
# leaves the shared sandbox HOME dirty for the next test file.
cleanup() {
  test_teardown_title
  assert_file_exists "$HOME/$fingerprint"
  if [[ -f "$HOME/$fingerprint" ]]; then
    echo
    rm -rf "$HOME"
    mkdir -p "$HOME"
  fi
}

# Each case must start from a HOME that holds only the fingerprint, since a
# case that fails by running a full install would otherwise leak into the next.
reset_home() {
  find "$HOME" -mindepth 1 -maxdepth 1 ! -name "$fingerprint" -exec rm -rf {} +
}

# Prints the tier files of <brew_dir>, one per line, in chain order: ascending <N> of
# tiers/<N>-<name>.Brewfile, compared as numbers. The file names are the only list of
# profiles, so tests read them instead of holding a copy that could drift.
tier_files_of() {
  local -a files=("$1"/tiers/*.Brewfile(Nn))
  (( ${#files} == 0 )) || print -rl -- "${files[@]}"
}

# Prints the add-on files of <brew_dir>, one per line, in name order.
addon_files_of() {
  local -a files=("$1"/addons/*.Brewfile(N))
  (( ${#files} == 0 )) || print -rl -- "${files[@]}"
}

# Prints the profile name of a tier or add-on file: its base name without the
# .Brewfile suffix and without the <N>- prefix of a tier.
profile_name_of() {
  setopt local_options extended_glob
  local name="${1:t:r}"
  print -r -- "${name#[0-9]##-}"
}
