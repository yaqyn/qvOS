# qvOS Release Candidate Gate

An ISO is a development artifact until every base gate below has current,
dated evidence for the same pinned inputs. Keep the evidence beside the
artifact outside Git; it can contain machine and installation details.

## 1. Freeze And Pin

- Select one full qvOS commit and freeze feature work for that candidate.
- Complete `git qvsync --audit`, resolve every upstream capability decision,
  and verify clean development, tracking, remote, and live source parity.
- Pin `QVOS_SOURCE_REF` to that qvOS commit and `QVOS_OMARCHY_ISO_REF` to the
  reviewed full commit from official `omacom-io/omarchy-iso` `main`.
- Keep qvCORE out of the image. Its optional lifecycle never gates base
  readiness.

Any source change creates a new candidate and invalidates later evidence from
the previous one.

## 2. Verify And Build

- Run `qv/tui/owner-contracts --check`, all Go tests, a production TUI build,
  Bash syntax and ShellCheck for changed shell, `test/qvos/run.sh`, and
  `git diff --check`.
- Run a fresh `qvos-build --prepare-only --rc` with both refs pinned. Inspect
  the staged patch application and package resolution before the full build.
- Build with downloads explicitly allowed and no reused ISO package cache for
  the release proof. Record both input commits, the artifact name and size,
  SHA-256, build result, and retained failure-stage path when applicable.
- Inspect the completed image and prove that its embedded qvOS source equals
  `QVOS_SOURCE_REF`, is on `OS` tracking `origin/OS`, its tracked executable
  modes match Git, and the embedded worktree is clean with
  `core.filemode=true`; do not infer any of this from the build command. Verify
  the embedded `qvos-tui --source-hash` equals the shared source digest and is
  not `unmanaged`, and reject build-only Git reflogs or private builder
  identity in the embedded checkout.
- Boot the image and capture the Limine, Plymouth, installer, progress, and
  finale surfaces. Their pixels must use exact black (`#000000`) and neutral
  grayscale; Plymouth and the installer may use only qvOS red tonal accents
  (`#5f0000`/`#b00000`/`#d00000`), while Limine stays grayscale-only. Reject
  inherited Omarchy/Tokyo Night colors or stale glyphs from an earlier TUI
  frame. Confirm the installer starts directly at its qvOS welcome on Step 1/3,
  then uses one ring for Region, two for Account, and three for Install drive.
  Verify Region shows Keyboard with Time zone, Account shows Username, Machine
  Name, Password, and Confirm Password, and the drive step becomes its own final
  erase confirmation. Wide screens use the divided side composition with the
  model and context on the right; narrow screens stack safely without a model.
  Confirm Region filtering does not move any field, divider, tracker, title, or
  column; Tab and Shift+Tab cycle every field; invalid account characters do not
  enter; and password mismatches cannot continue. Primary actions use a red
  chevron and white label without a filled background. Progress exposes `v log`,
  `ctrl+v terminal`, and `? help`; V opens the same-process side log, while
  Ctrl+V opens the minimal full terminal with no copy-all or navigation actions.
  Confirm both shortcuts are inactive on the finale. Verify the live-media
  progress process exits before target-install progress starts, and that target
  progress exits before the finale or error fallback; two renderers must never
  own the installer terminal together.
- Inspect ISO metadata and every UEFI, GRUB, Syslinux, and installed Limine
  menu. All displayed product, entry, publisher, and application names must say
  `qvOS`; inherited internal compatibility identifiers may remain lowercase
  `omarchy` only when they are not shown as branding.

## 3. Clean Installation Rehearsal

Use a disposable UEFI VM, a separate test machine, or separately approved
test storage. Never overwrite this development installation for rehearsal.

- Boot the artifact and complete the normal disk installer from an empty
  target without qvCORE.
- Reboot from the installed disk and verify login, networking, audio, graphics,
  storage, the qvOS menu, the shared TUI, and installed source/payload parity.
- Exercise the read-only update preflight, then one real update when an update
  exists. Verify the branch guard, Omarchy delegation, qvOS post-update hooks,
  configuration reconciliation, reboot handling, and a clean second boot.
- Confirm no failed system or user units and no private build, installer, or
  development-machine data entered the image or installed source.

## 4. Optional Integration Rehearsal

After the base passes, test Proton and qvDEV Install and Uninstall separately.
Verify enrollment, convergence, preserved credentials and personal data, and
complete owned cleanup. A failure blocks that optional stack, not qvOS base.

## Pass Condition

Call the candidate releasable only when the same pinned artifact passes every
base gate through the clean second boot. Record failures truthfully, repair the
owner, select a new candidate, and repeat the affected gates; never edit or
bless a previously built image in place.
