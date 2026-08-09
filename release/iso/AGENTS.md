# qvOS ISO Workflow

Read this file completely when changing the qvOS image builder, ISO patch,
embedded source, installer integration, or release-image verification.

`release/iso/build` owns qvOS image construction. The installed TUI command is
a thin adapter to this owner.
`release/iso/README.md` owns the release-candidate gate and required evidence.

- `release/iso/upstream-ref` is the reviewed full commit of the official
  `omacom-io/omarchy-iso` source-backed builder. The qvOS patch is verified
  against that exact input. Never default to a floating branch. The newer
  package-backed builder would make qvOS depend on operating a custom runtime
  package, which is outside the product boundary; learn from its changes and
  port selected fixes into this release owner instead. Changing the pin
  requires an explicit compatibility audit and adaptation. Stage the builder
  fresh for normal builds. `git qvsync` does not sync this separate repository.
- Stage the selected qvOS Git ref separately and apply
  `release/iso/omarchy-iso-qvos-tui.patch` only to the temporary builder. Keep ISO
  integration under `release/iso/` and never persist qvOS edits in upstream source.
- Validate the embedded qvOS installer at `qvcore/install/` and login leaves at
  `qvcore/boot/login/`; never require or recreate the retired top-level
  `install/` tree for image staging.
- Route live-media and target progress through `/var/log/qvos-install.log`.
  Removed `omarchy-install.log` lines may appear only as the upstream side of
  the reviewed patch, never as added or active qvOS behavior.
- If an upstream builder change breaks the patch or a relied-on contract, stop
  and update the qvOS owner and tests. Do not weaken the guard or patch cached
  upstream output directly.
- During pre-public development, run full image builds and embedded audits on
  request or for release candidates. For ISO changes, run fast staging and
  contract checks immediately and report any deferred full build.
- Unflagged image builds use the installed qvOS Stable package channel.
  `--dev` selects Edge and `--rc` selects RC only for those explicit reviewed
  image workflows; never make a development channel the production default.
- Keep release package transfers on bounded HTTP/1.1 curl retries. A no-cache
  release candidate starts with an empty package cache; retries inside that one
  build may preserve packages already verified during the same run.
- For release verification, pin `QVOS_SOURCE_REF` to the intended qvOS commit,
  require that commit to equal `origin/OS`, and leave the embedded checkout on
  `OS` tracking `origin/OS` so the installed update guard remains usable. Build
  the intended `QVOS_OMARCHY_ISO_REF`, verify the image and embedded source,
  and keep optional Services and Development integrations out unless
  explicitly promoted.
- Archiso normalizes ordinary payload files to mode `0644`. Generate explicit
  `profiledef.sh` entries from the embedded Git tree's tracked `100755` modes;
  never maintain a second executable inventory. Reject an artifact unless the
  embedded worktree is clean with file-mode checking enabled.
- Build the ISO TUI with the exact digest from `qvcore/tui/source-hash` and verify
  the embedded binary reports that digest, never `unmanaged`. Disable and
  remove clone reflogs before image assembly so transient builder identity is
  absent; retain the usable `OS` branch, `origin/OS` tracking, and clean Git
  worktree.
- The live ISO, Syslinux, Limine, and installer TUI use exact black (`#000000`)
  with neutral grayscale; only the installer TUI uses sparse qvOS red accents.
  Plymouth uses the canonical promoted live theme from
  `qvcore/boot/plymouth` with its graphite `#090909` graphical background and
  exact promoted assets; never stage the inherited Omarchy Plymouth payload.
  Replace the inherited Arch Syslinux splash from
  `release/iso/syslinux-splash.png`, and verify every rendered boot/install pixel.
- Preserve the boot setup, progress, and finale contract in `qvcore/tui/AGENTS.md`;
  the ISO layer owns no visual fork. Verify its direct Step 1/3 entry, increasing
  ring roles, fixed Region layout, safe-default Back/Continue erase gate, real
  milestone progress, single replacing log view, dim estimate/Help footer, and
  quiet finale in the live TTY.
- Every user-visible live-media boot label, installed Limine label, volume
  label, publisher, and application name says `qvOS`. Keep inherited lowercase
  internal paths, command names, package names, and UKI filenames unchanged
  when they are compatibility identifiers rather than displayed branding.
- Progress renderers have one terminal owner at a time. Stop and wait for the
  live-media base-system TUI before entering the target PID namespace; start
  target-install progress inside that namespace, and stop and wait for it
  before either the qvOS finale or inherited error fallback. Never pass a
  live-media PID through `arch-chroot` as if the target could own it.
- Keep installer diagnostics local. The live ISO must not stage a diagnostic
  uploader or offer external log upload; users may inspect or explicitly save
  the private install log instead.
- Once a release candidate commit is selected, freeze feature work until its
  rehearsal passes or the candidate is abandoned. During the freeze, accept
  only upstream compatibility, build or installation blockers, verification
  repairs, and security fixes; every change selects a new candidate commit.
- Never call a candidate releasable from static tests or a successful image
  build alone. Complete the build, embedded-source, clean-install, reboot,
  base-without-optional-integrations, update, and configuration-reconciliation
  evidence in `release/iso/README.md`. Record Services and Development results
  separately so optional integrations never redefine qvOS base readiness.
