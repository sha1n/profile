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

# Prints the names of the `known` line of <brewfile> on one line, in file order.
# The Brewfile is the only list of profiles, so tests read it instead of holding a
# copy that could drift. Same pattern as __profile_cmd_known_profiles in scripts/profile.
known_profiles_of() {
  local brewfile="$1" line
  local known_pattern='^known = %w\[([a-z. ]+)\]$'
  if [[ -r "$brewfile" ]]; then
    for line in "${(@f)$(<"$brewfile")}"; do
      if [[ "$line" =~ $known_pattern ]]; then
        print -r -- "${(j: :)${=match[1]}}"
        return 0
      fi
    done
  fi
  print -r -- "no 'known' profile list in $brewfile" >&2
  return 1
}
