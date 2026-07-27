#!/bin/bash
set -euo pipefail

brave_ready=0
omarchy-pkg-present brave-origin-beta-bin &&
  omarchy-cmd-present brave-origin-beta &&
  brave_ready=1

case ${1:-} in
"")
  omarchy-install-browser brave-origin
  omarchy-default-browser brave-origin
  ;;
--status)
  if ((brave_ready)); then
    echo "qvCORE Brave is installed."
  else
    echo "qvCORE Brave is not installed."
  fi
  ((brave_ready))
  ;;
--state)
  if ((brave_ready)); then
    echo "ready"
  else
    echo "not-installed"
  fi
  ;;
*)
  echo "Usage: brave-origin.sh [--status]" >&2
  exit 2
  ;;
esac
