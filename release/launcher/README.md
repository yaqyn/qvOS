# qvOS public launcher

```sh
curl -fsSL qvos.yaqyn.dev | sh
```

The command downloads a checksum-verified compiled Linux x86_64 TUI and opens
it in the current terminal. It needs curl, tar, sha256sum, and an interactive
terminal. It does not install qvOS or require a Go toolchain on the client.
The temporary binary and Build adapter are removed when the interface exits.

System contains Build and Download; About contains Developer and Project.
Build requires Git and an accessible Docker daemon. Only after confirmation,
it fetches the official OS branch, checks its TUI source digest against the
compiled interface, and delegates to `release/iso/build`. The existing builder
owns package transfers, disk-space checks, caching, cleanup, and output under
`~/qvISO`. The launcher does not write an operating-system disk.

Download remains unavailable until a working-confirmed ISO URL and SHA-256 are
supplied. `/release.json` reports `{"iso":null}`; a launcher deployment is not
an ISO release or proof that an ISO has passed its release gate.

## Publish

From `release/launcher/worker`:

```sh
npm ci
npm run build
npm run typecheck
cf deploy --prebuilt --mode production --dry-run
cf deploy --prebuilt --mode production
```

`../package` is the payload owner. It calls the singular TUI compiler, then
writes ignored static assets and provenance metadata. Archive URLs include
the complete archive SHA-256 and are immutable; the root script is uncached.
The Cloudflare Worker, script, and matching payload deploy together through
cf. `cloudflare.config.ts` owns the account, domain, assets binding, and logs.
Authentication stays in the user's cf profile, never the repository.

Check `/health` for the binary source digest, commit, and archive checksum.
Test the literal curl-to-sh command in a PTY after deploying, including keyboard
navigation and clean exit. Run `test/release/qvos-launcher-test.sh` for pipe
input, cleanup, tampering, provenance rejection, and missing-terminal tests.
Roll back through Cloudflare Worker deployments so script and assets stay paired.
