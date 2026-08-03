# qvOS Command Interface Workflow

Read this file completely when changing the `qv` command, command discovery,
route metadata, compatibility dispatch, or user-facing command help.

`qvcore/cli/qv` is the single command-discovery and dispatch engine. `bin/qv`
is the primary qvOS entry point; `bin/omarchy` is a thin compatibility adapter
for inherited commands and upstream tooling. Both adapters must invoke the same
engine and command directory without duplicating route behavior.

The inherited `omarchy-*` binary namespace and `# omarchy:*` metadata are a
temporary upstream ABI, not qvOS product identity. Native `qv` output, routes,
examples, errors, and suggestions must use `qv`. Keep compatibility output on
the `omarchy` entry point so existing scripts remain truthful.

`qv update` must resolve only to `omarchy-qvos-update`, which delegates to the
guarded qvOS update owner. Never expose the inherited raw updater or its
implementation subcommands as native `qv update` routes. Do not run an update
or package upgrade while testing CLI dispatch; use help, metadata checks, and
the update owner's `--check` mode only when the live checkout is in scope.

List every promoted inherited CLI path in `native-paths`, sorted and unique.
Run `qvcore/cli/check`, both CLI suites, the product and upstream-overlay
guards, Bash syntax and ShellCheck for changed shell, then the full qvOS suite.
