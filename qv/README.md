# qv

qvOS-owned source lives here.

Keep upstream Omarchy files in their existing locations whenever practical. Put qvOS-only helpers, assets, and generated support files under this namespace so upstream syncs stay easy to review.

Expected layout:

```text
qv/
  core/        Opt-in qvCORE integration components.
  desktop/     Shared context, web, and Hyprland desktop helpers.
  git/         Private git helper source and installers.
  iso/         ISO integration patches.
  maintenance/ qvOS base repair, inherited-extra review, and upstream guards.
  screensaver/ Screensaver launchers and terminal profile.
  thunar/      Thunar feature entry points.
  tmux/        Persistent tmux session manager.
  tui/         ISO installer, progress UI, and image build tooling.
  waybar/      qvOS prayer clock modules.
```

qvCORE components marked `# qvcore:lifecycle=1` own four local operations:
`--status`, `--repair`, `--adopt`, and `--disable`. One base-owned post-update
hook checks only explicitly enabled component state, delegates repairs to the
component owner, and ignores optional applications that were never enabled or
were later removed.

## Product lifecycle

qvOS has one supported base: a curated, unbloated Omarchy system. qvCORE adds
optional applications and integrations without changing base ownership.

- `omarchy qvos repair` restores missing base packages, qvOS runtime payloads,
  missing qvOS config, and enabled qvCORE integrations. Customized qvOS config
  is preserved unless `--restore-config` is explicitly requested.
- `omarchy qvcore disable` removes only enabled qvOS-owned integration and
  maintenance state. Installed applications, authentication, network choices,
  and personal data remain.
- `omarchy qvos cleanup inherited` previews a reviewed legacy package catalog.
  Applying cleanup still requires explicit package selection and confirmation.

Returning to upstream Omarchy is not an in-place qvOS lifecycle. It requires a
separate documented installation rather than a source, branch, or config reset.

`qv/thunar/actions.sh` is the preservation-safe owner for qvOS custom actions.
The base desktop installs only the default Thunar helpers; optional Share,
Codex, and Proton helpers are installed and repaired by their qvCORE component.

## Upstream boundary

Keep implementations in `qv/`; touch inherited Omarchy paths only at the seam
that exposes, installs, or refreshes them:

- `bin/` owns CLI routes and menu handoffs.
- `config/` and `default/` own user-facing defaults and overlays.
- `install/` owns fresh-install payloads; `migrations/` owns existing systems.
- `test/qvos/*-test.sh` guards qvOS product and integration contracts;
  `test/qvos/run.sh` runs them together with all upstream root tests.
- `themes/yaqyn/` is the intentionally singular bundled qvOS theme.

When one of these seams changes, trace it back to its `qv/` owner and verify
both the fresh-install and update paths. This keeps qvsync conflicts localized
and makes intentional omissions from upstream visible during review.
