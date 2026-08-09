# qv git helpers

Tracked qvOS git helper source lives here.

Run `upstream/qvsync/install-qvsync` from this repository to install the local
`git qvsync` alias and a `.git/qvsync` dispatcher that delegates to the tracked
`upstream/qvsync/qvsync` implementation.

`git qvsync` and `git qvsync --audit` audit two independent read-only sources:

- Omarchy `master`, after the tracked `reviewed-upstream` baseline
- Omarchy ISO `quattro`, after the tracked `reviewed-iso-upstream` baseline

The command fetches both, then prints every commit, changed path, and mechanical
qvOS overlap hint for each range. It never merges, cherry-picks, moves local
branches, makes either upstream executable product input, or publishes refs.
Open maintainer-owned roadmap work is advisory context only.

After porting selected capabilities into native qvOS owners, create
`upstream-reviews/<target-sha>.psv` with these exact comment headers:

```text
# base=<previous-reviewed-sha>
# target=<target-sha>
# commit|decision|owner|summary|verification
```

Add one five-field row for every upstream commit. Supported decisions are
`adopt`, `combine`, `retire-qvos`, `preserve`, and `no-impact`. Then run
`git qvsync --record-reviewed-upstream <target-sha>`. The command validates the
complete ledger and advances only the tracked baseline file. Commit the
ledger, baseline, and verified qvOS adaptations as one logical unit.

Omarchy ISO reviews use the same schema under
`iso-upstream-reviews/<target-sha>.psv`, with `reviewed-iso-upstream` as their
base. After independently porting and verifying selected fixes in
`release/iso/`, run:

```text
git qvsync --record-reviewed-iso-upstream <target-sha>
```

The installer resolves the checkout containing its own tracked source, then
converges `upstream` and `upstream-iso` to their official fetch URLs with both
push URLs set to `DISABLED`. Their fetched objects and remote-tracking refs are
audit evidence only; the native ISO build never reads them.
