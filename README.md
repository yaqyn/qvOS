# qvOS

qvOS is an independent, focused Arch distribution. Omarchy is its read-only
code upstream and credited package-infrastructure provider, not its product
identity.

- qvOS decides its branding, product composition, defaults, exposed
  capabilities, installation, update policy, and release behavior.
- Useful Omarchy capability is reviewed and ported into native qvOS owners;
  upstream commits are never merged automatically into qvOS.
- qvOS owns package selection and safe update integration while Omarchy supplies
  the stable Arch mirror, curated repository, and signing keyring. qvOS does not
  operate a parallel package repository or mirror.
- `qvcore/` is the mandatory native implementation of qvOS. It owns the
  installed product domains and is not an optional software bundle.
- Optional integrations are classified by purpose. Proton belongs to Services;
  the workstation formerly named qvDEV is now Devel under Development. qvOS
  remains complete without either optional integration.

```text
qvcore/       Mandatory installed qvOS implementation.
services/     Optional service integrations, currently Proton.
development/  Optional development integrations, currently Devel.
release/      Image construction and release evidence.
upstream/     Read-only upstream review tooling and records.
compat/       Narrow migration adapters for supported legacy qvOS states.
test/         Tests split along the same ownership boundaries.
```

The installed source checkout is `~/.local/share/qvos`. During the native
transition, `~/.local/share/omarchy` is only an exact relative compatibility
link to that canonical checkout.

See [`qvcore/README.md`](qvcore/README.md) for the ownership map and lifecycle.
