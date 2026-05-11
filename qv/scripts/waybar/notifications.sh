#!/bin/bash
set -euo pipefail

count="$(makoctl list -j 2>/dev/null | jq 'length' 2>/dev/null || printf '0')"

if [[ "$count" =~ ^[0-9]+$ ]] && ((count > 0)); then
  printf '{"text":"","tooltip":"%s active notifications\\nLeft: history\\nRight: clear history\\nMiddle: restore latest","class":"active"}\n' "$count"
else
  printf '{"text":"","tooltip":"No active notifications\\nLeft: history\\nRight: clear history\\nMiddle: restore latest","class":"empty"}\n'
fi
