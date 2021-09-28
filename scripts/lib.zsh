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
