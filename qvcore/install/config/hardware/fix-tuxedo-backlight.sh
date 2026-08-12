# Install Tuxedo drivers for keyboard backlighting on Tuxedo laptops and
# compatible devices like the Slimbook Executive (Clevo/Tuxedo chassis).
if "$QVOS_PATH/bin/qv-hw-tuxedo"; then
  qv-pkg-add linux-headers tuxedo-drivers-nocompatcheck-dkms
  "$QVOS_PATH/qvcore/install/hardware/identity" tuxedo-backlight
fi
