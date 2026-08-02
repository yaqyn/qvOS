# qvOS ISO Workflow

Read this file completely when changing the qvOS image builder, ISO patch,
embedded source, installer integration, or release-image verification.

`qv/tui/bin/qvos-build` owns qvOS image construction.
`qv/iso/README.md` owns the release-candidate gate and required evidence.

- Pin official `omacom-io/omarchy-iso` `main` because the current qvOS source
  tracks Omarchy `master` and the patch contracts are verified against that
  pairing. An upstream default-branch change is not permission to follow it;
  changing the pin requires an explicit compatibility audit and adaptation.
  Stage the builder fresh for normal builds. `git qvsync` does not sync this
  separate repository.
- Stage the selected qvOS Git ref separately and apply
  `qv/iso/omarchy-iso-qvos-tui.patch` only to the temporary builder. Keep ISO
  integration under `qv/iso/` and never persist qvOS edits in upstream source.
- If an upstream builder change breaks the patch or a relied-on contract, stop
  and update the qvOS owner and tests. Do not weaken the guard or patch cached
  upstream output directly.
- During pre-public development, run full image builds and embedded audits on
  request or for release candidates. For ISO changes, run fast staging and
  contract checks immediately and report any deferred full build.
- Keep release package transfers on bounded HTTP/1.1 curl retries. A no-cache
  release candidate starts with an empty package cache; retries inside that one
  build may preserve packages already verified during the same run.
- For release verification, pin `QVOS_SOURCE_REF` to the intended qvOS commit,
  require that commit to equal `origin/OS`, and leave the embedded checkout on
  `OS` tracking `origin/OS` so the installed update guard remains usable. Build
  the intended `QVOS_OMARCHY_ISO_REF`, verify the image and embedded source,
  and keep optional qvCORE stacks out unless explicitly promoted.
- Archiso normalizes ordinary payload files to mode `0644`. Generate explicit
  `profiledef.sh` entries from the embedded Git tree's tracked `100755` modes;
  never maintain a second executable inventory. Reject an artifact unless the
  embedded worktree is clean with file-mode checking enabled.
- Build the ISO TUI with the exact digest from `qv/tui/source-hash` and verify
  the embedded binary reports that digest, never `unmanaged`. Disable and
  remove clone reflogs before image assembly so transient builder identity is
  absent; retain the usable `OS` branch, `origin/OS` tracking, and clean Git
  worktree.
- The live ISO, Syslinux, Plymouth, Limine, and installer TUI use exact black
  (`#000000`) and neutral grayscale. Plymouth and the installer TUI may use
  only the Yaqyn red tonal accents (`#5f0000`/`#b00000`/`#d00000`); Limine
  and Syslinux stay grayscale-only. Stage `qv/boot/plymouth`, never the
  inherited Omarchy Plymouth payload; replace the inherited Arch Syslinux
  splash from `qv/iso/syslinux-splash.png`; and verify the rendered
  boot/install pixels.
- Preserve the boot setup, progress, and finale contract in `qv/tui/AGENTS.md`;
  the ISO layer owns no visual fork. Verify its direct Step 1/3 entry, increasing
  ring roles, fixed Region layout, explicit erase gate, real milestone progress,
  minimal terminal controls, and quiet finale in the live TTY.
- Every user-visible live-media boot label, installed Limine label, volume
  label, publisher, and application name says `qvOS`. Keep inherited lowercase
  internal paths, command names, package names, and UKI filenames unchanged
  when they are compatibility identifiers rather than displayed branding.
- Progress renderers have one terminal owner at a time. Stop and wait for the
  live-media base-system TUI before entering the target PID namespace; start
  target-install progress inside that namespace, and stop and wait for it
  before either the qvOS finale or inherited error fallback. Never pass a
  live-media PID through `arch-chroot` as if the target could own it.
- Once a release candidate commit is selected, freeze feature work until its
  rehearsal passes or the candidate is abandoned. During the freeze, accept
  only upstream compatibility, build or installation blockers, verification
  repairs, and security fixes; every change selects a new candidate commit.
- Never call a candidate releasable from static tests or a successful image
  build alone. Complete the build, embedded-source, clean-install, reboot,
  base-without-qvCORE, update, and configuration-reconciliation evidence in
  `qv/iso/README.md`. Record optional-stack results separately so qvCORE never
  redefines qvOS base readiness.
