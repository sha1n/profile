#!/usr/bin/env zsh

source "$SHA1N_PROFILE_TESTS_HOME/sandbox.zsh"
# Resolved before any child narrows PATH.
git_bin="$(command -v git)"
zsh_bin="$(command -v zsh)"
child_path="${git_bin:h}:${zsh_bin:h}:/usr/bin:/bin"
# Git 2.38.1 and later block the file transport for submodules, and the sandbox HOME has
# no .gitconfig, so the identity and the transport come from the environment. The system
# config is left out, because a machine setting could change what the step sees.
git_env=(
  HOME="$HOME" PATH="$child_path" TERM=dumb GIT_CONFIG_NOSYSTEM=1
  GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=protocol.file.allow GIT_CONFIG_VALUE_0=always
  GIT_AUTHOR_NAME=profile-test GIT_AUTHOR_EMAIL=profile-test@example.invalid
  GIT_COMMITTER_NAME=profile-test GIT_COMMITTER_EMAIL=profile-test@example.invalid
)
upstream="$HOME/upstream"
clone="$HOME/clone"
kept_name="keep"
# A name with a slash, like zsh-plugins/fzf-tab in this repo.
orphan_name="plugins/gone"

git_in() {
  env -i "${git_env[@]}" "$git_bin" "$@"
}

# Builds the submodule repos keep and gone, an upstream superproject that has both and a
# copy of scripts/, and a clone of it with its submodules. profile resolves its repo from
# its own path with :A, so the upstream holds a copy of scripts/, not a link to it.
build_repos() {
  reset_home
  local name
  for name in keep gone; do
    git_in init -q -b master "$HOME/src/$name"
    print -r -- "$name" >"$HOME/src/$name/README"
    git_in -C "$HOME/src/$name" add README
    git_in -C "$HOME/src/$name" commit -q -m "init $name"
  done
  git_in init -q -b master "$upstream"
  cp -R "$profile_home/scripts" "$upstream/scripts"
  git_in -C "$upstream" submodule add -q "$HOME/src/keep" "$kept_name"
  git_in -C "$upstream" submodule add -q "$HOME/src/gone" "$orphan_name"
  git_in -C "$upstream" add scripts
  git_in -C "$upstream" commit -q -m "init upstream"
  git_in clone -q --recurse-submodules "$upstream" "$clone"
}

# Removes the gone submodule upstream, so the next profile update pulls its removal.
# With <replacement>, the same commit tracks a file with that content at its path.
remove_orphan_upstream() {
  git_in -C "$upstream" rm -q "$orphan_name"
  if (( $# )); then
    mkdir -p "$upstream/$orphan_name"
    print -r -- "$1" >"$upstream/$orphan_name/file"
    git_in -C "$upstream" add "$orphan_name/file"
  fi
  git_in -C "$upstream" commit -q -m "remove $orphan_name"
}

run_update() {
  (cd "$HOME" && env -i "${git_env[@]}" "$clone/scripts/profile" update) \
    >"$HOME/out" 2>"$HOME/err"
  rc=$?
  out="$(<"$HOME/out")"
  err="$(<"$HOME/err")"
}

config_section_of() {
  git_in -C "$clone" config --local --get-regexp "^submodule\.${1//./\\.}\." 2>/dev/null
}

# The stdout lines after the section title, or nothing when there is no title; the title
# itself is checked in profile_command.test.sh.
output_after_title() {
  [[ "$out" == *"Orphaned submodules"* ]] || return 0
  local after="${out#*Orphaned submodules}"
  [[ "$after" == *$'\n'* ]] && print -r -- "${after#*$'\n'}"
}

assert_kept_submodule_intact() {
  assert_file_exists "$clone/$kept_name/README"
  assert_dir_exists "$clone/.git/modules/$kept_name"
  assert_not_empty "$(config_section_of "$kept_name")"
  assert_not_contains "$out$err" "orphaned submodule '$kept_name'"
}

assert_orphan_removed() {
  local name="$1"
  assert_equal "$rc" "0"
  assert_dir_not_exists "$clone/.git/modules/$name"
  assert_empty "$(config_section_of "$name")"
  assert_contains "$out" "removed orphaned submodule '$name'"
  assert_not_contains "$err" "kept orphaned submodule '$name'"
  assert_kept_submodule_intact
}

assert_orphan_kept() {
  local name="$1"
  assert_equal "$rc" "0"
  assert_dir_exists "$clone/$name"
  assert_dir_exists "$clone/.git/modules/$name"
  assert_not_empty "$(config_section_of "$name")"
  assert_contains "$err" "kept orphaned submodule '$name'"
  assert_not_contains "$out" "removed orphaned submodule '$name'"
  assert_kept_submodule_intact
}

function test_update_with_no_upstream_change() {
  test_case_title
  build_repos
  run_update

  assert_equal "$rc" "0"
}

function test_clean_orphan() {
  test_case_title
  build_repos
  remove_orphan_upstream
  run_update

  assert_orphan_removed "$orphan_name"
  assert_dir_not_exists "$clone/$orphan_name"
  assert_dir_not_exists "$clone/${orphan_name:h}"
  assert_dir_not_exists "$clone/.git/modules/${orphan_name:h}"
}

function test_orphan_with_uncommitted_change() {
  test_case_title
  build_repos
  remove_orphan_upstream
  print -r -- "local change" >>"$clone/$orphan_name/README"
  run_update

  assert_orphan_kept "$orphan_name"
  assert_contains "$(<"$clone/$orphan_name/README")" "local change"
}

function test_orphan_with_untracked_file() {
  test_case_title
  build_repos
  remove_orphan_upstream
  print -r -- "notes" >"$clone/$orphan_name/notes.txt"
  run_update

  assert_orphan_kept "$orphan_name"
  assert_file_exists "$clone/$orphan_name/notes.txt"
}

function test_orphan_with_unpushed_commit() {
  test_case_title
  build_repos
  remove_orphan_upstream
  print -r -- "unpushed" >>"$clone/$orphan_name/README"
  git_in -C "$clone/$orphan_name" commit -q -a -m "unpushed"
  run_update

  assert_orphan_kept "$orphan_name"
  assert_contains "$(<"$clone/$orphan_name/README")" "unpushed"
}

function test_orphan_with_stash() {
  test_case_title
  build_repos
  remove_orphan_upstream
  print -r -- "stashed" >>"$clone/$orphan_name/README"
  git_in -C "$clone/$orphan_name" stash -q
  run_update

  assert_orphan_kept "$orphan_name"
  assert_not_empty "$(git_in -C "$clone/$orphan_name" stash list)"
}

function test_orphan_with_deleted_working_tree() {
  test_case_title
  build_repos
  remove_orphan_upstream
  rm -rf "$clone/$orphan_name"
  run_update

  assert_orphan_removed "$orphan_name"
  assert_dir_not_exists "$clone/$orphan_name"
}

function test_orphan_with_only_config_section() {
  test_case_title
  build_repos
  local name="fake/only"
  git_in -C "$clone" config --local "submodule.$name.url" https://example.invalid/x.git
  run_update

  assert_orphan_removed "$name"
  assert_file_exists "$clone/$orphan_name/README"
  assert_dir_exists "$clone/.git/modules/$orphan_name"
  assert_not_empty "$(config_section_of "$orphan_name")"
}

# A pull alone leaves the orphan's .git file beside the new tracked file, so that path
# would test the untracked-file check again. Deleting the working tree first lets the pull
# put only the tracked file there, which is the state this case needs.
function test_orphan_path_used_by_other_content() {
  test_case_title
  build_repos
  remove_orphan_upstream "tracked content"
  rm -rf "$clone/$orphan_name"
  run_update

  assert_orphan_removed "$orphan_name"
  assert_equal "$(<"$clone/$orphan_name/file")" "tracked content"
  assert_empty "$(git_in -C "$clone" status --porcelain)"
}

# The pull leaves the orphan's .git file, which points to the orphan, beside a file that
# the superproject now tracks; the orphan sees that file as untracked, so it is kept and
# the tracked file survives.
function test_orphan_path_shared_with_tracked_file() {
  test_case_title
  build_repos
  remove_orphan_upstream "tracked content"
  run_update

  assert_orphan_kept "$orphan_name"
  assert_equal "$(<"$clone/$orphan_name/file")" "tracked content"
}

function test_no_orphans() {
  test_case_title
  build_repos
  print -r -- "change" >"$upstream/change.txt"
  git_in -C "$upstream" add change.txt
  git_in -C "$upstream" commit -q -m "change"
  run_update

  assert_equal "$rc" "0"
  assert_file_exists "$clone/change.txt"
  assert_file_exists "$clone/$orphan_name/README"
  assert_dir_exists "$clone/.git/modules/$orphan_name"
  assert_not_empty "$(config_section_of "$orphan_name")"
  assert_kept_submodule_intact
  assert_not_contains "$out$err" "orphaned submodule"
  assert_empty "$(output_after_title)"
}

setup
run_test test_update_with_no_upstream_change
run_test test_clean_orphan
run_test test_orphan_with_uncommitted_change
run_test test_orphan_with_untracked_file
run_test test_orphan_with_unpushed_commit
run_test test_orphan_with_stash
run_test test_orphan_with_deleted_working_tree
run_test test_orphan_with_only_config_section
run_test test_orphan_path_used_by_other_content
run_test test_orphan_path_shared_with_tracked_file
run_test test_no_orphans
cleanup
finish_tests
