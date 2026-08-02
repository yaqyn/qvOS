# qvOS

qvOS is an independent, focused Arch distribution. Omarchy is its primary
read-only upstream, not its product identity.

- qvOS decides its branding, product composition, defaults, exposed
  capabilities, installation, update policy, and release behavior.
- Useful Omarchy capability is reviewed and ported into native qvOS owners;
  upstream commits are never merged automatically into qvOS.
- During the native transition, canonical qvOS configuration, policy, assets,
  and implementation live under `qv/` while inherited implementations are
  retired one domain at a time.
- qvCORE is a separate, optional collection of two integrated stacks. Each has
  only Install and Remove; qvOS does not require any stack to be healthy.

See [`qv/README.md`](qv/README.md) for the ownership map and lifecycle.
