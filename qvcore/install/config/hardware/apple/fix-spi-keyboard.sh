if "$QVOS_PATH/bin/qv-hw-apple-spi-keyboard"; then
  qv-pkg-add macbook12-spi-driver-dkms
  "$QVOS_PATH/qvcore/install/hardware/identity" apple-spi-keyboard
fi
