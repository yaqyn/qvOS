# qvOS Boot Presentation Workflow

Read this file completely when changing qvOS-owned Limine, Plymouth, SDDM,
session, or direct-boot presentation under `qv/boot/`.

`qv/boot/limine/limine.conf` owns the installed Limine presentation. The
generated qvOS, kernel, snapshot, and EFI entries remain owned by
`limine-entry-tool` and `limine-snapper-sync`; never rewrite or duplicate them
to obtain a custom menu layout.

`qv/boot/plymouth/` is the single installed-system and ISO Plymouth source.
Keep the promoted live theme's graphite `#090909` graphical background and
exact promoted assets together. The installer TUI remains an independent
exact-black renderer and must clear Plymouth before painting its first frame.

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

Run `bash -n` and ShellCheck for changed shell, then
`test/qvos/qvos-product-contract-test.sh`, the instruction guard, and the full
qvOS shell suite when shared boot/install contracts change. Apply with
`omarchy-refresh-limine`, compare the generated live header with the source,
and capture the Limine menu from a safe UEFI VM or approved reboot. The final
image must show only the centered generated menu on exact black.
