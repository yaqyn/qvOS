# qvOS Network Policy Workflow

Read this file completely when changing DNS selection, Cloudflare WARP,
systemd-resolved policy, networkd DNS sources, or privileged network helpers.

`qvcore/network/setup-dns` is the interactive owner. `qv-setup-dns` carries
native command metadata; `omarchy-setup-dns` is a metadata-free compatibility
adapter. Native menus and TUI catalogs call only the qvOS route. WARP remains an
explicit, on-demand AUR install and must require acceptance of Cloudflare's
terms before registration.

`warp-policy` is the singular privileged privacy owner for an installed WARP
daemon. `install` publishes it root-owned, and reconciles it before WARP starts
and after package updates. Its exact systemd drop-in makes the vendor state and
log roots private and stops stdout and stderr from duplicating credential-like
registration details into the journal while leaving the runtime IPC socket
available to the desktop account. Apply the policy idempotently, restart only
an active daemon whose effective policy is stale, and refuse a modified qvOS
drop-in or unsafe vendor directory. Never read, copy, print, or test against
registration contents. A live policy activation may briefly restart WARP and
requires explicit approval; deleting or rotating a registration is a separate
external mutation and is never implied by hardening.

`dns-policy` is the singular privileged configuration owner installed
root-owned at `/usr/lib/qvos/network/dns-policy` by `install`. It validates
every provider and custom address again after escalation, writes only
`80-qvos-dns.conf` drop-ins, and never edits inherited `.network` files for
ordinary operation. Static providers disable DHCP and RA DNS through exact
per-network drop-ins; DHCP removes only validated qvOS-owned drop-ins. Every
file replacement is atomic and the multi-file transaction rolls back on
failure.

Custom DNS accepts one to eight literal IPv4 or IPv6 addresses with an optional
validated `#server-name`; it never accepts configuration syntax, hostnames in
place of addresses, ports, interface selectors, control characters, or extra
directives. Validate before disconnecting WARP so rejected input has no side
effects. Do not expose registrations, identifiers, or command output that can
contain credentials.

`regdom` owns automatic wireless-region selection. The package-owned
`/etc/conf.d/wireless-regdom` is an administrator configuration surface, so the
owner preserves one valid active choice and otherwise atomically uncomments
exactly one country supported by the package after deriving it from the
validated system timezone. Never source that file as shell, append assignments,
or create multiple active regions. A live activation failure restores the prior
file; target-chroot installation only persists the selected region.

Tailscale is an optional-software owner, not qvOS DNS policy. Its native
authentication may enable `tailscaled`, but must not accept advertised routes,
change qvOS DNS policy, or create an admin Web App implicitly. Users opt into
those capabilities separately after joining their tailnet.

The unreleased full-file resolver and inline `UseDNS=no` transition is retired
after the only supported installation converged. The installed helper exposes
only `apply`, `check`, and `validate`; never restore a legacy policy scanner or
package-cache restoration path to normal network operation.

Run `qvcore/network/check`, `test/qvcore/qvos-dns-test.sh`, menu, TUI owner,
install, update, migration, CLI, product, and upstream-overlay tests, then Bash
syntax, ShellCheck, and the full qvOS suite. Live verification may install the
root helpers and inspect policy status, but never change the selected provider,
restart or disconnect WARP, or rotate its registration without explicit live
approval.
