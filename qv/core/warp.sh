#!/bin/bash
# qvcore:lifecycle=1
set -euo pipefail

state_file="$HOME/.local/state/qvos/qvcore/warp"
mode="install"
package_ready=0
service_ready=0
registration_ready=0
connection_ready=0
maintenance_ready=0

usage() {
  echo "Usage: warp.sh [--status|--integration-status|--repair|--adopt|--disable]" >&2
}

status_label() {
  if (($1)); then
    printf 'ready\n'
  else
    printf 'missing\n'
  fi
}

inventory_warp() {
  package_ready=0
  service_ready=0
  registration_ready=0
  connection_ready=0
  maintenance_ready=0

  omarchy-cmd-present warp-cli && package_ready=1
  if ((package_ready)); then
    systemctl is-enabled --quiet warp-svc.service &&
      systemctl is-active --quiet warp-svc.service &&
      service_ready=1
    warp-cli --json registration show </dev/null &>/dev/null &&
      registration_ready=1
    if warp-cli --json status 2>/dev/null |
      jq -e '.status == "Connected"' >/dev/null; then
      connection_ready=1
    fi
  fi
  [[ -f $state_file ]] && maintenance_ready=1
  return 0
}

print_inventory() {
  local ready_count=$((package_ready + \
    service_ready + \
    registration_ready + \
    connection_ready + \
    maintenance_ready))

  echo ""
  echo "qvCORE WARP inventory: $ready_count/5 ready"
  printf '  %-20s %s\n' "WARP CLI" "$(status_label "$package_ready")"
  printf '  %-20s %s\n' "WARP service" "$(status_label "$service_ready")"
  printf '  %-20s %s\n' "Registration" "$(status_label "$registration_ready")"
  printf '  %-20s %s\n' "Connection" "$(status_label "$connection_ready")"
  printf '  %-20s %s\n' "Update tracking" \
    "$(status_label "$maintenance_ready")"
}

if (($# > 1)); then
  usage
  exit 2
fi

case ${1:-} in
"") ;;
--status) mode="status" ;;
--integration-status) mode="integration-status" ;;
--repair) mode="repair" ;;
--adopt) mode="adopt" ;;
--disable) mode="disable" ;;
*)
  usage
  exit 2
  ;;
esac

inventory_warp
if [[ $mode != "install" ]]; then
  print_inventory
fi

if [[ $mode == "status" || $mode == "integration-status" ]]; then
  ((package_ready && service_ready && registration_ready && \
  connection_ready && maintenance_ready))
  exit
fi

if [[ $mode == "disable" ]]; then
  rm -f "$state_file"
  echo "qvCORE WARP maintenance is disabled; the current network choice was not changed."
  exit
fi

if [[ $mode == "adopt" ]]; then
  if ((package_ready == 0 || service_ready == 0 || \
    registration_ready == 0 || connection_ready == 0)); then
    echo "The current WARP setup is not ready to adopt." >&2
    echo 'Run "omarchy install qvcore warp" to configure it.' >&2
    exit 1
  fi
  install -D -m 0644 /dev/null "$state_file"
elif [[ $mode == "repair" ]]; then
  if [[ ! -f $state_file ]]; then
    echo "qvCORE WARP maintenance is not enabled; nothing was repaired."
    exit
  fi
  omarchy-qvos-setup-dns WARP
else
  omarchy-qvos-setup-dns WARP
fi

inventory_warp
print_inventory
if ((package_ready == 0 || service_ready == 0 || registration_ready == 0 || \
  connection_ready == 0 || maintenance_ready == 0)); then
  echo "qvCORE WARP is incomplete." >&2
  exit 1
fi

echo ""
echo "qvCORE WARP is ready: 5/5."
