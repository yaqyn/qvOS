# Fix audio volume on Asus ROG laptops by using a soft mixer.

if qv-hw-asus-rog; then
  "$QVOS_PATH/qvcore/config/wireplumber-policy" asus-soft-mixer
fi
