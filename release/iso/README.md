# qvOS Release Candidate Gate

An ISO is a development artifact until every base gate below has current,
dated evidence for the same pinned inputs. Keep the evidence beside the
artifact outside Git; it can contain machine and installation details.

## 0. Diagnostic Convergence

- Before selecting the final candidate, build one cache-backed pre-public
  diagnostic image and install it in a disposable VM. Preserve explicit VM
  snapshots at clean lifecycle boundaries and reuse this installation for
  integration discovery instead of rebuilding after each ordinary repair.
- A VM-local edit is permitted only as a diagnostic prototype. Once it proves
  the hypothesis, implement the repair in the singular repository owner, run
  its focused and shared checks, then deploy that exact repository revision to
  the diagnostic VM. Record the deployed revision and reject unexplained VM
  drift. Never treat a hand-modified installed system as product source.
- Exercise installation, desktop, command, configuration, package, service,
  update, removal, failure, reboot, and recovery behavior in the same VM until
  no known high-impact issue remains. Rebuild during this phase only when a
  repair affects live media, installation before repository deployment,
  partitioning, boot or early boot, offline package contents, first-boot
  payload, or behavior that cannot be reproduced faithfully after install.
- Before counting an installed boot, detach the exact diagnostic ISO, verify
  every emulated optical drive is empty, and select the installed disk as the
  boot source. A reset may recover a disposable VM, but it is not reboot
  evidence. If attached media causes a stall, preserve the console and kernel
  evidence and repeat an ordinary disk-only reboot before assigning the fault
  to qvOS.
- Diagnostic evidence guides fixes but never satisfies the final release gate.
  After convergence, select the exact final commit and proceed below with a new
  artifact and an empty target disk. One diagnostic build plus one final proof
  build is the normal path; correctness may still require another candidate.

## 1. Freeze And Pin

- Select one full qvOS commit after diagnostic convergence and freeze feature
  work for that candidate.
- Complete `git qvsync --audit`, resolve every upstream capability decision,
  and verify clean development, tracking, remote, and live source parity.
- Pin `QVOS_SOURCE_REF` to that qvOS commit. Its native builder and profile are
  the only executable ISO inputs. Complete both qvsync review ledgers and record
  the exact reviewed Omarchy and Omarchy ISO baselines without making either
  upstream an executable build dependency.
- Use `--pre-public` only for development rehearsal before that commit is the
  public `OS` head. The builder must reject an unflagged image when its pinned
  commit differs from the public update branch; a pre-public image is never a
  releasable artifact and its updater may refuse the unpublished shallow source.
- Keep optional Services and Development integrations out of the image. Their
  lifecycle never gates base readiness; qvCORE itself is the image's mandatory
  qvOS implementation.

After final candidate selection, any source change creates a new candidate and
invalidates later evidence from the previous one. Earlier diagnostic evidence
remains useful only for discovery and regression targeting.

## 2. Verify And Build

- Run `qvcore/tui/owner-contracts --check`, all Go tests, a production TUI build,
  Bash syntax and ShellCheck for changed shell, `test/qvcore/run.sh`, and
  `git diff --check`.
- Run a fresh `qvos-build --prepare-only --rc` with the qvOS ref pinned. Inspect
  the staged native builder, profile, package trust, and source validation
  before the full build.
- Confirm the free-space preflight reports at least 40 GiB available on the
  selected release filesystem, then build with downloads explicitly allowed
  and the persistent package and tool caches enabled. The caches reduce
  bandwidth only: every reused payload must pass the same signature, checksum,
  filename, repository, and provenance checks as a fresh download. Record the
  qvOS input commit, provider channel, container
  image identity, resolved package inventory, artifact name and size, SHA-256,
  selected Node.js LTS release and checksum, build result, and any explicitly
  retained failure-stage path. Set `QVOS_ISO_RELEASE_DIR` to a
  filesystem with enough capacity for both the temporary image and published
  artifact; the private stage is deliberately colocated there. Ordinary
  failures clean expanded scratch and preserve the reusable download caches;
  use `--retain-failed-stage` only for a deliberate debugging capture.
- Confirm the full Archiso workspace is mounted from that private stage. After
  either success or failure, verify it is owned and removable by the invoking
  user, including package-created read-only directories; a clean build must
  not leave expanded image data in Docker's host filesystem or in `~/.cache`.
  Preserve and reuse the named package and tool download caches for release and
  development builds. Run `--no-cache` only as an explicitly approved
  diagnostic after stating its expected multi-gigabyte transfer cost; it is not
  a release-proof requirement.
- Verify that repository and direct local package signatures are required, the
  offline cache is not group-writable, its package archives, signatures, and
  repository metadata are non-executable, the generated Archinstall
  configuration contains no network mirrors, and native post-install policy
  restores the reviewed provider channel, Stable by default. Confirm the image
  also carries exactly one nonempty `core`, `extra`, `multilib`, and `omarchy`
  database from the same resolution snapshot. The installer must preserve the
  temporary `offline` database through native package staging, then validate
  the final provider databases and retire `offline` at the handoff boundary.
- Exercise reused-cache recovery: a Pacman-identified checksum-invalid archive
  is quarantined individually inside the ephemeral builder and fetched again.
  If Pacman already removed that exact archive, the retry remains valid and any
  matching safe signature is quarantined. Ambiguous or repeated mismatches fail
  closed without clearing the whole cache.
- Confirm the live image does not contain inherited cloud bootstrap, mirror
  discovery, or a parallel DHCP client, and does not start SSH. Networking has
  one systemd-networkd/iwd owner and remains client-only until the user
  explicitly starts a recovery service.
- Inspect the completed image and prove that its embedded qvOS source equals
  `QVOS_SOURCE_REF`, is on `OS` tracking `origin/OS`, its tracked executable
  modes match Git, and the embedded worktree is clean with
  `core.filemode=true`. Confirm `origin` is the intended public credential-free
  HTTPS qvOS update URL, the checkout is shallow, single-branch, tag-free, and
  contains only the pinned commit, and no source-machine path, fetch record,
  reflog, or ambient hook remains; do not
  infer any of this from the build command. Verify
  the embedded `qvos-tui --source-hash` equals the shared source digest and is
  not `unmanaged`, and reject build-only Git reflogs or private builder
  identity in the embedded checkout.
- Boot the image and capture the Limine, Plymouth, installer, progress, and
  finale surfaces. Limine and the TUI use exact black (`#000000`) and neutral
  grayscale, with red reserved for the installer's active field and selected
  disk rails, focused final action field, and loading bar. Ring models remain
  pure grayscale with bright white highlights. Plymouth must match the promoted
  live theme with its graphite `#090909` graphical background and exact promoted
  assets. Reject stale glyphs from an earlier TUI frame. Confirm the installer
  starts directly on Step 1/3, then uses one ring for Region, two for Account,
  and three for Install drive. Verify Region shows Keyboard with Time zone,
  Account shows Username, Machine Name, Password, and Confirm Password, and the
  drive step becomes its own final erase confirmation. After selection, the
  complete drive remains
  dimmed on the left and its fixed hint becomes the bright marker-free erase
  notice. The right removes its model and setup hierarchy, leaving only stacked
  `Back` and `Continue` fields. Back is selected by default; arrows and Tab move
  the bright red-underlined focus, Escape returns, and only an explicit Enter
  on Continue starts installation. Disk descriptions wrap in full and only the
  active selected disk carries one continuous red rail across its wrapped lines;
  the rail becomes deep red after confirmation. No confirmation box, marker, or
  button chrome is present. Wide screens keep left controls and the restrained
  model plus compact context on
  the right without a divider; narrow screens stack safely without a model.
  Confirm Region filtering does not move any field, context line, title, or
  column. Left and Right cycle the active fields or choices on every step; Up
  and Down navigate Region matches, then cycle Account fields, drive choices,
  and final actions. Tab and Shift+Tab retain field navigation. Invalid account
  characters do not enter, and password mismatches cannot continue. Every setup step keeps the
  same two-row contextual hint slot beneath its left controls. Validation
  replaces that hint with calm bright-gray copy, never a second message or
  marker, and cannot move the form. Focused fields use near-white text with a
  red rail, incomplete inactive fields stay slightly brighter, and valid
  completed fields dim. Choices and primary actions use dim/near-white
  grayscale without markers or filled backgrounds; the focused field and
  selected disk get red rails. Progress shows only its loading message,
  percentage, shared thin red/dim rail with a restrained breathing tip, and
  centered dim `Estimated 4:00  -  ? Help` footer. The estimate becomes
  `Any moment now` at zero and never drives milestone progress. V replaces the
  rail with one same-process frameless, title-free log view and returns to
  progress. Boot has no Ctrl+V route, switch cue, copy-all, or navigation
  actions. Confirm the finale has no log or terminal view, shows `Finished` and
  `Reboot`, and automatically continues after a hidden five-second timer that
  any key stops. Verify the live-media progress process exits before
  target-install progress starts, and that target progress exits before the
  finale or native error path; two renderers must never own the installer terminal
  together.
- Inspect ISO metadata and every UEFI, GRUB, Syslinux, and installed Limine
  menu. All displayed product, entry, publisher, and application names must say
  `qvOS`. Confirm live and installed `/etc/os-release` report `ID=qvos` and
  `ID_LIKE=arch`, and that Plymouth, SDDM, session, hostname, and UKI identities
  use `qvos` or `qvOS`; `omarchy` may remain only in truthful
  package-provider inputs, upstream provenance and review records, the exact
  chroot compatibility signal, and the installed-source compatibility link.
- Inspect the rendered Syslinux splash and menu palette. Its background is
  exact black, its artwork and text are neutral grayscale, and no inherited
  Arch blue or red accent remains in this bootloader path.

## 3. Clean Installation Rehearsal

Use a disposable UEFI VM, a separate test machine, or separately approved
test storage. Never overwrite this development installation for rehearsal.

- Boot the artifact and complete the normal disk installer from an empty
  target without optional Services or Development integrations.
- Before the first installed boot, stop any automatic finale action if needed,
  detach the exact installation ISO, verify every emulated optical drive is
  empty, and select the installed disk as the boot source. Record the resulting
  boot identity; a hypervisor reset does not satisfy this gate.
- Reboot from the installed disk and verify login, networking, audio, graphics,
  storage, the qvOS menu, the shared TUI, and installed source/payload parity.
- Before updating, install and remove one harmless repository package through
  the native `qv pkg` routes. Verify the seeded repository databases resolve
  it, package signatures remain required, and the removal leaves no orphaned
  test payload.
- Exercise the read-only update preflight, then one real update when an update
  exists. Verify the branch guard, credited package-provider transaction, qvOS
  post-update hooks, configuration reconciliation, reboot handling, and a clean
  second boot.
- Keep the installation media detached for that second ordinary reboot. Record
  a different boot identity and verify the current boot has no failed units,
  blocked kernel workers, or optical-media I/O errors.
- Confirm no failed system or user units and no private build, installer, or
  development-machine data entered the image or installed source.

## 4. Optional Integration Rehearsal

After the base passes, test the Proton Service and Devel Development
integration independently.
Verify enrollment, convergence, preserved credentials and personal data, and
complete owned cleanup. A failure blocks that optional integration, not qvOS
base.

## Pass Condition

Call the candidate releasable only when the same pinned artifact passes every
base gate through the clean second boot. Record failures truthfully, repair the
owner, select a new candidate, and repeat the affected gates; never edit or
bless a previously built image in place.
