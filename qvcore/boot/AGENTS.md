# qvOS Boot Presentation Workflow

Read this file completely when changing qvOS-owned Limine, Plymouth, SDDM,
session, or direct-boot presentation under `qvcore/boot/`.

`qvcore/boot/limine/limine.conf` owns the installed Limine presentation. The
generated qvOS, kernel, snapshot, and EFI entries remain owned by
`limine-entry-tool` and `limine-snapper-sync`; never rewrite or duplicate them
to obtain a custom menu layout.

`qvcore/boot/plymouth/` owns the installed-system and ISO Plymouth payload,
while `qvcore/boot/logo.png` is the single raster logo master shared with SDDM.
The atomic theme owner publishes that master as `logo.png` in both installed
themes; never restore per-theme source copies.
Declare the shared logo as an explicit TUI owner-contract dependency in
`sync-theme` so refresh provenance includes the dynamically selected payload.
Keep the promoted live theme's graphite `#090909` graphical background and
exact assets together. The installer TUI remains an independent
exact-black renderer and must clear Plymouth before painting its first frame.
The installed graphical kernel command line must explicitly initialize
`console=tty0`; a Limine-started UKI can otherwise reach early Plymouth with
no primary kernel console and crash before the encrypted-root prompt. Keep the
console token in the singular native Limine defaults and covered by the boot
install idempotence test.
`qvcore/boot/limine/`, `qvcore/boot/sddm/`, and `qvcore/boot/wayland-sessions/` likewise
own their installed payloads. Do not restore parallel copies under `default/`.
Public `bin/qv-*` boot routes own command metadata and delegate directly to
executable owners in this directory. `bin/omarchy-*` routes are metadata-free
compatibility adapters only; neither adapter family may retain implementation.
Historical boot migrations are retired because native fresh-install and boot
owners already converge the selected state; future transitions use only the
native migration domain.

`qvcore/boot/session-start` is the singular qvOS Hyprland login launcher. The
installed `/usr/local/bin/qvos-session` validates the native Lua
configuration before starting UWSM with an explicit `--config` path and the
Hyprland watchdog. Never route the qvOS session through generic
`hyprland.desktop`: default config discovery can recreate a `.conf` stub and
silently discard qvOS bindings, monitor policy, and appearance. The launcher
validates and executes only the native Lua entrypoint; it never reads, writes,
or removes a `.conf` file.

`qvcore/boot/install` singularly owns the ordered login stage. Its native leaves
install Plymouth without an early image rebuild, install the SDDM theme,
session, Wayland compositor config, autologin compatibility, and PAM policy,
then configure Limine and Snapper after the native keyring and hibernation
leaves in `qvcore/boot/login/`. The hibernation leaf calls the native power
owner with `--no-rebuild`, so the later Limine package step remains the only
fresh-install UKI rebuild. Hibernation must accept a safely absent
`/etc/default/limine`; the later Limine owner singularly creates that file.
The hibernation transaction owns only native qvOS resume and sleep artifacts;
its completed pre-release compatibility convergence is retired and must not return as
a boot input.
Active Plymouth, SDDM, session, mkinitcpio, and UKI
identifiers use `qvos`. Completed pre-release theme, selector, login, and
session convergence is retired and is not scanned at runtime. The direct-boot
owner recognizes and creates only the native `qvOS` firmware label; its
completed pre-release label transition is likewise retired. The shared atomic
theme sync owner stages the new payload, switches its Plymouth or SDDM selector,
and commits only after both succeed; any publication or selector failure
restores the prior native theme. The exact inherited mkinitcpio and UKI
identities remain preservation-safe migration input until their root state is
verified separately.
Treat Snapper's non-zero empty `list-configs` result as fresh state, then let
the required root `create-config` operation surface any real failure.
Use Snapper's native `--no-dbus` mode only for the reviewed chroot installer
boundary; running systems retain normal daemon coordination.
An interrupted run may have already installed the qvOS skin before generated
entries exist. Retry may recover its kernel command line only from an exact
re-render of the native Limine defaults plus the current validated drop-ins;
never source defaults or accept a partial or foreign recovery file.
Before rendering the captured or recovered base command line, collect only
simple, safely tokenizable default arguments appended by the native template
and current drop-ins, then remove their exact token forms from the captured
base before appending those sources once. Parse token boundaries without
evaluation, preserve safe escaped foreign arguments, reject shell-expanding or
structurally ambiguous base input, and validate native resume and RTC drop-ins
before treating them as policy. Require one non-empty `root=` argument. When
the mounted root stack contains dm-crypt, reject a command line whose final
root target is under `/dev/mapper` or `/dev/dm-*` unless `cryptdevice=` or
`dm-mod.create=` identifies the volume the busybox initramfs must unlock; fail
before changing defaults, packages, or UKIs.
Fresh Archinstall autologin may name `hyprland-uwsm`; the native session owner
rewrites only that exact generic seed to `qvos`. During the exact target-chroot
install, an empty regular Archinstall autologin fragment is likewise an
incomplete seed and is replaced with the native account and session; live
reconciliation preserves an intentional empty or custom file. Every root-owned
boot payload publication byte-compares its installed target before reporting
success, so a truncated write fails the owner instead of reaching reboot.

The Limine install owner must read private `/boot` content through explicit
sudo, render the inherited kernel command line without shell or sed
substitution, restore disabled mkinitcpio hooks on every exit, and rebuild UKIs
when either generated entries are absent or an EFI install lacks its native
non-empty UKI. Treat those as independent evidence; never let one mask the
other. When the installed config already begins with the exact native header,
preserve its generated entries instead of rewriting the header and forcing an
unchanged UKI rebuild. Changed native defaults, mkinitcpio policy, or drop-ins
must still rebuild exactly once when the mkinitcpio hook was already installed;
on first installation, trust its package hook only after the generated entries
and non-empty UKI verify successfully. Install required Limine integration packages through
the native package owner so a retry skips packages already present without
depending on a still-populated synchronization database. Include
`inotify-tools` with the integration packages because the enabled snapshot
watcher otherwise exits successfully without monitoring later snapshots.
Preserve the root-only Snapper policy from `qvcore/boot/snapper-root.conf`,
including explicit number cleanup with five retained recovery snapshots,
disabled timeline creation, zero-retention cleanup for historical timeline
snapshots, and disabled btrfs quotas. Explicitly disable the timeline timer and
enable the cleanup timer whenever the policy is installed; package presets are
not lifecycle authority. `default/snapper/` is retired. Fixture roots are test-only:
require `QVOS_BOOT_TESTING=1`, a canonical caller-owned `/tmp` directory, and
non-writable permissions before redirecting any system path. Normal boot
commands validate an interactive sudo ticket. The reviewed ISO chroot cannot
prompt and must instead prove its temporary authorization with
`sudo -n /usr/bin/true`; never let credential validation block a no-input
target install or weaken the commands that follow.

- Keep the Limine screen center-only on exact black: explicit empty branding,
  hidden interface help, no wallpaper, and no custom font or renderer fork.
- Preserve an explicit five-second automatic boot of entry 2 with
  `remember_last_entry: no`. Keep the countdown active but invisible by using
  exact-black normal and bright help colors.
- Limine renders selected-entry comments with ANSI cyan. Keep the normal cyan
  palette slot exact black to hide them, and disable editor syntax highlighting
  so the recovery editor remains completely readable in the default foreground.
- Use restrained `#a0a0a0` foreground. Limine owns selection as reverse video,
  producing the brighter gray selected block with black text; do not patch its
  renderer for separate selected and unselected colors.
- Preserve the generated menu tree, keyboard and mouse behavior, editor,
  snapshots, EFI fallback, boot verification, and Secure Boot behavior.
- The EFI system partition is root-only on qvOS. Boot commands inspect or
  change `/boot` through explicit privileged operations; never weaken its mount
  mask to make an unprivileged read convenient.

Run `qvcore/boot/check`, the boot install fixture test, `bash -n`, and ShellCheck
for changed shell, then
`test/qvcore/qvos-product-contract-test.sh`, the instruction guard, and the full
qvOS shell suite when shared boot/install contracts change. Apply with
`qv refresh limine`, compare the generated live header with the source,
and capture the Limine menu from a safe UEFI VM or approved reboot. The final
image must show only the centered generated menu on exact black.
