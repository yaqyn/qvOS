# qvOS ISO Workflow

Read this file completely when changing the qvOS image builder, ISO patch,
embedded source, installer integration, or release-image verification.

`qv/tui/bin/qvos-build` owns qvOS image construction.

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
  source, and keep optional qvCORE applications out unless explicitly promoted.
