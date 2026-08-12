# shellcheck shell=bash

"$QVOS_PATH/qvcore/config/wireplumber-policy" bluetooth-a2dp

# Turn on Bluetooth by default after its user policy is ready.
chrootable_systemctl_enable bluetooth.service
