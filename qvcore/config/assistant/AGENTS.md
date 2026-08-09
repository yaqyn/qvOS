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
`pi-managed-hashes`. Remove old `omarchy` skill links and the old Pi filename
only when they exactly match a reviewed generated predecessor. Fail before
publication on modified, linked, foreign, or ambiguous state so two theme
extensions never run together.

Desktop reconciliation owns fresh install and update application. Keep the
installer config leaves retired and use one numeric migration for installations
that predate this owner.

Run `check`, the skill validator, Bash syntax, ShellCheck, the assistant,
installer, config, reminder, security, product, and upstream-boundary tests,
then the full qvOS suite. After live alignment, run `install`, verify every
native link and Pi payload, and prove exact old targets are absent without
changing unrelated skills or extensions.
