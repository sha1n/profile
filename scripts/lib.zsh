#!/usr/bin/env zsh
autoload -U colors && colors

function __profile_log_error() {
  __profile_log_log "red" "error" $1
}

function __profile_log_warn() {
  __profile_log_log "yellow" "warn" $1
}

function __profile_log_info() {
  __profile_log_log "cyan" "info" $1
}

function __profile_log_success() {
  __profile_log_log "green" "success" $1
}

function __profile_log_log() {
  printf "$fg[$1]%7s:$reset_color %s\n" "$2" "$3"
}
