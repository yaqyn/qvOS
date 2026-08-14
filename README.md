# qvOS

qvOS is a focused Arch distribution with a native desktop, installer, update
lifecycle, security policy, and release process.

- `qvcore/` is the mandatory native implementation of qvOS. It owns the
  installed product domains and is not an optional software bundle.
- Optional integrations are classified by purpose. Proton belongs to Services
  and Devel belongs to Development. qvOS remains complete without either
  optional integration.

```text
qvcore/       Mandatory installed qvOS implementation.
services/     Optional service integrations, currently Proton.
development/  Optional development integrations, currently Devel.
release/      Image construction and release evidence.
upstream/     Read-only upstream review tooling and records.
compat/       Narrow migration adapters for supported legacy qvOS states.
test/         Tests split along the same ownership boundaries.
```

The installed source checkout is `~/.local/share/qvos`.
`~/.local/share/omarchy` is retained only as an exact relative compatibility
link to that canonical checkout. Generated and checked runtime payloads live
separately under `~/.local/lib/qvos` so the Git source stays clean.

See [`qvcore/README.md`](qvcore/README.md) for the ownership map and lifecycle.

## Provenance and infrastructure

qvOS reviews selected work from [Omarchy](https://github.com/basecamp/omarchy)
through its read-only qvsync workflow and uses Omarchy's credited signed Stable
package infrastructure. qvOS owns package selection, integration, defaults,
installation, updates, and releases; upstream commits are reviewed and ported
deliberately rather than merged into the product.
