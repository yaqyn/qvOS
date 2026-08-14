# qvOS Hardware Detection Workflow

Read this file completely when changing hardware identification, DMI, PCI,
display-connector, input-device, or graphics-capability probes.

`qvcore/hardware/detect` is the singular read-only detector. Public `qv-hw-*`
commands carry metadata; matching `omarchy-hw-*` files are metadata-free
compatibility adapters only. Native qvOS callers use the `qv-*` route. Keep
detectors usable during installation, return status for conditional probes,
and print output only for selectors such as touchpad and touchscreen.
The Intel Wi-Fi 7 EHT detector is qvOS-only because no inherited public binary
existed; it matches only Intel vendor/device IDs `e440` and `272b` in a network
or wireless controller record. The Tuxedo detector likewise owns the new
native-only vendor match used by its driver setup. The Synaptics PS/2 detector
requires both the kernel's `SynPS/2` identity and a touchpad record, so it never
applies a `psmouse` option to an I2C-only device. Apple SPI and Lenovo Yoga
detectors require the exact vendor and supported model family rather than an
unbounded product-name substring. The Surface SAM detector likewise accepts
only the documented Laptop, Book 3, and Laptop Studio models whose keyboard is
routed through the Surface Aggregator Module. None invents a compatibility adapter.

Validate action arity before probing. Treat caller-provided DMI matches as
bounded fixed strings, terminate option parsing, and suppress expected errors
from unavailable hardware. Never mutate hardware, load modules, start
services, or infer a capability from a malformed command response. Test
hardware through `QVOS_HARDWARE_TESTING=1` and an absolute, non-linked
`QVOS_HARDWARE_FIXTURE_ROOT`; no other source-root override is supported.
Hybrid-GPU detection requires both Integrated and Hybrid in a successful
`supergfxctl` capability response. If its daemon is unavailable, fall back only
to one NVIDIA display controller plus one non-NVIDIA display controller; two
arbitrary display devices are not sufficient for the NVIDIA-only switch owner.

The Framework 16 QMK HID rule lives only at
`qvcore/hardware/framework16-qmk-hid.rules`; `default/udev/` is retired. Its
fresh-install leaf delegates to the transactional hardware identity owner. The
owner publishes the native rule without clobbering a concurrent winner,
preserves modified or linked administrator state, and triggers only the hidraw
subsystem after a newly created live rule. Target-chroot construction persists
udev policy without reloading or triggering the builder's device manager.
Static Apple SPI, ASUS display and touchpad, hid_apple function-key, Synaptics
PS/2, Intel FRED, BE200/BE211 EHT, Lenovo speaker, NVIDIA boot, and Tuxedo
module policies install only through the native transactional hardware
identity owner. Surface initramfs keyboard support accepts exactly one loaded
platform pin-controller from its bounded allowlist, or verifies the standard
Arch kernel's built-in AMD controller, selects the documented model-specific
input driver, and publishes one native generated policy through the same owner.
Missing or ambiguous module evidence fails before writing, and unrelated
Surface models receive no policy. The paired NVIDIA modprobe and
mkinitcpio files roll back a
newly created first file when the second cannot be installed. A detected
Synaptics fix is persistent and applies on the next boot; never issue a
transient unprivileged `modprobe` from installation. Keep every boot argument
in its one Limine drop-in; never append it directly to `/etc/default/limine`.
Every installed policy filename uses a native `qvos` identity. Do not delete
unverified kernel module files or historical policy paths during fresh install.
All missing-policy publication is no-clobber: accept an exact concurrent winner
and reject every other object rather than overwriting a target that appeared
after preflight.

List every promoted inherited detector in `native-paths` and removed policy
prefix in `retired-paths`, sorted and unique.
Run `qvcore/hardware/check`, `test/qvcore/qvos-hardware-test.sh`, affected
install/config/software suites, CLI and upstream-overlay checks, Bash syntax
and ShellCheck, then the full qvOS suite. Live validation is read-only.
