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
  screensaver/ Screensaver launchers and terminal profile.
  thunar/      Thunar feature entry points.
  tmux/        Persistent tmux session manager.
  tui/         ISO installer, progress UI, and image build tooling.
  waybar/      qvOS prayer clock modules.
```

qvCORE components marked `# qvcore:lifecycle=1` own four local operations:
`--status`, `--repair`, `--adopt`, and `--disable`. Their post-update hooks run
only when the deployed component exposes that marker, so a source update and a
user integration cannot silently cross versions.

`qv/thunar/actions.sh` is the preservation-safe owner for qvOS custom actions.
The base desktop installs only the default Thunar helpers; optional Share,
Codex, and Proton helpers are installed and repaired by their qvCORE component.

## Upstream boundary

Keep implementations in `qv/`; touch inherited Omarchy paths only at the seam
that exposes, installs, or refreshes them:

- `bin/` owns CLI routes and menu handoffs.
- `config/` and `default/` own user-facing defaults and overlays.
- `install/` owns fresh-install payloads; `migrations/` owns existing systems.
- `test/qv*-test.sh` guards qvOS product and integration contracts.
- `themes/yaqyn/` is the intentionally singular bundled qvOS theme.

When one of these seams changes, trace it back to its `qv/` owner and verify
both the fresh-install and update paths. This keeps qvsync conflicts localized
and makes intentional omissions from upstream visible during review.
