# Install Sound Open Firmware for the audio DSP on Intel systems that need it.
# The sof-audio-pci-intel-* driver family requires sof-firmware to initialise
# the DSP; without it the DSP fails to boot and PipeWire exposes only a Dummy
# Output sink. This affects Arrow Lake, Meteor Lake, Tiger Lake, Alder Lake,
# Wildcat Lake, Panther Lake, and similar platforms.

if qv-hw-intel-sof; then
  qv-pkg-add sof-firmware
fi
