# Helpers for the tests that run install.sh in a child shell. Source after sandbox.zsh.

install_script="$profile_home/install.sh"

# Usage: run_install [<extra_path>] — <extra_path> goes first on PATH, e.g. a directory of stubs.
run_install() {
  local search_path="$PATH"
  [[ -n "$1" ]] && search_path="$1:$PATH"
  # stdin from /dev/null so an unexpected replace prompt cannot block the run
  env -i HOME="$HOME" PATH="$search_path" TERM=dumb zsh "$install_script" </dev/null 2>&1
}

# Sets install_out and install_rc, because a command substitution in a local declaration drops the exit code.
run_install_with_rc() {
  install_out="$(run_install "$1")"
  install_rc=$?
}

errors_naming() {
  print -r -- "$1" | grep 'ERROR' | grep -F "$2"
}

# Usage: write_failing_stub <stub_dir> <command> <pattern>
# A stub fails as root too, where a read-only directory would not stop the command.
write_failing_stub() {
  local stub_dir="$1" name="$2" pattern="$3"
  local real="$(command -v "$name")"
  cat >"$stub_dir/$name" <<STUB
#!/bin/sh
for last do :; done
case "\$last" in
  *'$pattern'*)
    echo "$name: stub failure for \$last" >&2
    exit 1
    ;;
esac
exec '$real' "\$@"
STUB
  chmod +x "$stub_dir/$name"
}
