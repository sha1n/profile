#!/usr/bin/env zsh

source "$SHA1N_PROFILE_TESTS_HOME/sandbox.zsh"
source "$SHA1N_PROFILE_TESTS_HOME/install_helpers.zsh"

function test_existing_agent_config_replaced_at_end_of_input() {
  test_case_title
  reset_home

  mkdir -p "$HOME/.claude"
  print "OLD CONTENT" >"$HOME/.claude/CLAUDE.md"

  env -i HOME="$HOME" PATH="$PATH" TERM=dumb zsh "$install_script" </dev/null >/dev/null 2>&1

  assert_equal "$(readlink "$HOME/.claude/CLAUDE.md")" "$profile_home/agents/AGENTS.md"
}

write_brew_stub() {
  cat >"$1/brew" <<'EOF'
#!/bin/sh
case "$1" in
  --prefix) echo /opt/homebrew ;;
esac
exit 0
EOF
  chmod +x "$1/brew"
}

last_error_line() {
  print -r -- "$1" | grep 'ERROR' | tail -n 1
}

section_background() {
  env -i HOME="$HOME" PATH="$PATH" TERM=xterm-256color zsh -fc "print -nP '%K{blue}'"
}

# Prints the lines of the Homebrew shellenv section: after its title, up to the next title.
# Other steps also log SUCCESS lines, so the check must stay within this section.
shellenv_section_lines() {
  local background="$(section_background)"
  local in_section=false
  local line
  for line in "${(@f)1}"; do
    if [[ "$line" == *"$background"* ]]; then
      [[ "$line" == *"Homebrew shellenv"* ]] && in_section=true || in_section=false
    elif [[ "$in_section" == true ]]; then
      print -r -- "$line"
    fi
  done
}

# Two runs: the first prints a section title for each step and adds the shellenv line
# (macOS only); the second keeps one line and warns instead.
function test_sections_and_zprofile_brew_shellenv() {
  test_case_title
  reset_home

  # A stub brew keeps the case independent of whether Homebrew is installed on the runner.
  local stub_dir
  stub_dir="$(mktemp -d)"
  write_brew_stub "$stub_dir"

  local first_output second_output first_count second_count zprofile_created=false
  first_output="$(env -i HOME="$HOME" PATH="$stub_dir:$PATH" TERM=xterm-256color zsh "$install_script" </dev/null 2>&1)"
  first_count="$(grep -c 'brew shellenv' "$HOME/.zprofile" 2>/dev/null)"
  second_output="$(env -i HOME="$HOME" PATH="$stub_dir:$PATH" TERM=xterm-256color zsh "$install_script" </dev/null 2>&1)"
  second_count="$(grep -c 'brew shellenv' "$HOME/.zprofile" 2>/dev/null)"
  [[ -e "$HOME/.zprofile" ]] && zprofile_created=true

  # Removed before asserting because a failed assertion exits the case.
  rm -rf "$stub_dir"

  local background="$(section_background)"
  local -a lines=("${(@f)first_output}")
  local -a titles=("${(@M)lines:#*${background}*}")
  local titles_text="${(L)${(F)titles}}"
  assert_not_empty "$background"
  assert_equal "$(( ${#titles} >= 8 ))" "1"
  local keyword
  for keyword in dotfiles director zprofile zshrc agent neovim mise bytecode; do
    assert_contains "$titles_text" "$keyword"
  done

  if [[ "$OSTYPE" == darwin* ]]; then
    assert_equal "$first_count" "1"
    assert_equal "$second_count" "1"
    assert_match "$(shellenv_section_lines "$first_output")" 'SUCCESS:'
    local second_section="$(shellenv_section_lines "$second_output")"
    assert_not_contains "$second_section" "SUCCESS:"
    assert_match "$second_section" 'WARNING:'
  else
    assert_equal "$zprofile_created" "false"
  fi
}

# Runs from $HOME, which is not a git repository, so the submodule step must not depend on the caller's directory.
function test_clean_runs_exit_0() {
  test_case_title
  reset_home

  pushd -q "$HOME"
  run_install_with_rc
  local first_rc="$install_rc" first_out="$install_out"
  run_install_with_rc
  local second_rc="$install_rc" second_out="$install_out"
  popd -q

  assert_equal "$first_rc" "0"
  assert_equal "$second_rc" "0"
  assert_empty "$(print -r -- "$first_out"$'\n'"$second_out" | grep -i 'submodule' | grep -E 'ERROR|WARNING')"
}

function test_declined_prompts_exit_0() {
  test_case_title
  reset_home

  local -a targets=("$HOME/.agents/AGENTS.md" "$HOME/.claude/CLAUDE.md" "$HOME/.codex/AGENTS.md")
  local target
  for target in "${targets[@]}"; do
    mkdir -p "${target:h}"
    print -n "MINE" >"$target"
  done

  print -n 'n\nn\nn\n' | env -i HOME="$HOME" PATH="$PATH" TERM=dumb zsh "$install_script" >/dev/null 2>&1
  local rc=$?

  assert_equal "$rc" "0"
  for target in "${targets[@]}"; do
    assert_equal "$( [[ -L "$target" ]] && print link || print file )" "file"
    assert_equal "$(cat "$target")" "MINE"
  done
}

# Each row blocks one step: its error names the path, the remaining steps run, and the last error names the step.
function test_step_failure_fails_install() {
  test_case_title

  local row title blocker named stub_dir
  # <step title>|<what blocks the step>|<path or word that the error names>
  local -a rows=(
    'Submodules|git-stub|submodules'
    'Dotfiles|ln-stub|.gitconfig'
    'Directories|local-file|.local/bin'
    'Shell rc (~/.zshrc)|zshrc-dir|.zshrc'
    'Agent instructions|claude-file|.claude'
    'Neovim|config-file|.config'
    'Homebrew shellenv (~/.zprofile)|zprofile-dir|.zprofile'
  )
  for row in "${rows[@]}"; do
    IFS='|' read -r title blocker named <<<"$row"
    print -r -- "row: $title"
    if [[ "$blocker" == zprofile-dir && "$OSTYPE" != darwin* ]]; then
      print -r -- "# skipped: macOS only"
      continue
    fi
    reset_home
    stub_dir="$(mktemp -d)"
    case "$blocker" in
      git-stub) write_failing_stub "$stub_dir" git --init ;;
      ln-stub) write_failing_stub "$stub_dir" ln .gitconfig ;;
      local-file) print -n "FILE" >"$HOME/.local" ;;
      zshrc-dir) mkdir "$HOME/.zshrc" ;;
      claude-file) print -n "FILE" >"$HOME/.claude" ;;
      # A file where ~/.config must go: neither the directory nor the link can be made.
      config-file) print -n "FILE" >"$HOME/.config" ;;
      # Homebrew must be found, or the step is a skip.
      zprofile-dir) mkdir "$HOME/.zprofile" && write_brew_stub "$stub_dir" ;;
    esac

    run_install_with_rc "$stub_dir"
    # Removed before asserting because a failed assertion exits the case.
    rm -rf "$stub_dir"

    local last_error="$(last_error_line "$install_out")"
    assert_equal "$install_rc" "1"
    assert_not_empty "$(errors_naming "$install_out" "$named")"
    assert_contains "$install_out" "Bytecode"
    assert_contains "$last_error" "failed steps:"
    assert_contains "$last_error" "$title"
  done
}

function test_sourced_failure_returns_1() {
  test_case_title
  reset_home
  print -n "FILE" >"$HOME/.local"

  local output
  output="$(env -i HOME="$HOME" PATH="$PATH" TERM=dumb zsh -fc 'source "$1" </dev/null >/dev/null 2>&1; print "rc=$?"; print after' zsh "$install_script" 2>&1)"

  assert_contains "$output" "rc=1"
  assert_contains "$output" "after"
}

nvim_config="$HOME/.config/nvim"
nvim_repo_config="$profile_home/config/nvim"

# Prints what is at <path>: link:<target>, dir, file or none.
path_kind() {
  if [[ -L "$1" ]]; then
    print -r -- "link:$(readlink "$1")"
  elif [[ -d "$1" ]]; then
    print -r -- "dir"
  elif [[ -e "$1" ]]; then
    print -r -- "file"
  else
    print -r -- "none"
  fi
}

# The config directory is linked as a whole. The link may dangle, as the repo of the
# run under test may predate config/nvim, so the checks read the link, not its target.
function test_neovim_links_config_directory() {
  test_case_title

  local row state
  # <state of ~/.config/nvim before the run>
  for row in 'no-config-dir' 'absent' 'linked'; do
    state="$row"
    print -r -- "row: $state"
    reset_home
    case "$state" in
      absent) mkdir -p "$HOME/.config" ;;
      linked) mkdir -p "$HOME/.config" && ln -s "$nvim_repo_config" "$nvim_config" ;;
    esac

    run_install_with_rc

    assert_equal "$install_rc" "0"
    assert_equal "$(path_kind "$nvim_config")" "link:$nvim_repo_config"
    assert_empty "$(print -r -- "$HOME"/.config/nvim.bak.*(DN))"
    assert_equal "$(path_kind "$HOME/init.lua")" "none"
  done
}

# A directory from the old layout, whose init.lua links into the repo, is kept as a
# backup and replaced by the link.
function test_neovim_migrates_old_layout() {
  test_case_title

  local target
  local -a backups
  for target in "$profile_home/dotfiles/init.lua" "$nvim_repo_config/init.lua"; do
    print -r -- "row: init.lua -> $target"
    reset_home
    mkdir -p "$nvim_config"
    ln -s "$target" "$nvim_config/init.lua"
    print -r -- "LOCK" >"$nvim_config/lazy-lock.json"

    run_install_with_rc
    backups=("$HOME"/.config/nvim.bak.*(DN))

    assert_equal "$install_rc" "0"
    assert_equal "$(path_kind "$nvim_config")" "link:$nvim_repo_config"
    assert_equal "${#backups}" "1"
    assert_match "${backups[1]:t}" '^nvim\.bak\.[0-9]+$'
    assert_equal "$(path_kind "${backups[1]}")" "dir"
    assert_equal "$(cat "${backups[1]}/lazy-lock.json" 2>/dev/null)" "LOCK"
    assert_equal "$(path_kind "${backups[1]}/init.lua")" "link:$target"
  done
}

# Anything else at ~/.config/nvim belongs to the user: the step warns and leaves it.
function test_neovim_skips_foreign_config() {
  test_case_title

  local row expected
  # <what is at ~/.config/nvim>
  for row in 'file' 'dir' 'dir-own-init' 'link-elsewhere'; do
    print -r -- "row: $row"
    reset_home
    mkdir -p "$HOME/.config"
    case "$row" in
      file) print -n "MINE" >"$nvim_config" ;;
      dir) mkdir "$nvim_config" && print -n "MINE" >"$nvim_config/mine.lua" ;;
      dir-own-init) mkdir "$nvim_config" && print -n "MINE" >"$nvim_config/init.lua" ;;
      link-elsewhere) mkdir "$HOME/elsewhere" && ln -s "$HOME/elsewhere" "$nvim_config" ;;
    esac
    expected="$(path_kind "$nvim_config")"

    run_install_with_rc

    assert_equal "$install_rc" "0"
    assert_equal "$(path_kind "$nvim_config")" "$expected"
    assert_empty "$(print -r -- "$HOME"/.config/nvim.bak.*(DN))"
    assert_not_empty "$(print -r -- "$install_out" | grep 'WARNING' | grep -F '.config/nvim')"
    case "$row" in
      file) assert_equal "$(cat "$nvim_config")" "MINE" ;;
      dir)
        assert_equal "$(cat "$nvim_config/mine.lua")" "MINE"
        assert_equal "$(path_kind "$nvim_config/init.lua")" "none"
        ;;
      dir-own-init) assert_equal "$(path_kind "$nvim_config/init.lua")" "file" ;;
      link-elsewhere) assert_empty "$(print -r -- "$HOME"/elsewhere/*(DN))" ;;
    esac
  done
}

setup
run_test test_existing_agent_config_replaced_at_end_of_input
run_test test_sections_and_zprofile_brew_shellenv
run_test test_clean_runs_exit_0
run_test test_declined_prompts_exit_0
run_test test_step_failure_fails_install
run_test test_neovim_links_config_directory
run_test test_neovim_migrates_old_layout
run_test test_neovim_skips_foreign_config
run_test test_sourced_failure_returns_1
cleanup
finish_tests
