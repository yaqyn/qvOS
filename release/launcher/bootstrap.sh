#!/bin/bash
# POSIX bootstrap: this file is also consumed by curl | sh.
set -eu
umask 077

fail() {
  printf 'qvOS: %s\n' "$1" >&2
  exit 1
}

case "$(uname -s):$(uname -m)" in
  Linux:x86_64) ;;
  *) fail 'This launcher currently supports Linux x86_64.' ;;
esac
for tool in curl tar mktemp chmod rm; do
  command -v "$tool" >/dev/null 2>&1 || fail "Missing required command: $tool"
done
command -v sha256sum >/dev/null 2>&1 || fail 'Missing required command: sha256sum'
( : </dev/tty >/dev/tty ) 2>/dev/null || fail 'Run this command from an interactive terminal.'

launcher_dir=$(mktemp -d "${TMPDIR:-/tmp}/qvos-launcher.XXXXXXXX")
trap 'rm -rf -- "$launcher_dir"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
  --connect-timeout 15 --max-time 180 --retry 2 \
  '@ORIGIN@/downloads/@ARCHIVE@' -o "$launcher_dir/payload.tar.gz"
printf '%s  %s\n' '@ARCHIVE_SHA256@' "$launcher_dir/payload.tar.gz" | sha256sum --check --status ||
  fail 'The launcher download failed its integrity check.'
tar -xzf "$launcher_dir/payload.tar.gz" -C "$launcher_dir"
chmod 0700 "$launcher_dir/qvos-tui" "$launcher_dir/build"
test "$("$launcher_dir/qvos-tui" --source-hash)" = '@SOURCE_HASH@' ||
  fail 'The compiled interface does not match its release source.'

QVOS_BUILD_SCRIPT="$launcher_dir/build" QVOS_TUI_ROOT="$launcher_dir" \
  QVOS_LAUNCHER_SOURCE_HASH='@SOURCE_HASH@' \
  "$launcher_dir/qvos-tui" </dev/tty >/dev/tty 2>/dev/tty
