# qvOS Command Interface Workflow

Read this file completely when changing the `qv` command, command discovery,
route metadata, compatibility dispatch, or user-facing command help.

`qvcore/cli/qv` is the single command-discovery and dispatch engine. `bin/qv`
is the primary qvOS entry point; `bin/omarchy` is a thin compatibility adapter
for inherited commands and upstream tooling. Both adapters invoke the same
engine and command directory without duplicating route behavior.

Promoted commands use a `qv-*` route with `# qv:*` metadata. The engine prefers
that native route for both frontends and ignores its matching `omarchy-*` file
during discovery; the latter is a metadata-free direct-command compatibility
adapter only. Unpromoted `omarchy-*` implementations and metadata remain an
upstream ABI until their complete domain moves. Never keep two implementations
or two active metadata records for the same route. Native `qv` output, routes,
examples, errors, and suggestions use `qv`; the compatibility frontend rewrites
the same catalog to `omarchy` without changing its owner.

`qv update` must resolve only to `omarchy-qvos-update`, which delegates to the
guarded qvOS update owner. Never expose the inherited raw updater or its
implementation subcommands as native `qv update` routes. Do not run an update
or package upgrade while testing CLI dispatch; use help, metadata checks, and
the update owner's `--check` mode only when the live checkout is in scope.

List every promoted inherited CLI path in `native-paths`, sorted and unique.
Run `qvcore/cli/check`, both CLI suites, the product and upstream-overlay
guards, Bash syntax and ShellCheck for changed shell, then the full qvOS suite.
