echo "Migrating DNS policy to the root-owned qvOS boundary"

"$QVOS_PATH/qvcore/network/install"
if [[ -n ${QVOS_NETWORK_SYSTEM_ROOT:-} && ${QVOS_NETWORK_TESTING:-} == "1" ]]; then
  "$QVOS_NETWORK_SYSTEM_ROOT/usr/lib/qvos/network/dns-policy" migrate-legacy
else
  /usr/bin/sudo /usr/lib/qvos/network/dns-policy migrate-legacy
fi
