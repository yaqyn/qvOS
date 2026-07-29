# qvOS Power Workflow

Read this file completely when changing battery protection, charging thresholds,
the full-charge override, or another mutation under `qv/power/`.

## Battery protection contract

- Keep Battery Protection in qvOS base. It must remain complete without qvCORE
  and must not share ownership with the low-battery monitor.
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
  commands, refuses symlinks or foreign content, and keeps a root-only rollback
  transaction until the caller verifies UPower and kernel readback.
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

## Verification and live approval

- Use simulated UPower, D-Bus, sysfs, hwdb, Polkit denial, concurrency, and
  systemd fixtures for mutation coverage. Run Bash syntax, ShellCheck, focused
  power/menu/install tests, `git diff --check`, and `test/qvos/run.sh`.
- After a verified commit, apply the desktop overlay and system helper, reload
  user units, and verify source/runtime/live SHA parity, a disabled/inactive
  override unit, no qvOS hwdb file, and Standard charging.
- Never toggle live battery protection, exercise Full Charge Once, discharge,
  calibrate, cycle, or repeatedly probe writes without a separate explicit
  approval. For an approved initial Lenovo enable, perform one UPower mutation,
  require `[Long_Life]` readback, and roll back once to Standard on disagreement.
