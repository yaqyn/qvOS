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
- For release verification, pin `QVOS_SOURCE_REF` to the intended qvOS commit,
  build the intended `QVOS_OMARCHY_ISO_REF`, verify the image and embedded
  source, and keep optional qvCORE stacks out unless explicitly promoted.
- Once a release candidate commit is selected, freeze feature work until its
  rehearsal passes or the candidate is abandoned. During the freeze, accept
  only upstream compatibility, build or installation blockers, verification
  repairs, and security fixes; every change selects a new candidate commit.
- Never call a candidate releasable from static tests or a successful image
  build alone. Complete the build, embedded-source, clean-install, reboot,
  base-without-qvCORE, update, and configuration-reconciliation evidence in
  `qv/iso/README.md`. Record optional-stack results separately so qvCORE never
  redefines qvOS base readiness.
