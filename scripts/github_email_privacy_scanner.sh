#!/usr/bin/env zsh

autoload -U colors && colors

migdir="$CODE/migration"
organizations=("sha1n" "sha1n-playground")
emails=()

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

  echo "$fg[magenta]
> Processing repo "$org/$repo"
$reset_color"

  cd "$migdir"
  git clone "git@github.com:$org/$repo.git"
  cd "$repo"

  for email in "${emails[@]}"
  do
    local count=$(git log --pretty=format:"%h %ce %ae" | grep "$email" | wc -l | xargs)

    if test "$count" -gt "0";
    then
      echo "$fg[red] email '$email' found $count times in $repo"
    fi
  done

    echo "$fg[magenta]
> Done!$reset_color" 
}


function scan_orgs() {
  local orgs=("$@")
  # listing only non-fork repos
  for org in "${orgs[@]}"; do
    scan_org "$org"
  done
}

scan_orgs "${organizations[@]}"
