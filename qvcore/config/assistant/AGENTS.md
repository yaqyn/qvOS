# qvOS Assistant Integration Workflow

Read this file completely when changing the installed qvOS agent skill, Pi
theme integration, or their migration and reconciliation lifecycle.

`qvos/SKILL.md` is the singular end-user customization skill. Its name and
examples use qvOS and native `qv` commands. It may mention
the compatible Omarchy theme format, but native theme state lives only under
`~/.config/qvos`; never restore an Omarchy product skill, state path, or
user-facing Omarchy command.

`install` preflights every assistant directory and managed target before
mutation, installs exact `qvos` skill links, and copies the qvOS Pi theme owner
atomically. Replace Pi output only when its hash is listed in
`pi-managed-hashes`. Fail before publication on modified, linked, foreign, or
ambiguous native state. Historical Omarchy skill and Pi convergence is retired;
the native owner never reads or mutates those external names.

Desktop reconciliation owns fresh install and update application. Keep the
installer config leaves and the completed numeric migration retired.

Run `check`, the skill validator, Bash syntax, ShellCheck, the assistant,
installer, config, reminder, security, product, and upstream-boundary tests,
then the full qvOS suite. After live alignment, run `install`, verify every
native link and Pi payload, and prove unrelated skills or extensions are
unchanged.
