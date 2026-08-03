echo "Raise soft file descriptor limit so dev tools have headroom (takes effect after reboot)"

bash "$OMARCHY_PATH/qvcore/install/config/increase-fd-limit.sh"
