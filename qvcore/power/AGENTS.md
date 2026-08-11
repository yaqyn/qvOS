# qvOS Power Workflow

Read this file completely when changing battery protection, charging thresholds,
the full-charge override, or another mutation under `qvcore/power/`.

## System power

`qvcore/power/system-power` is the one reboot and shutdown owner. Native `qv`
commands own metadata; metadata-free compatibility commands pass the same fixed
`reboot` or `poweroff` verb. Clear safe qvOS update
markers through their state owner, but never block an intentional power action
because stale state cleanup was refused. Schedule the fixed systemctl action
before closing windows, preserve the existing two-second application grace,
and never build a user-controlled shell command.

`toggle-suspend` owns only the user-facing availability flag consumed by the
system menu and automatic-suspend guard. It delegates the private `suspend-off`
state to the shared config toggle owner; it never changes logind, systemd, or
kernel sleep policy.

## Root-owned AC event boundary

`profiles-set` owns power-profile policy. Accept only `autodetect`, `ac`,
`battery`, or an exact profile reported by `powerprofilesctl`; use Balanced as
the safe battery and missing-Performance fallback. Autodetection reads only
Mains, USB-class, and wireless supplies with a validated `online` value. Test
fixtures may
override the power-supply root only with `QVOS_POWER_TESTING=1`. The init and
list owners delegate to this policy or the system service without duplicating
selection logic. `wifi-powersave` shares `supply-lib`, accepts only `auto`, `on`,
or `off`, and updates validated wireless interfaces with the required `iw`
base package.

No root AC event may execute the user-writable source checkout. `root-install`
is the singular owner of root copies under `/usr/lib/qvos/power/`.
It verifies an exact safe payload without privilege first so routine desktop
reconciliation never prompts for sudo when the root helpers are already current.
`event-rule` owns the shared atomic udev transaction; `profile-rule` and
`wifi-rule` select only their fixed policy. Accept only exact known qvOS or
Omarchy predecessors, keep a root-owned backup, and restore the prior rule when
reload or activation fails. Both policies run in bounded transient services.
Wi-Fi derives the effective mode from every supported external supply instead
of trusting a single event's online value.

## Power telemetry and sleep guards

`supply-lib` is the one sysfs owner for battery and external-power presence,
including USB-C/PD and wireless power. `battery-info` selects the aggregate
UPower DisplayDevice when available, validates every reported value, and
formats capacity, percentage,
remaining time, monitoring samples, and status without repeating device
queries. Low-battery notification state lives only in the validated user
runtime directory. Test roots require
`QVOS_POWER_TESTING=1`. Native qvOS consumers use `qv-*` routes. Sleep-inhibit
and automatic-suspend runtime links resolve to one copied power owner. The
installed runtime contains only native links; thin source adapters remain the
sole external compatibility boundary.
`unmount-fuse` is the singular system-sleep owner for lazily unmounting gvfs
before sleep and restarting it after wake. `root-install` deploys its fixed
root-owned copy as `/usr/lib/systemd/system-sleep/qvos-unmount-fuse`; it removes
the inherited `unmount-fuse` name only when its mode, owner, and payload hash
all match the reviewed predecessor, and preserves every modified or unsafe
file.
Power installation stages its dormant user unit independently of session
availability and reloads only a reachable manager for the same `HOME` through
the shared config probe. A fresh chroot leaves activation to first run.

## Hibernation

`qvcore/power/hibernation/` singularly owns support detection, the Btrfs swap
file, fstab entry, mkinitcpio resume hook, Limine drop-ins, and the keyboard
backlight sleep helper. Public `qv-hibernation-*` commands own metadata; their
Omarchy names are metadata-free compatibility adapters. Fresh install invokes
the native setup owner directly before Limine performs its one rebuild.

Keep confirmation and reboot choice unprivileged. Install and verify the
mutation helper and keyboard payload under `/usr/lib/qvos/power/`, then run
only that root-owned helper through sudo. The helper must serialize changes,
accept only Btrfs and a validated resume device and offset, stage system-file
changes atomically, and restore the prior boot policy if rebuilding fails. Use
only `/etc/limine-entry-tool.d/80-qvos-*.conf`; remove an old duplicate line
from `/etc/default/limine` only when it exactly matches a validated managed
drop-in. Never execute a home checkout from a boot, sleep, or package hook.
Fresh install invokes hibernation before the Limine owner creates that defaults
file. Treat an absent file as clean state, keep it absent, and still reject any
linked, foreign-owned, or writable file that is present.

Removal may delete `/swap/swapfile` and its subvolume only after explicit user
confirmation, exact ownership checks, successful boot-policy removal and
rebuild, and proof that the subvolume contains no unrelated data. Historical
Omarchy resume and sleep files are migration inputs only and may be removed
only when their complete content matches the known generated form. Fixture
roots and tool overrides require `QVOS_HIBERNATION_TESTING=1` and caller-owned
paths beneath one `/tmp` system root.

## Battery protection contract

- Keep Battery Protection in qvCORE. It must remain complete without optional
  Services or Development integrations and must not share ownership with the
  low-battery monitor.
- Installation and updates install only the runtime owner, root helper, and
  dormant user unit. They never enable protection, write the hwdb override, or
  call UPower's charge-threshold method.
- Enumerate batteries through UPower and require every present system battery
  to be a rechargeable power supply with a valid kernel power-supply path.
  Ignore `DisplayDevice`; refuse the complete mutation when any real battery
  lacks the shared safe capability.
- Support only start-and-end, end-only, or firmware-only `Long_Life` hardware.
  Treat start-only, mixed capability shapes, missing readback, and masks that
  combine adjustable and firmware behavior as unavailable.
- Mutate charge mode only through UPower's
  `EnableChargeThreshold(bool)` D-Bus method. Kernel power-supply files are
  readback only.
- Use the root-owned hwdb helper only for the fixed Balanced and Mostly plugged
  in presets. It accepts fixed verbs, owns one marked file, uses absolute
  commands, refuses symlinks or content other than an exact fixed preset, and
  keeps a root-only rollback transaction until the caller verifies UPower and
  kernel readback. Keep that transaction for retry if rollback reload fails.
- Disable and verify unlimited charging before changing hwdb configuration.
  On any later failure, disable all batteries, roll back the configuration, and
  preserve the prior qvOS intent.
- Serialize mutations with `flock`. Keep user intent and override state atomic
  and private under a `0700` directory with `0600` files. Never adopt or repair
  an external threshold state silently.
- Refuse mutation while TLP, auto-cpufreq, or asusd is active. Do not disable a
  competing manager. `power-profiles-daemon` is compatible.

## Full Charge Once

1. Require verified qvOS-managed protection and online AC power.
2. Persist the preset, capability shape, and 24-hour recovery deadline before
   temporarily disabling protection.
3. Enable the dormant user service only for the active override.
4. Restore through UPower when AC disconnects, all batteries are full, or the
   deadline expires. Retry transient failures and remove recovery state only
   after UPower and kernel readback agree.
5. Explicit Disable cancels the override and remains disabled. Explicit Enable
   cancels it only after protection is verified again.

Report an override as temporary only while its matching recovery state is
unexpired and the hardened service is enabled and active. If a conflicting
charging manager appears before restoration, preserve recovery state and retry
without writing until the conflict is gone.

## Verification and live approval

- Use simulated UPower, D-Bus, sysfs, hwdb, Wi-Fi, udev, power-profile, Polkit denial, concurrency, and
  systemd fixtures for mutation coverage. Run Bash syntax, ShellCheck, focused
  power/menu/install tests, `git diff --check`, and `test/qvcore/run.sh`.
- After a verified commit, apply the desktop overlay and system helper, reload
  user units, and verify source/runtime/live SHA parity, a disabled/inactive
  override unit, no qvOS hwdb file, and Standard charging.
- Never toggle live battery protection, exercise Full Charge Once, discharge,
  calibrate, cycle, or repeatedly probe writes without a separate explicit
  approval. For an approved initial Lenovo enable, perform one UPower mutation,
  require `[Long_Life]` readback, and roll back once to Standard on disagreement.
