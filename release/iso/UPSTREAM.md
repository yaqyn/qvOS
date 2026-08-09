# ISO Builder Provenance

The native qvOS Archiso profile began as a reviewed port of selected files from
`omacom-io/omarchy-iso` commit
`023cd14f2a64bad856e79714f79d8f9f09605727`, under the MIT license preserved in
`LICENSE.omarchy-iso`.

qvOS now owns and executes the implementation under `release/iso/`. Builds do
not clone, patch, mount, or run Omarchy ISO source. Future upstream changes are
read-only review input through qvsync: each upstream commit receives an explicit
decision, and selected fixes are independently ported into the native owner.

The complete review through
`6b2f8a6ac701452da5fb20a1ecf431e774d3ee3a` is recorded in
`upstream/qvsync/iso-upstream-reviews/`. Selected later fixes were independently
ported for Archinstall 4.4 configuration, exact offline-mirror resolution,
bounded package retries, zstd live-root compression, synchronous initramfs
unpacking, package prefetch, temporary CPU-governor restoration, reserved-user
validation, target-ESP remounting, and deterministic bind-mount cleanup. qvOS
retains signed offline packages and intentionally omits the upstream private
Python orchestrator, T2 package stack, protected/alongside installer, debug and
VM tools, unattended SSH, cidata, and Tailscale paths, and deferred-provisioning
and factory-reset state with its temporary UKI-embedded unlock material.
