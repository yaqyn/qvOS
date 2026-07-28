# qvOS

qvOS is a focused Arch system built as a clean overlay on Omarchy.

- Omarchy remains the upstream system foundation.
- qvOS-owned configuration, policy, assets, and implementation live under
  `qv/` and are applied through small integration seams.
- qvCORE is a separate, optional collection of five integrated stacks. Each has
  only Install and Remove; qvOS does not require any stack to be healthy.

See [`qv/README.md`](qv/README.md) for the ownership map and lifecycle.
