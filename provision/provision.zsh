#!/usr/bin/env zsh
#
# Homebrew provisioning. Darwin only — install.sh must not source this on Linux.
#

__PROFILE_PROVISION_DIR="${${(%):-%x}:a:h}"

#
# Names of the selectable dev-* layers, one per line. essentials is implicit and
# never listed. Discovery is a glob so adding a layer needs no code change.
#
function __profile_provision_available_layers() {
  local f
  for f in "$__PROFILE_PROVISION_DIR"/dev-*.Brewfile(N); do
    print -r -- "${${f:t}%.Brewfile}"
  done
}

#
# Returns 0 if the named layer exists, 1 otherwise.
#
function __profile_provision_validate_layer() {
  local layer="$1"
  if [[ -f "$__PROFILE_PROVISION_DIR/${layer}.Brewfile" ]]; then
    return 0
  fi
  __profile_log_error "unknown profile layer: '${layer}'"
  __profile_log_error "available layers: $(__profile_provision_available_layers | tr '\n' ' ')"
  return 1
}

#
# Prints the effective Brewfile for the given layers to stdout. essentials is
# always first. Layers are standalone and purely additive — no instance_eval
# includes, which would evaluate essentials more than once.
#
function __profile_provision_compose() {
  local -a files=("$__PROFILE_PROVISION_DIR/essentials.Brewfile")
  local layer
  for layer in "$@"; do
    __profile_provision_validate_layer "$layer" || return 1
    files+=("$__PROFILE_PROVISION_DIR/${layer}.Brewfile")
  done
  cat "${files[@]}"
}

#
# 0 when every declared package is present, non-zero on drift. Never mutates.
# --no-upgrade is required: without it, outdated packages count as unmet and the
# check is permanently red.
#
function __profile_provision_check() {
  __profile_provision_compose "$@" | brew bundle check --no-upgrade --verbose --file=-
}

#
# As __profile_provision_check, but outdated packages count as drift.
#
function __profile_provision_check_upgrades() {
  __profile_provision_compose "$@" | brew bundle check --verbose --file=-
}

#
# Names the composed Brewfile declares for a given entry type (tap, brew, cask,
# vscode), one per line.
#
function __profile_provision_declared_entries() {
  local kind="$1"; shift
  __profile_provision_compose "$@" | awk -F'"' -v kind="$kind" '$0 ~ "^" kind " " {print $2}'
}

#
# Names of the taps the composed Brewfile declares, one per line.
#
function __profile_provision_declared_taps() {
  __profile_provision_declared_entries tap "$@"
}

#
# Homebrew 6 refuses to load a formula from an untrusted tap, and declaring a tap
# in a Brewfile does not trust it. Without this, `brew bundle install` fails on a
# fresh machine at the first sha1n/tap formula. Scope is deliberately limited to
# taps the manifest itself declares.
#
function __profile_provision_trust_taps() {
  local tap
  for tap in ${(f)"$(__profile_provision_declared_taps "$@")"}; do
    [[ -n "$tap" ]] || continue
    brew trust "$tap" >/dev/null 2>&1
  done
  return 0
}

#
# Applies the composed Brewfile. The visual-studio-code cask puts `code` on PATH,
# so `vscode` lines resolve within the same pass.
#
function __profile_provision_install() {
  __profile_provision_trust_taps "$@"
  __profile_provision_compose "$@" | brew bundle install --file=-
}
