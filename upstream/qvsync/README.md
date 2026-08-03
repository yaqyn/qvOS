# qv git helpers

Tracked qvOS git helper source lives here.

Run `upstream/qvsync/install-qvsync` from this repository to install the local
`git qvsync` alias and a `.git/qvsync` dispatcher that delegates to the tracked
`upstream/qvsync/qvsync` implementation.

`git qvsync` and `git qvsync --audit` fetch upstream and print every commit
after the tracked `reviewed-upstream` baseline, every changed path, and
mechanical qvOS overlap hints. They never merge, cherry-pick, move local
branches, or publish refs. Open maintainer-owned roadmap work is advisory
context only.

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
