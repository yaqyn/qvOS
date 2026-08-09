# qvOS ISO Workflow

Read this file completely when changing the qvOS image builder, native Archiso
profile, embedded source, installer integration, upstream ISO review, or
release-image verification.

`release/iso/build` owns qvOS image construction. The installed TUI command is
a thin adapter to this owner.
`release/iso/README.md` owns the release-candidate gate and required evidence.

- `release/iso/builder/` and `release/iso/profile/` are the singular native
  qvOS image implementation. They began as a reviewed port from the exact
  commit recorded in `release/iso/UPSTREAM.md`; retain its license and
  provenance. No Omarchy ISO source is cloned, patched, mounted, or executed.
- Audit `omacom-io/omarchy-iso` through qvsync as a separate read-only upstream
  with an independent baseline and per-commit ledger. Never merge or
  cherry-pick it. Port only reviewed capability, fixes, or simplifications into
  the native qvOS owner and record each decision before advancing its baseline.
- Install the signed Arch `archiso` package inside a refreshed ephemeral build
  container and derive the image from its `/usr/share/archiso/configs/releng`
  profile. Never vendor Archiso itself or depend on another distribution's
  runtime, settings, meta, or ISO package.
- Stage the selected qvOS Git ref separately. Mount its native builder, profile,
  and complete source read-only; reject links, special files, weak package
  policy, or duplicate installers before Docker executes.
- Mount that exact staged source read-only at `/qvos`, embed it at `/root/qvos`,
  and resolve package-provider files from it before the first Omarchy package.
  Never let the builder fetch a replacement product source or keep retired
  `/root/omarchy` or `/var/cache/omarchy` internal paths.
- Validate the embedded qvOS installer at `qvcore/install/` and login leaves at
  `qvcore/boot/login/`; never require or recreate the retired top-level
  `install/` tree for image staging.
- Route live-media and target progress through `/var/log/qvos-install.log`;
  never restore `omarchy-install.log` as active qvOS behavior.
- If an upstream ISO change reveals a bug or useful capability, update the
  native qvOS owner and its tests deliberately. Do not weaken guards, patch
  cached output, or make a reviewed upstream commit executable build input.
- During pre-public development, run full image builds and embedded audits on
  request or for release candidates. For ISO changes, run fast staging and
  contract checks immediately and report any deferred full build.
- Unflagged image builds use the installed qvOS Stable package channel.
  `--dev` selects Edge and `--rc` selects RC only for those explicit reviewed
  image workflows; never make a development channel the production default.
- Require signatures for every online and offline package. Copy each detached
  signature with its cached package and validate the native builder for weak
  trust, unsupported repositories, and boot-kernel drift before Docker runs.
  Require signatures for direct local package files too, and keep the offline
  cache root-owned without group write access.
  The live medium and target use signed Arch `linux`; refuse T2 Macs before disk
  selection because qvOS does not operate a signing boundary for their required
  third-party kernel, firmware, audio, fan, Touch Bar, and graphics packages.
- Keep release package transfers on bounded HTTP/1.1 curl retries. A no-cache
  release candidate starts with an empty package cache; retries inside that one
  build may preserve packages already verified during the same run.
- Pull the build-container image for every build and perform a complete
  container `pacman -Syu` before installing tools. Keep package names sorted and
  unique, reject provider-key payload drift, and validate remote checksums and
  filenames before using downloaded archives.
- For release verification, pin `QVOS_SOURCE_REF` to the intended qvOS commit,
  require that commit to equal `origin/OS`, and leave the embedded checkout on
  `OS` tracking `origin/OS` so the installed update guard remains usable. The
  native builder and profile come from that same pinned qvOS commit. Verify the
  image and embedded source, and keep optional Services and Development
  integrations out unless explicitly promoted.
- Archiso normalizes ordinary payload files to mode `0644`. Generate explicit
  `profiledef.sh` entries from the embedded Git tree's tracked `100755` modes;
  never maintain a second executable inventory. Reject an artifact unless the
  embedded worktree is clean with file-mode checking enabled.
- Build the ISO TUI with the exact digest from `qvcore/tui/source-hash` and verify
  the embedded binary reports that digest, never `unmanaged`. Disable and
  remove clone reflogs before image assembly so transient builder identity is
  absent; retain the usable `OS` branch, `origin/OS` tracking, and clean Git
  worktree. The TUI is the singular installer: an image build fails if it cannot
  be built, and live boot fails closed to a recovery shell if it is unexpectedly
  unavailable. Never ship a parallel configurator fallback.
- Keep the signed offline package archive uncompressed inside the zstd live
  root so package data is not compressed twice. Prefetch at most half of
  available memory while the user configures the installation, and restore
  every CPU governor changed temporarily for the base install.
- The live ISO, Syslinux, Limine, and installer TUI use exact black (`#000000`)
  with neutral grayscale; only the installer TUI uses sparse qvOS red accents.
  Plymouth uses the canonical promoted live theme from
  `qvcore/boot/plymouth` with its graphite `#090909` graphical background and
  exact promoted assets under the native `qvos` theme identity; never stage the
  inherited Omarchy Plymouth payload or select its retired theme name.
  Replace the inherited Arch Syslinux splash from
  `release/iso/syslinux-splash.png`, and verify every rendered boot/install pixel.
- Preserve the boot setup, progress, and finale contract in `qvcore/tui/AGENTS.md`;
  the ISO layer owns no visual fork. Verify its direct Step 1/3 entry, increasing
  ring roles, fixed Region layout, safe-default Back/Continue erase gate, real
  milestone progress, single replacing log view, dim estimate/Help footer, and
  quiet finale in the live TTY.
- Every user-visible live-media boot label, installed Limine label, volume
  label, publisher, and application name says `qvOS`. Fresh images also use
  native `qvos` host, Plymouth, SDDM, session, and UKI identifiers. Keep only
  truthful package-provider ABI, names and URLs, upstream provenance and review
  records, and the exact installed-source compatibility link; never recreate a
  retired internal boot identity.
- The staged target installer exports only qvOS names for source ownership,
  provider channel, and user metadata. Pass the validated provider input as
  `QVOS_PROVIDER_CHANNEL` and user data as `QVOS_USER_NAME` and
  `QVOS_USER_EMAIL`. Preserve only
  `OMARCHY_CHROOT_INSTALL` as the exact upstream chroot-mode signal; never
  restore `OMARCHY_PATH` or `OMARCHY_INSTALL` as installer roots.
- Progress renderers have one terminal owner at a time. Stop and wait for the
  live-media base-system TUI before entering the target PID namespace; start
  target-install progress inside that namespace, and stop and wait for it
  before either the qvOS finale or the native error path. Never pass a
  live-media PID through `arch-chroot` as if the target could own it.
- Archinstall may unmount the new ESP before returning. Remount the validated
  target `/boot` from its generated fstab before native qvOS finalization, but
  never relax its permissions for the target user; the boot owner reads and
  replaces root-only artifacts through explicit sudo.
- Wait for Archiso's `pacman-init.service` before invoking Archinstall so every
  installed keyring package populates one live trust store. Do not duplicate
  `pacman-key` initialization or trade the wait for unsigned offline packages.
- Keep the Archinstall configuration free of network mirror URLs. The base
  system resolves only through the signed offline repository; native post-install
  policy then installs the reviewed provider channel, Stable by default.
- Record each ISO-only bind mount immediately, unwind them in reverse order on
  every exit, restore changed CPU governors, stop package prefetch, and persist
  the private install log only after its bind is detached. A cleanup failure
  may fail an otherwise successful install but must not hide an earlier error.
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
