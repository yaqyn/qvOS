echo "6Ghz Wi-Fi + Intel graphics acceleration for existing installations"

bash "$OMARCHY_PATH/qvcore/install/config/hardware/set-wireless-regdom.sh"
bash "$OMARCHY_PATH/qvcore/install/config/hardware/intel/video-acceleration.sh"
