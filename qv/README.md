# qv

qvOS-owned source lives here.

Keep upstream Omarchy files in their existing locations whenever practical. Put qvOS-only helpers, assets, and generated support files under this namespace so upstream syncs stay easy to review.

Expected layout:

```text
qv/
  git/        Private git helper source and installers.
  iso/        ISO integration patches.
  scripts/    Private helpers used by qvOS config.
  thunar/     Thunar feature entry points.
  tui/        qvOS apply, reset, build, update, and ISO tooling.
```
