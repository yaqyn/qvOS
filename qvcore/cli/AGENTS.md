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
Every retained command domain is now promoted: no `omarchy-*` adapter may carry
command metadata or implementation. Compatibility adapters remain thin direct
ABI routes until their callers can be retired.

`qvcore/cli/command-{missing,present}` owns command availability checks. Always
terminate `command -v` option parsing with `--` and preserve empty-set semantics:
every command is present and no command is missing. The old hidden terminal-CWD
helper is retired; `qvcore/desktop/context/qvos-active-location` is the singular
tested desktop-context resolver.

`qvcore/cli/{benchmark,metadata}` owns developer-facing CLI introspection.
Benchmark only static native `qv` surfaces, bound repeats before arithmetic,
and never depend on user configuration or execute a mutation. Metadata help and
JSON describe the current `qv:*` schema and native filename-derived routes;
the Omarchy frontend translates the shared catalog only at its compatibility
boundary. Public `qv-dev-*` adapters carry metadata and exact
`omarchy-dev-*` names are metadata-free compatibility only.

`qv update` must resolve only to `qv-update`, which delegates to the
guarded qvOS update owner. Never expose the inherited raw updater or its
implementation subcommands as native `qv update` routes. Do not run an update
or package upgrade while testing CLI dispatch; use help, metadata checks, and
the update owner's `--check` mode only when the live checkout is in scope.

List every promoted inherited CLI path in `native-paths`, sorted and unique.
Run `qvcore/cli/check`, both CLI suites, the product and upstream-overlay
guards, Bash syntax and ShellCheck for changed shell, then the full qvOS suite.
