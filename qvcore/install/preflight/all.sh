# shellcheck disable=SC1091
source "$QVOS_INSTALL/preflight/guard.sh"
# shellcheck disable=SC1091
source "$QVOS_INSTALL/preflight/begin.sh"
run_logged "$QVOS_INSTALL/preflight/show-env.sh"
run_logged "$QVOS_INSTALL/preflight/pacman.sh"
run_logged "$QVOS_INSTALL/preflight/migrations.sh"
run_logged "$QVOS_PATH/qvcore/install/first-run/prepare"
run_logged "$QVOS_INSTALL/preflight/disable-mkinitcpio.sh"
