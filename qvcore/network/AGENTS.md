# qvOS Network Policy Workflow

Read this file completely when changing DNS selection, Cloudflare WARP,
systemd-resolved policy, networkd DNS sources, or privileged network helpers.

`qvcore/network/setup-dns` is the interactive owner. `qv-setup-dns` carries
native command metadata; `omarchy-setup-dns` is a metadata-free compatibility
adapter. Native menus and TUI catalogs call only the qvOS route. WARP remains an
explicit, on-demand AUR install and must require acceptance of Cloudflare's
terms before registration.

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

Tailscale is an optional-software owner, not qvOS DNS policy. Its native
authentication may enable `tailscaled`, but must not accept advertised routes,
change qvOS DNS policy, or create an admin Web App implicitly. Users opt into
those capabilities separately after joining their tailnet.

`dns-policy migrate-legacy` is the one unreleased-state cleanup for the former
full-file resolver policy and immediately inserted `UseDNS=no` lines. It acts
only on exact known qvOS/Omarchy-generated content, restores the installed
systemd default from the matching package cache when available, and otherwise
uses a neutral `[Resolve]` file. Preserve unknown or modified configuration.

Run `qvcore/network/check`, `test/qvcore/qvos-dns-test.sh`, menu, TUI owner,
install, update, migration, CLI, product, and upstream-overlay tests, then Bash
syntax, ShellCheck, and the full qvOS suite. Live verification may install the
root helper and inspect policy status, but never change the selected provider
or disconnect WARP without explicit live approval.
