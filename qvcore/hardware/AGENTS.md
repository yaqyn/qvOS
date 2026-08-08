# qvOS Hardware Detection Workflow

Read this file completely when changing hardware identification, DMI, PCI,
display-connector, input-device, or graphics-capability probes.

`qvcore/hardware/detect` is the singular read-only detector. Public `qv-hw-*`
commands carry metadata; matching `omarchy-hw-*` files are metadata-free
compatibility adapters only. Native qvOS callers use the `qv-*` route. Keep
detectors usable during installation, return status for conditional probes,
and print output only for selectors such as touchpad and touchscreen.

Validate action arity before probing. Treat caller-provided DMI matches as
bounded fixed strings, terminate option parsing, and suppress expected errors
from unavailable hardware. Never mutate hardware, load modules, start
services, or infer a capability from a malformed command response. Test
hardware through `QVOS_HARDWARE_TESTING=1` and an absolute, non-linked
`QVOS_HARDWARE_FIXTURE_ROOT`; no other source-root override is supported.

List every promoted inherited detector in `native-paths`, sorted and unique.
Run `qvcore/hardware/check`, `test/qvcore/qvos-hardware-test.sh`, affected
install/config/software suites, CLI and upstream-overlay checks, Bash syntax
and ShellCheck, then the full qvOS suite. Live validation is read-only.
