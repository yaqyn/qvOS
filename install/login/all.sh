# shellcheck shell=bash

run_logged "$OMARCHY_INSTALL/login/plymouth.sh"
run_logged "$OMARCHY_INSTALL/login/sddm.sh"
run_logged "$OMARCHY_INSTALL/login/hibernation.sh"
run_logged "$OMARCHY_INSTALL/login/limine-snapper.sh"
