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
  policy, or duplicate installers before Docker executes. Automatic context
  discovery derives only from the qvOS checkout that owns the executing
  builder. Select a different source explicitly with `QVOS_SOURCE_REPO` and
  `QVOS_SOURCE_REF`; never infer product authority from an ambient source path
  or the inherited `~/.local/share/omarchy` compatibility path.
- Create the private build stage on `QVOS_ISO_RELEASE_DIR` so large temporary
  images use the selected artifact filesystem. Before creating it, require a
  user-owned non-linked release directory with at least 40 GiB free for a
  cached build, 50 GiB for `--no-cache`, or 1 GiB for prepare-only validation.
  Ordinary build failures remove expanded scratch while preserving the named
  download caches; retain the exact hidden stage only when the operator passes
  `--retain-failed-stage` or an already-built artifact cannot publish safely.
- Bind the complete Archiso workspace from that private stage into the build
  container so image construction cannot silently fill Docker's host
  filesystem. A `--no-cache` build uses only this empty one-shot workspace;
  normal builds may nest the two named download-cache volumes inside it. Never
  delete or replace those reusable volumes during stage cleanup. Release the
  stage workspace back to the invoking user through a bounded container mount
  after every build attempt so explicitly retained failures remain inspectable
  and ordinary scratch remains removable, including package-created
  directories that were deliberately not owner-writable inside the image.
  Mark ownership as pending before Docker starts and retry that bounded release
  from the EXIT cleanup path, so interruption cannot strand a root-owned
  multi-gigabyte workspace. Keep the
  randomized stage root private,
  but make its cache mount root searchable inside the container so Pacman's
  unprivileged `DownloadUser` can reach the per-transaction directories it
  owns; never disable Pacman's download sandbox to work around host modes.
- Mount that exact staged source read-only at `/qvos`, embed it at `/root/qvos`,
  and resolve package-provider files from it before the first provider package.
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
  request or for release candidates. Use explicit `--pre-public` only when the
  pinned commit is not yet the public `OS` head; the resulting image is a
  development artifact whose updater may refuse that unpublished shallow
  source. A build without that flag must prove the pinned commit equals the
  public update branch before staging proceeds. For ISO changes, run fast
  staging and contract checks immediately and report any deferred full build.
- Use one cache-backed pre-public image as the integration-discovery artifact
  and keep its disposable installed VM across test cycles with explicit
  snapshots. A VM-local edit may confirm a diagnosis, but it is disposable:
  reproduce the repair immediately in its native repository owner, run focused
  and shared checks there, and deploy that exact repository change back into
  the diagnostic VM. Record the source revision behind every deployed repair
  so accumulated VM drift cannot become evidence.
- Treat installation media and the installed disk as separate lifecycle
  inputs. Before any installed-system boot or reboot result counts, detach the
  exact ISO, verify every emulated optical drive reports no inserted medium,
  and select the target disk as the boot source. If a guest stalls while media
  is attached, capture its console and kernel evidence, detach only that media,
  and repeat an ordinary reboot before classifying the behavior as a qvOS
  regression. A hard reset can recover a disposable VM but is never reboot
  proof.
- Do not rebuild the diagnostic image for ordinary desktop, command,
  configuration, service, update, removal, or security-policy repairs that can
  be faithfully deployed and exercised after installation. Rebuild when a
  changed owner affects live-media boot, the installer before repository
  deployment, partitioning, boot or early boot, offline package contents,
  pre-first-boot payload, or another behavior that cannot be reproduced in the
  installed VM. This saves build time and bandwidth; it never weakens the
  final clean-install gate.
- Unflagged image builds use the installed qvOS Stable package channel.
  `--dev` selects Edge and `--rc` selects RC only for those explicit reviewed
  image workflows; never make a development channel the production default.
- Require signatures for every online and offline package. Copy each detached
  signature with its cached package and validate the native builder for weak
  trust, unsupported repositories, and boot-kernel drift before Docker runs.
  Require signatures for direct local package files too, and keep the offline
  cache root-owned without group write access. Its directory is `0755`, while
  package archives, signatures, and repository metadata are non-executable
  `0644`; never use Archiso's trailing-slash recursive permission form for the
  mirror directory.
- The reusable package cache is a performance aid, never a trust source. If
  Pacman identifies a checksum-invalid cached archive, quarantine only that
  exact regular archive and its regular detached signature inside the ephemeral
  build container, then retry against current signed metadata. If Pacman already
  removed that exact archive, quarantine any safe matching signature and retry.
  Refuse links, nested paths, ambiguous output, and broad cache deletion; a
  repeated mismatch fails the build.
  Treat the reusable tool cache the same way: its mirror directory must be a
  real directory and its retained offline entry must be the exact expected
  link into the current staged Archiso tree. Reuse that exact link
  idempotently; never follow, replace, or delete a foreign cache entry. This
  host-side cache is not installed-system payload: after target integrity
  verification, the native target-only owner removes the safe duplicate signed
  archives that Pacman copied into the fresh target cache.
  The live medium and target use signed Arch `linux`; refuse T2 Macs before disk
  selection because qvOS does not operate a signing boundary for their required
  third-party kernel, firmware, audio, fan, Touch Bar, and graphics packages.
  Do not cache or stage `linux-ptl` either: qvOS does not replace the standard
  Arch kernel for one hardware generation or carry a separate kernel lifecycle.
- The interactive live image exposes no remote-administration service and does
  not install inherited cloud bootstrap, mirror discovery, or a parallel DHCP
  client. Its one network owner is systemd-networkd with iwd. Retain SSH
  tooling only for an operator to start explicitly from the recovery shell.
  Reuse the exact native resolver policy from
  `qvcore/install/system/printing-resolver.conf` in the staged live root so
  systemd-resolved cannot advertise or answer mDNS or LLMNR on an untrusted
  installation network; never duplicate that policy in the ISO source tree.
  Retire Archiso's enabling resolver drop-in, publish the native policy as the
  final `zz-qvos-live.conf` drop-in, and fail the build if any remaining main
  configuration or drop-in re-enables either discovery protocol. Validate this
  once in the staged profile and again in Archiso's fully assembled live root;
  an absent pre-package main configuration is valid, but inspection errors are
  not.
- Keep release package transfers on bounded HTTP/1.1 curl retries. Full image
  builds reuse the persistent package and tool caches by default because the
  development connection is bandwidth-constrained. Cached payloads remain
  untrusted until the normal signature, checksum, filename, and repository
  validation succeeds. Use `--no-cache` only for an explicitly approved
  diagnostic after stating its expected multi-gigabyte transfer cost; never
  make it a release-proof requirement. Retries preserve packages already
  verified during the same run.
- Pull the build-container image for every build and perform a complete
  container `pacman -Syu` before installing tools. Keep package names sorted and
  unique, reject provider-key payload drift, and validate remote checksums and
  filenames before using downloaded archives. Resolve the offline Node.js seed
  from the first official Linux x64 LTS entry, never the moving Current
  release, and verify the exact archive against that release's checksum list.
- For release verification, pin `QVOS_SOURCE_REF` to the intended qvOS commit,
  omit `--pre-public`, require that commit to equal the public `origin/OS`, and leave the embedded checkout on
  `OS` tracking `origin/OS` so the installed update guard remains usable.
  `QVOS_SOURCE_REPO` is only the build transfer source; embed the public,
  credential-free HTTPS `QVOS_UPDATE_REPO` as `origin`, use a shallow
  single-branch, tag-free one-commit checkout, and remove fetch provenance and
  ambient hooks. The
  native builder and profile come from that same pinned qvOS commit. Verify the
  image and embedded source, and keep optional Services and Development
  integrations out unless explicitly promoted.
- Archiso normalizes ordinary payload files to mode `0644`. Generate explicit
  `profiledef.sh` entries from the embedded Git tree's tracked `100755` modes;
  never maintain a second executable inventory. Reject an artifact unless the
  embedded worktree is clean with file-mode checking enabled.
- Build the ISO TUI only through `qvcore/tui/build`, with the exact digest from
  `qvcore/tui/source-hash`, and verify the embedded binary reports that digest,
  never `unmanaged`. Do not duplicate compiler flags or inherit ambient Go
  configuration in the ISO owner. Disable and
  remove clone reflogs before image assembly so transient builder identity is
  absent; retain the usable `OS` branch, `origin/OS` tracking, canonical public
  update URL, and clean Git worktree. The TUI is the singular installer: an
  image build fails if it cannot
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
  the singular `qvcore/boot/logo.png` raster master under the native `qvos`
  theme identity; never stage the
  inherited Plymouth payload or select its retired theme name.
  Replace the inherited Arch Syslinux splash from
  `release/iso/syslinux-splash.png`, and verify every rendered boot/install pixel.
- Preserve the boot setup, progress, and finale contract in `qvcore/tui/AGENTS.md`;
  the ISO layer owns no visual fork. Verify its direct Step 1/3 entry, increasing
  ring roles, fixed Region layout, safe-default Back/Continue erase gate, real
  milestone progress, single replacing log view, dim estimate/Help footer, and
  quiet finale in the live TTY.
- Every user-visible live-media boot label, installed Limine label, volume
  label, publisher, and application name says `qvOS`. Fresh images also use
  native `qvos` host, Plymouth, SDDM, session, and UKI identifiers. Derive the
  live `/etc/os-release` from `qvcore/branding/os-release`, retaining
  `ID_LIKE=arch` only as the truthful compatibility base; Archiso may append
  only its image ID and build version. Keep only
  truthful package-provider ABI, names and URLs, upstream provenance and review
  records, and the exact installed-source compatibility link; never recreate a
  retired internal boot identity.
- The staged target installer exports only qvOS names for source ownership,
  provider channel, and user metadata. Pass the validated provider input as
  `QVOS_PROVIDER_CHANNEL` and user data as `QVOS_USER_NAME` and
  `QVOS_USER_EMAIL`. Use an explicit clean chroot environment and bind XDG
  config, data, cache, and state paths to that target account so live-media
  state cannot escape into the installed user.
  Set `QVOS_CHROOT_INSTALL=1` as the exact native chroot-mode signal; never
  restore an inherited environment name or installer root.
- Put Gum in the Archinstall target bootstrap and execute the tracked native
  `install.sh` directly as the installed user. Never insert a hidden target
  Pacman transaction or a login-shell/source layer between Archinstall and the
  native installer; both obscure failures and create a second bootstrap owner.
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
  policy then installs the reviewed provider channel, Stable by default. Retain
  the exact online repository databases used to resolve the image and publish
  them atomically after Archinstall. Keep the temporary `offline` database
  through native package staging; only after the final provider configuration
  is selected may validation retire it. The first installed-system package
  action must not require a partial online refresh.
- Record each ISO-only bind mount immediately, unwind them in reverse order on
  every exit, restore changed CPU governors, stop package prefetch, and persist
  the private install log only after its bind is detached. A cleanup failure
  may fail an otherwise successful install but must not hide an earlier error.
- Never reboot directly from a successful native installer return. After all
  ISO-only binds are detached, require the exact root-owned completion marker,
  absence of broad installer authorization and Pacman's lock, an empty safe
  installed-system package cache, and a nonempty root-owned private log. Commit
  the Btrfs transaction when applicable, synchronize both target root and ESP,
  byte-compare the installed verifier with its root-owned live-image owner,
  then run that live owner against the mounted target under the exact reviewed
  chroot signal so an RC or Edge image can resolve only its matching provider
  files. Never execute user-owned target source as root. Any failure returns to
  the live error path; the ISO layer must not duplicate feature-specific
  validation.
- Keep installer diagnostics local. The live ISO must not stage a diagnostic
  uploader or offer external log upload; users may inspect or explicitly save
  the private install log instead.
- Once a release candidate commit is selected, freeze feature work until its
  rehearsal passes or the candidate is abandoned. During the freeze, accept
  only upstream compatibility, build or installation blockers, verification
  repairs, and security fixes; every change selects a new candidate commit.
- Select that final candidate only after the diagnostic VM has no known
  high-impact issue. Build a new exact artifact from the converged repository,
  then install it onto an empty disposable disk and repeat the full lifecycle.
  Detach and verify the installation media before the first installed boot,
  record its boot identity, then require a second ordinary disk-only reboot
  with a different boot identity and no failed units, blocked kernel workers,
  or optical-media I/O errors.
  Diagnostic-image and VM evidence explains discoveries but cannot satisfy a
  final-candidate gate. A failure in the final rehearsal returns to the native
  owner, creates a new candidate commit, and requires a new artifact; never
  patch or bless the prior ISO in place. One diagnostic build plus one final
  proof build is the normal target, not a limit that permits stale evidence.
- Never call a candidate releasable from static tests or a successful image
  build alone. Complete the build, embedded-source, clean-install, reboot,
  base-without-optional-integrations, update, and configuration-reconciliation
  evidence in `release/iso/README.md`. Record Services and Development results
  separately so optional integrations never redefine qvOS base readiness.
