# Allow unprivileged access to the Framework 16 keyboard for RGB control via qmk_hid.

if qv-hw-framework16; then
  rule=/etc/udev/rules.d/50-framework16-qmk-hid.rules
  candidate="$rule.qvos-new"
  if sudo test -L "$rule"; then
    echo "Refusing to install the Framework HID rule through a symbolic link." >&2
    return 1
  fi
  if ! sudo test -e "$rule"; then
    sudo rm -f -- "$candidate"
    sudo install -D -o root -g root -m 0644 \
      "$QVOS_PATH/qvcore/hardware/framework16-qmk-hid.rules" "$candidate"
    if sudo test -L "$rule"; then
      sudo rm -f -- "$candidate"
      echo "Refusing to install the Framework HID rule through a symbolic link." >&2
      return 1
    fi
    if sudo test -e "$rule"; then
      sudo rm -f -- "$candidate"
      echo "Preserving the existing Framework HID rule."
    else
      sudo mv -Tn "$candidate" "$rule"
      if sudo test -e "$candidate"; then
        sudo rm -f -- "$candidate"
        echo "Preserving the concurrently installed Framework HID rule."
      else
        sudo udevadm control --reload-rules
        sudo udevadm trigger
      fi
    fi
  fi
fi
