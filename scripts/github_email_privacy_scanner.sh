#!/usr/bin/env zsh

SHA1N_PROFILE_SCRIPTS="${${(%):-%x}:a:h}"
source "$SHA1N_PROFILE_SCRIPTS/lib.zsh"

migdir="$CODE/migration"
organizations=("sha1n" "sha1n-playground")
emails=($@)

################################################################################

function scan_org() {
  local org="$1"
  # listing only non-fork repos
  repos=($(gh repo list $org --source | awk -F' ' '{print $1}' | awk -F/ '{print $2}' | sort))
  for repo in "${repos[@]}"; do
    scan_repo "$org" "$repo"
  done
}

function scan_repo() {
  local org="$1"
  local repo="$2"

  __profile_log_info "processing repo $org/$repo"

  cd "$migdir"
  git clone "git@github.com:$org/$repo.git" >/dev/null 2>&1
  cd "$repo"

  for email in "${emails[@]}"; do
    __profile_log_info "checking $email"
    local count=$(git log --pretty=format:"%h %ce %ae" | grep "$email" | wc -l | xargs)

    if test "$count" -gt "0"; then
      __profile_log_error "email '$email' found $count times in $repo"
    fi
  done

  __profile_log_info "done!"
}

function scan_orgs() {
  local orgs=("$@")
  # listing only non-fork repos
  for org in "${orgs[@]}"; do
    scan_org "$org"
  done
}

mkdir -p "$migdir"
scan_orgs "${organizations[@]}"
