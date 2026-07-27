# qv git helpers

Tracked qvOS git helper source lives here.

Run `qv/git/install-qvsync` from this repository to install the local `git qvsync` alias and point `.git/qvsync` at the tracked `qv/git/qvsync` implementation.

`git qvsync --audit` fetches current refs and prints every upstream commit,
changed path, and mechanical qvOS overlap hint without merging or publishing.
It also lists open maintainer-owned roadmap work as advisory context so Codex
can avoid deepening architecture that upstream is already replacing.
When `origin/OS` does not contain the fetched upstream target, normal qvsync
refuses until Codex reviews that exact change set and retries with
`git qvsync --reviewed-upstream <full-sha>`.
