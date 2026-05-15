# qv

qvOS-owned source lives here.

Keep upstream Omarchy files in their existing locations whenever practical. Put qvOS-only helpers, assets, and generated support files under this namespace so upstream syncs stay easy to review.

Expected layout:

```text
qv/
  scripts/    Private helper scripts used by qvOS config.
  git/        Private git helper source and installers.
  assets/     qvOS-only source assets.
```
