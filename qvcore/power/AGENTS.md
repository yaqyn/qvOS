# qvOS Power Workflow

Read this file completely when changing battery protection, charging thresholds,
the full-charge override, or another mutation under `qvcore/power/`.

## System power

`qvcore/power/system-power` is the one reboot and shutdown owner. Compatibility
commands pass a fixed `reboot` or `poweroff` verb only. Clear safe qvOS update
markers through their state owner, but never block an intentional power action
because stale state cleanup was refused. Schedule the fixed systemctl action
before closing windows, preserve the existing two-second application grace,
and never build a user-controlled shell command.

## Session power profiles

`profiles-set` owns power-profile policy. Accept only `autodetect`, `ac`,
`battery`, or an exact profile reported by `powerprofilesctl`; use Balanced as
the safe battery and missing-Performance fallback. Autodetection reads only
Mains and USB supplies with a validated `online` value. Test fixtures may
override the power-supply root only with `QVOS_POWER_TESTING=1`. The init and
list owners delegate to this policy or the system service without duplicating
selection logic. `profile-rule` is the singular installer and update owner for
the root udev rule. It accepts only exact known qvOS/Omarchy predecessors,
writes atomically, keeps a root-owned backup, and restores it when reload fails.

## Power telemetry and sleep guards

`supply-lib` is the one sysfs owner for battery and AC presence, including
USB-C power. `battery-info` selects the aggregate UPower DisplayDevice when
available, validates every reported value, and formats capacity, percentage,
remaining time, monitoring samples, and status without repeating device
queries. Low-battery notification state lives only in the validated user
runtime directory. Test roots require
`QVOS_POWER_TESTING=1`. Native qvOS consumers use `qv-*` routes. Sleep-inhibit
and automatic-suspend runtime links resolve to one copied power owner; retain
exact `omarchy-*` links only for external and saved-session compatibility.

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

- Use simulated UPower, D-Bus, sysfs, hwdb, power-profile, Polkit denial, concurrency, and
  systemd fixtures for mutation coverage. Run Bash syntax, ShellCheck, focused
  power/menu/install tests, `git diff --check`, and `test/qvcore/run.sh`.
- After a verified commit, apply the desktop overlay and system helper, reload
  user units, and verify source/runtime/live SHA parity, a disabled/inactive
  override unit, no qvOS hwdb file, and Standard charging.
- Never toggle live battery protection, exercise Full Charge Once, discharge,
  calibrate, cycle, or repeatedly probe writes without a separate explicit
  approval. For an approved initial Lenovo enable, perform one UPower mutation,
  require `[Long_Life]` readback, and roll back once to Standard on disagreement.
