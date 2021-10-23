#!/usr/bin/env zsh
autoload -U colors && colors

function __profile_log_error() {
  __profile_log_log "red" "ERROR" $1
}

function __profile_log_warn() {
  __profile_log_log "yellow" "WARNING" $1
}

function __profile_log_info() {
  __profile_log_log "cyan" "INFO" $1
}

function __profile_log_success() {
  __profile_log_log "green" "SUCCESS" $1
}

function __profile_log_log() {
  printf "$fg[$1]%s:$reset_color %s\n" "$2" "$3"
}

#
# Searches the current directory ancestors tree for the specified file.
# If found, returns the file path relative to the current directory, otherwise returns nothing.
#
function __profile_search_ancestor_tree() {
  local file_name="$1"
  local dir="$PWD"
  while [[ ! -f "$dir/$file_name" ]]; do
    if [[ "$(realpath $dir)" == "/" ]]; then
      break
    fi
    dir="$dir/.."
  done

  if [[ -f "$dir/$file_name" ]]; then
    echo "$dir/$file_name"
  fi
}
