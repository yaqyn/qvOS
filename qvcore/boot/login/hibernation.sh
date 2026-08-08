# Run before limine-snapper.sh so the resume hook + cmdline drop-ins are in
# place when `pacman -S limine-mkinitcpio-hook` triggers its single full UKI
# rebuild. The --no-rebuild flag tells the script to skip its own rebuild —
# limine-snapper's pacman install will produce a UKI that already includes
# hibernation.
"$QVOS_PATH/qvcore/power/hibernation/setup" --force --no-rebuild
