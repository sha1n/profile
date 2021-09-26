#!/usr/bin/env zsh

SHA1N_PROFILE_SCRIPTS="${${(%):-%x}:a:h}"
source "$SHA1N_PROFILE_SCRIPTS/lib.zsh"

migdir="$CODE/migration"
organization="sha1n-playground"

################################################################################

function user_quit() {
  echo "\nOkay... Bye!"
  exit 0
}

function validate() {
  echo "$fg[red]
 PLEASE READ
 -----------
$reset_color
 This script is going to rewrite git repo(s) history. This process is going to change historic commit hashes, 
 which will result in stale refs like tags, PRs branches and anything that relies on hashes.

$fg[red]
- Please make sure you fully understand the consequences of this operation before proceeding
- Consider trying this on a single test repository before running on the rest
- Is it highly recommended that you merge/close all PR before proceeding
$reset_color
"

  if ! read -q "REPLY?Do you want to proceed? [Y/n]: "; then
    user_quit
  fi
  echo "\n"

  if [[ ! -f "$migdir/.mailmap" ]]; then
    __profile_log_error "mailmap file doesn't exist: $migdir/.mailmap"
    exit 1
  else
    __profile_log_info "using mailmap file:"
    cat "$migdir/.mailmap"
    echo "\n"

    if read -q "REPLY?Is this ok? [Y/n]: "; then
      __profile_log_info "\nproceeding..."
      mkdir -p "$migdir"
    else
      user_quit
    fi
  fi
}

function migrate() {
  # listing only non-fork repos
  repos=($(gh repo list $organization --source | awk -F' ' '{print $1}' | awk -F/ '{print $2}' | sort))
  for repo in "${repos[@]}"; do
    handle_repo "$repo"
  done
}

function handle_repo() {
  local repo="$1"

  __profile_log_info "processing repo $repo"

  cd "$migdir"

  __profile_log_info "going to migrate $repo..."
  git clone "git@github.com:$organization/$repo.git"

  cd "$repo"

  __profile_log_info "rewriting history..."
  git filter-repo --mailmap "$migdir/.mailmap"

  __profile_log_info "pushing $repo..."
  git remote add "origin" "git@github.com:$organization/$repo.git"
  git push --force origin $(git branch --show-current) && cd "$migdir" && rm -rf "$repo"

  if [[ "$?" == "0" ]]; then
    __profile_log_success "done!"
  else 
    __profile_log_error ">>> FAILED! <<<"
  fi
}

validate
migrate
