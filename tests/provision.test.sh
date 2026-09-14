#!/usr/bin/env zsh

source "$__ZSH_SCRIPTEST_HOME/matchers.sh"
source "$__ZSH_SCRIPTEST_HOME/test_util.sh"
fingerprint=$(cat /dev/urandom | base64 | tr -dc '0-9a-zA-Z' | head -c50)

setup() {
  if [[ "$(ls -A $HOME)" ]]; then
    echo "the test \$HOME directory is expected to be a temporary empty directory"
    exit 1
  else
    test_setup_title
    touch "$HOME/$fingerprint"
    source "$SHA1N_PROFILE_TESTS_HOME/../install.sh" --no-provision
    source "$SHA1N_PROFILE_TESTS_HOME/../load.zsh"
  fi
}

cleanup() {
  test_teardown_title
  assert_file_exists "$HOME/$fingerprint"
  if [[ -f "$HOME/$fingerprint" ]]; then
    echo
    rm -rf "$HOME"
    mkdir -p "$HOME"
  fi
}

function test_all_submodules_use_https() {
  test_case_title

  local ssh_urls
  ssh_urls="$(grep -c 'url = git@' "$SHA1N_PROFILE_HOME/.gitmodules" || true)"
  assert_equal "$ssh_urls" "0"
}

function test_all_submodules_are_checked_out() {
  test_case_title

  # A bare '-' prefix in `git submodule status` means the submodule is not initialised.
  local uninitialised
  uninitialised="$(git -C "$SHA1N_PROFILE_HOME" submodule status | grep -c '^-' || true)"
  assert_equal "$uninitialised" "0"
}

function test_available_layers_discovered_by_glob() {
  test_case_title

  source "$SHA1N_PROFILE_HOME/provision/provision.zsh"
  local layers
  layers="$(__profile_provision_available_layers | sort | tr '\n' ' ')"
  assert_contains "$layers" "dev-go"
  assert_contains "$layers" "dev-java"
  assert_contains "$layers" "dev-node"
  assert_contains "$layers" "dev-ops"
  assert_contains "$layers" "dev-python"
  # essentials is implicit, never a selectable layer
  assert_not_contains "$layers" "essentials"
}

function test_validate_layer_rejects_unknown() {
  test_case_title

  source "$SHA1N_PROFILE_HOME/provision/provision.zsh"
  __profile_provision_validate_layer "dev-cobol" >/dev/null 2>&1
  assert_equal "$?" "1"

  __profile_provision_validate_layer "dev-go" >/dev/null 2>&1
  assert_equal "$?" "0"
}

function test_compose_always_includes_essentials() {
  test_case_title

  source "$SHA1N_PROFILE_HOME/provision/provision.zsh"
  local composed
  composed="$(__profile_provision_compose)"
  assert_contains "$composed" 'brew "coreutils"'
  assert_not_contains "$composed" 'brew "golangci-lint"'
}

function test_compose_appends_selected_layers() {
  test_case_title

  source "$SHA1N_PROFILE_HOME/provision/provision.zsh"
  local composed
  composed="$(__profile_provision_compose dev-go dev-node)"
  assert_contains "$composed" 'brew "coreutils"'
  assert_contains "$composed" 'brew "golangci-lint"'
  assert_contains "$composed" 'brew "yarn"'
  assert_not_contains "$composed" 'brew "poetry"'
}

function test_profile_flag_rejected_on_linux() {
  test_case_title

  # The Darwin boundary is what protects the dual-platform contract in AGENTS.md.
  if [[ "$OSTYPE" == darwin* ]]; then
    echo "  skipped on darwin"
    return 0
  fi

  zsh "$SHA1N_PROFILE_TESTS_HOME/../install.sh" --profile dev-go --no-provision >/dev/null 2>&1
  assert_equal "$?" "2"
}

function test_unknown_layer_rejected_on_darwin() {
  test_case_title

  if [[ "$OSTYPE" != darwin* ]]; then
    echo "  skipped off darwin"
    return 0
  fi

  local out
  out="$(zsh "$SHA1N_PROFILE_TESTS_HOME/../install.sh" --profile dev-cobol --no-provision 2>&1)"
  assert_equal "$?" "2"
  assert_contains "$out" "dev-cobol"
}

function test_no_provision_skips_homebrew() {
  test_case_title

  local out
  out="$(zsh "$SHA1N_PROFILE_TESTS_HOME/../install.sh" --no-provision --yes 2>&1)"
  assert_not_contains "$out" "provisioning packages"
}

function test_compose_prints_effective_brewfile() {
  test_case_title

  if [[ "$OSTYPE" != darwin* ]]; then
    echo "  skipped off darwin"
    return 0
  fi

  local out
  out="$(zsh "$SHA1N_PROFILE_TESTS_HOME/../install.sh" --compose --profile dev-go 2>/dev/null)"
  assert_equal "$?" "0"
  assert_contains "$out" 'brew "coreutils"'
  assert_contains "$out" 'brew "golangci-lint"'
  assert_not_contains "$out" 'brew "poetry"'
}

function test_check_is_non_mutating() {
  test_case_title

  if [[ "$OSTYPE" != darwin* ]]; then
    echo "  skipped off darwin"
    return 0
  fi

  # A fingerprint of installed state must be identical before and after --check.
  local before after
  before="$(brew list --formula --versions; brew list --cask --versions)"
  zsh "$SHA1N_PROFILE_TESTS_HOME/../install.sh" --check >/dev/null 2>&1
  after="$(brew list --formula --versions; brew list --cask --versions)"

  assert_equal "$before" "$after"
}

function test_check_does_not_link_dotfiles() {
  test_case_title

  rm -f "$HOME/.vimrc"
  zsh "$SHA1N_PROFILE_TESTS_HOME/../install.sh" --check --no-provision >/dev/null 2>&1
  assert_equal "$(test -e "$HOME/.vimrc" && echo present || echo absent)" "absent"
}

function test_neovim_relinks_a_foreign_symlink() {
  test_case_title

  local nvim_dir="$HOME/.config/nvim"
  local foreign="$HOME/foreign-init.lua"
  mkdir -p "$nvim_dir"
  print -r -- "-- not ours" >"$foreign"
  ln -sfn "$foreign" "$nvim_dir/init.lua"

  PROFILE_ASSUME_YES=1 setup_neovim >/dev/null 2>&1

  assert_equal "$(readlink "$nvim_dir/init.lua")" "$SHA1N_PROFILE_HOME/dotfiles/init.lua"
}

function test_neovim_preserves_a_real_file() {
  test_case_title

  local nvim_dir="$HOME/.config/nvim"
  mkdir -p "$nvim_dir"
  rm -f "$nvim_dir/init.lua"
  print -r -- "-- hand written" >"$nvim_dir/init.lua"

  PROFILE_ASSUME_YES=1 setup_neovim >/dev/null 2>&1

  # A regular file is the user's own work; never clobber it silently.
  assert_empty "$(readlink "$nvim_dir/init.lua" 2>/dev/null)"
  assert_contains "$(cat "$nvim_dir/init.lua")" "hand written"
}

function test_vscode_settings_not_linked_into_home_root() {
  test_case_title

  # dotfiles/ is linked by basename, so this file must be excluded from the loop.
  assert_equal "$(test -e "$HOME/vscode-settings.json" && echo present || echo absent)" "absent"
}

function test_vscode_settings_linked_to_application_support() {
  test_case_title

  if [[ "$OSTYPE" != darwin* ]]; then
    echo "  skipped off darwin"
    return 0
  fi

  local target="$HOME/Library/Application Support/Code/User/settings.json"
  assert_equal "$(readlink "$target")" "$SHA1N_PROFILE_HOME/dotfiles/vscode-settings.json"
}

function test_go_bin_on_path() {
  test_case_title

  assert_contains "$PATH" "$HOME/go/bin"
}

function test_solarized_colorscheme_is_tracked() {
  test_case_title

  # dotfiles/.vimrc:4 sets `colorscheme solarized`; the file must ship with the repo.
  assert_file_exists "$SHA1N_PROFILE_HOME/dotfiles/colors/solarized.vim"
}

function test_solarized_linked_where_vim_looks() {
  test_case_title

  # dotfiles/ is linked into $HOME by basename, which would put the colorscheme at
  # ~/solarized.vim where vim never looks. It is linked into ~/.vim/colors instead,
  # keeping vim's stock runtimepath and no repo path literal in .vimrc.
  assert_equal "$(readlink "$HOME/.vim/colors/solarized.vim")" "$SHA1N_PROFILE_HOME/dotfiles/colors/solarized.vim"
  assert_equal "$(test -e "$HOME/solarized.vim" && echo present || echo absent)" "absent"
}

function test_nvm_sourced_when_present() {
  test_case_title

  if ! command -v brew >/dev/null 2>&1 || [[ ! -s "$(brew --prefix nvm 2>/dev/null)/nvm.sh" ]]; then
    echo "  skipped: nvm not installed"
    return 0
  fi

  assert_equal "$(type -w nvm | cut -d: -f2 | tr -d ' ')" "function"
}

function test_toolchain_aliases_are_guarded() {
  test_case_title

  # Every toolchain-dependent alias group must sit behind a command -v guard, so
  # an essentials-only machine gets a clean shell rather than broken aliases.
  local aliases_file="$SHA1N_PROFILE_HOME/include/aliases"

  assert_contains "$(cat "$aliases_file")" 'command -v kubectl'
  assert_contains "$(cat "$aliases_file")" 'command -v mvn'
  assert_contains "$(cat "$aliases_file")" 'command -v yarn'
  assert_contains "$(cat "$aliases_file")" 'command -v docker'
}

function test_kubectl_alias_absent_without_kubectl() {
  test_case_title

  local out
  out="$(PATH=/usr/bin:/bin zsh -c 'source '"$SHA1N_PROFILE_HOME"'/include/aliases 2>/dev/null; alias k 2>&1' )"
  assert_not_contains "$out" "kubectl"
}

function test_bazel_integration_removed() {
  test_case_title

  assert_empty "$(grep -rn 'BAZEL_' "$SHA1N_PROFILE_HOME/include/" 2>/dev/null)"
  assert_empty "$(grep -n 'bazel_with_disk_cache_guard' "$SHA1N_PROFILE_HOME/include/functions" 2>/dev/null)"
  assert_equal "$(test -e "$SHA1N_PROFILE_HOME/dotfiles/.bazelrc" && echo present || echo absent)" "absent"
}

function test_export_openjdk_formula_resolves_a_cask_jdk() {
  test_case_title

  if [[ "$OSTYPE" != darwin* ]] || [[ ! -x /usr/libexec/java_home ]]; then
    echo "  skipped: no java_home"
    return 0
  fi

  local want
  want="$(/usr/libexec/java_home -v 25 2>/dev/null)" || { echo "  skipped: no JDK 25"; return 0 }

  export_openjdk_formula 25 >/dev/null 2>&1
  assert_equal "$?" "0"
  assert_equal "$JAVA_HOME" "$want"
}

function test_export_openjdk_formula_rejects_missing_version() {
  test_case_title

  export_openjdk_formula 8 >/dev/null 2>&1
  assert_equal "$?" "1"
}

function test_export_openjdk_formula_requires_an_argument() {
  test_case_title

  export_openjdk_formula >/dev/null 2>&1
  assert_equal "$?" "1"
}

function test_every_declared_entry_resolves() {
  test_case_title

  if [[ "$OSTYPE" != darwin* ]]; then
    echo "  skipped off darwin"
    return 0
  fi

  # Catches typos and undeclared taps (§6.3): installed state masks unresolvable
  # names, so a bad entry would only surface on a fresh machine.
  #
  # `brew bundle list` is NOT usable here — it echoes declared names without
  # resolving them and exits 0 even for a nonexistent formula. `brew info`
  # resolves, and takes every name in one batched call.
  local -a layers formulae casks
  layers=(${(f)"$(__profile_provision_available_layers)"})
  formulae=(${(f)"$(__profile_provision_declared_entries brew "${layers[@]}")"})
  casks=(${(f)"$(__profile_provision_declared_entries cask "${layers[@]}")"})

  assert_equal "$(( ${#formulae} > 0 ))" "1"
  assert_equal "$(( ${#casks} > 0 ))" "1"

  brew info --json=v2 --formula "${formulae[@]}" >/dev/null 2>&1
  assert_equal "$?" "0"

  brew info --json=v2 --cask "${casks[@]}" >/dev/null 2>&1
  assert_equal "$?" "0"

  # vscode entries cannot be resolved without `code` on PATH and a network round
  # trip per extension; they are deliberately not validated here.
}

function test_one_owning_layer_per_package() {
  test_case_title

  # Scoped to the six known files so a stray `brew bundle dump` artifact in
  # provision/ cannot trip this.
  local dupes
  dupes="$(grep -hE '^(brew|cask|vscode) ' \
    "$SHA1N_PROFILE_HOME/provision/essentials.Brewfile" \
    "$SHA1N_PROFILE_HOME"/provision/dev-*.Brewfile \
    | sort | uniq -d)"
  assert_empty "$dupes"
}

function test_essentials_satisfies_shell_hard_requirements() {
  test_case_title

  # Regression guard for §3.2: profile assumed ~20 tools it never installed.
  local essentials="$SHA1N_PROFILE_HOME/provision/essentials.Brewfile"
  local required=(git coreutils make fzf neovim jq git-lfs git-filter-repo gh glab bat ripgrep tree)
  local tool
  for tool in "${required[@]}"; do
    assert_contains "$(cat "$essentials")" "brew \"${tool}\""
  done
  assert_contains "$(cat "$essentials")" 'cask "font-menlo-for-powerline"'
}

function test_install_is_idempotent() {
  test_case_title

  # Only meetable once --yes exists (§6.2).
  zsh "$SHA1N_PROFILE_TESTS_HOME/../install.sh" --no-provision --yes >/dev/null 2>&1
  zsh "$SHA1N_PROFILE_TESTS_HOME/../install.sh" --no-provision --yes >/dev/null 2>&1
  assert_equal "$?" "0"
}

function test_linux_suite_unaffected() {
  test_case_title

  if [[ "$OSTYPE" == darwin* ]]; then
    echo "  skipped on darwin"
    return 0
  fi

  # provision/ must never be sourced on Linux.
  local out
  out="$(zsh "$SHA1N_PROFILE_TESTS_HOME/../install.sh" --yes 2>&1)"
  assert_equal "$?" "0"
  assert_not_contains "$out" "provisioning packages"
}

function test_declared_taps_are_trusted_before_install() {
  test_case_title

  if [[ "$OSTYPE" != darwin* ]]; then
    echo "  skipped off darwin"
    return 0
  fi

  # Homebrew 6 refuses to load a formula from an untrusted tap, so declaring a
  # tap in a Brewfile is not enough for `brew bundle install` to succeed.
  source "$SHA1N_PROFILE_HOME/provision/provision.zsh"
  local taps
  taps="$(__profile_provision_declared_taps | sort | tr '\n' ' ')"
  assert_contains "$taps" "sha1n/tap"
  assert_contains "$taps" "dapr/tap"
  assert_contains "$taps" "sqldef/sqldef"
}

function test_vim_colors_preserves_a_real_file() {
  test_case_title

  local colors_dir="$HOME/.vim/colors"
  mkdir -p "$colors_dir"
  rm -f "$colors_dir/solarized.vim"
  print -r -- "\" hand written" >"$colors_dir/solarized.vim"

  setup_vim_colors >/dev/null 2>&1

  # A regular file is the user's own work; never clobber it silently.
  assert_empty "$(readlink "$colors_dir/solarized.vim" 2>/dev/null)"
  assert_contains "$(cat "$colors_dir/solarized.vim")" "hand written"
}

function test_vim_colors_relinks_a_foreign_symlink() {
  test_case_title

  local colors_dir="$HOME/.vim/colors"
  local foreign="$HOME/foreign-solarized.vim"
  mkdir -p "$colors_dir"
  print -r -- "\" not ours" >"$foreign"
  ln -sfn "$foreign" "$colors_dir/solarized.vim"

  setup_vim_colors >/dev/null 2>&1

  assert_equal "$(readlink "$colors_dir/solarized.vim")" "$SHA1N_PROFILE_HOME/dotfiles/colors/solarized.vim"
}

function test_check_reports_managed_link_drift() {
  test_case_title

  # --check must cover every link install.sh manages, not just the flat dotfiles.
  # A link it creates but never verifies is drift that reports as clean.
  # Heal first: an earlier case removes ~/.vimrc, which would make --check report
  # drift for an unrelated reason and mask what this case is testing.
  zsh "$SHA1N_PROFILE_TESTS_HOME/../install.sh" --no-provision --yes >/dev/null 2>&1
  zsh "$SHA1N_PROFILE_TESTS_HOME/../install.sh" --check --no-provision >/dev/null 2>&1
  local healed_rc=$?

  # Restore before asserting: a failed matcher returns from the test, which would
  # otherwise leave the sandbox missing a link later cases depend on.
  local colors_link="$HOME/.vim/colors/solarized.vim"
  rm -f "$colors_link"
  zsh "$SHA1N_PROFILE_TESTS_HOME/../install.sh" --check --no-provision >/dev/null 2>&1
  local colors_rc=$?
  setup_vim_colors >/dev/null 2>&1

  local vscode_rc=1
  if [[ "$OSTYPE" == darwin* ]]; then
    rm -f "$HOME/Library/Application Support/Code/User/settings.json"
    zsh "$SHA1N_PROFILE_TESTS_HOME/../install.sh" --check --no-provision >/dev/null 2>&1
    vscode_rc=$?
    setup_vscode_settings >/dev/null 2>&1
  fi

  assert_equal "$healed_rc" "0"
  assert_equal "$colors_rc" "1"
  assert_equal "$vscode_rc" "1"
}

function test_provisioning_requires_homebrew() {
  test_case_title

  if [[ "$OSTYPE" != darwin* ]]; then
    echo "  skipped off darwin"
    return 0
  fi

  # Provisioning is main()'s first step, so a Mac without Homebrew must fail with
  # an actionable message rather than an opaque "command not found".
  local out
  out="$(PATH=/usr/bin:/bin provision_packages 2>&1)"
  assert_equal "$?" "1"
  assert_contains "$out" "Homebrew"
  assert_contains "$out" "--no-provision"
}

function test_install_trusts_taps_before_bundling() {
  test_case_title

  # The provisioning path is otherwise unexercised: nothing asserts that
  # main() actually reaches it, nor that trust precedes bundle install.
  # Sourced explicitly rather than Darwin-gated: install.sh does not source
  # provision/ off macOS, but the logic under test is platform-independent.
  source "$SHA1N_PROFILE_HOME/provision/provision.zsh"

  local stub_dir="$HOME/stub-bin"
  local log="$HOME/brew-calls.log"
  mkdir -p "$stub_dir"
  rm -f "$log"
  cat >"$stub_dir/brew" <<STUB
#!/usr/bin/env zsh
print -r -- "\$@" >>"$log"
# Drain stdin so the composing pipeline does not get EPIPE.
[[ "\$1" == "bundle" ]] && cat >/dev/null
exit 0
STUB
  chmod +x "$stub_dir/brew"

  PROFILE_BREW="$stub_dir/brew" __profile_provision_install dev-go >/dev/null 2>&1
  assert_equal "$?" "0"

  assert_file_exists "$log"
  local calls
  calls="$(cat "$log")"
  assert_contains "$calls" "trust sha1n/tap"
  assert_contains "$calls" "bundle install"

  # Ordering is load-bearing: Homebrew refuses to load a formula from an
  # untrusted tap, so a bundle install before trust fails on a fresh machine.
  local trust_line bundle_line
  trust_line="$(grep -n 'trust sha1n/tap' "$log" | head -1 | cut -d: -f1)"
  bundle_line="$(grep -n 'bundle install' "$log" | head -1 | cut -d: -f1)"
  assert_equal "$(( trust_line < bundle_line ))" "1"
}

function test_main_reaches_provisioning_on_darwin() {
  test_case_title

  if [[ "$OSTYPE" != darwin* ]]; then
    echo "  skipped off darwin"
    return 0
  fi

  # Guards against the provisioning step being dropped from main() unnoticed:
  # asserting only on absence (as --no-provision does) passes either way.
  local stub_dir="$HOME/stub-bin2"
  mkdir -p "$stub_dir"
  cat >"$stub_dir/brew" <<'STUB'
#!/usr/bin/env zsh
[[ "$1" == "bundle" ]] && cat >/dev/null
exit 0
STUB
  chmod +x "$stub_dir/brew"

  local out
  out="$(PROFILE_BREW="$stub_dir/brew" zsh "$SHA1N_PROFILE_TESTS_HOME/../install.sh" --yes 2>&1)"
  assert_equal "$?" "0"
  assert_contains "$out" "provisioning packages"
}

setup
run_test test_all_submodules_use_https
run_test test_all_submodules_are_checked_out
run_test test_available_layers_discovered_by_glob
run_test test_validate_layer_rejects_unknown
run_test test_compose_always_includes_essentials
run_test test_compose_appends_selected_layers
run_test test_profile_flag_rejected_on_linux
run_test test_unknown_layer_rejected_on_darwin
run_test test_no_provision_skips_homebrew
run_test test_compose_prints_effective_brewfile
run_test test_check_is_non_mutating
run_test test_check_does_not_link_dotfiles
run_test test_check_reports_managed_link_drift
run_test test_neovim_relinks_a_foreign_symlink
run_test test_neovim_preserves_a_real_file
run_test test_vscode_settings_not_linked_into_home_root
run_test test_vscode_settings_linked_to_application_support
run_test test_go_bin_on_path
run_test test_solarized_colorscheme_is_tracked
run_test test_solarized_linked_where_vim_looks
run_test test_vim_colors_preserves_a_real_file
run_test test_vim_colors_relinks_a_foreign_symlink
run_test test_nvm_sourced_when_present
run_test test_toolchain_aliases_are_guarded
run_test test_kubectl_alias_absent_without_kubectl
run_test test_bazel_integration_removed
run_test test_export_openjdk_formula_resolves_a_cask_jdk
run_test test_export_openjdk_formula_rejects_missing_version
run_test test_export_openjdk_formula_requires_an_argument
run_test test_every_declared_entry_resolves
run_test test_one_owning_layer_per_package
run_test test_essentials_satisfies_shell_hard_requirements
run_test test_install_is_idempotent
run_test test_linux_suite_unaffected
run_test test_declared_taps_are_trusted_before_install
run_test test_provisioning_requires_homebrew
run_test test_install_trusts_taps_before_bundling
run_test test_main_reaches_provisioning_on_darwin
finish_tests
cleanup
