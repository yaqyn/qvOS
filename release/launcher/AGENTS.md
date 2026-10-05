# Public qvOS launcher

`release/launcher/` owns distribution of the compiled public TUI through
`curl -fsSL qvos.yaqyn.dev | sh`. Read `qvcore/tui/AGENTS.md` and
`release/iso/AGENTS.md` when changing its payload or Build handoff.

- Use cf with `worker/cloudflare.config.ts`; keep account credentials outside
  source. Static assets and the Worker deploy as one version.
- `package` compiles only through `qvcore/tui/build`. Publish the source digest,
  source commit, and immutable archive checksum. Generated assets are ignored.
- The bootstrap is POSIX-compatible despite its standard Bash shebang because
  users pipe it to sh. Use case and portable commands there; other scripts use
  Bash 5. Never require Go, Git, Docker, sudo, or qvOS just to open the TUI.
- Download and verify the complete payload before executing anything. Reopen
  `/dev/tty` for the TUI so piped script input cannot swallow keyboard input.
  Use a private temporary directory and remove it after the TUI exits.
- Build fetches the official OS branch only after the normal TUI confirmation,
  verifies its source digest against the public binary, then delegates once to
  `release/iso/build`. Keep the checkout alive through builder cleanup. Docker
  and Git are Build prerequisites; never auto-install or elevate them.
- An absent verified ISO is truthful unavailability, never a guessed GitHub
  release. Add a release only with the user-confirmed URL and SHA-256.
- Run bootstrap/payload tampering and PTY interaction tests, TUI tests, shell
  syntax and ShellCheck, Worker type checking, local runtime HTTP checks, and
  cf deploy --dry-run before deployment. Then verify HTTPS on the custom domain
  and run the literal curl-to-sh entrypoint in a PTY. Do not start an ISO build
  merely to smoke-test the launcher.
