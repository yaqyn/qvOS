#!/bin/bash
set -euo pipefail
export LC_ALL=C

test_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$test_dir/../.." && pwd)"
canonical_repo_root=$(readlink -e -- "$repo_root")
installed_source_root=$(
  readlink -e -- "$HOME/.local/share/qvos" 2>/dev/null || true
)
installed_shallow_source=0
if [[ -n $installed_source_root &&
  $canonical_repo_root == "$installed_source_root" ]] &&
  [[ $(git -C "$repo_root" rev-parse --is-shallow-repository) == "true" ]] &&
  ! git -C "$repo_root" show-ref --verify --quiet \
    refs/remotes/upstream/master &&
  ! git -C "$repo_root" show-ref --verify --quiet \
    refs/remotes/origin/master; then
  installed_shallow_source=1
fi
mapfile -d '' test_files < <(
  find "$repo_root/test" -type f -name '*-test.sh' -print0 | sort -z
)

(( ${#test_files[@]} > 0 )) || {
  echo "No qvOS shell tests found." >&2
  exit 1
}

executed_count=0
skipped_count=0
for test_file in "${test_files[@]}"; do
  printf '\n==> %s\n' "${test_file#"$repo_root/"}"
  if ((installed_shallow_source)) &&
    [[ $test_file == "$repo_root/test/qvcore/qvos-upstream-overlay-test.sh" ]]; then
    printf 'skip - development-only upstream parity input is not embedded in installed qvOS\n'
    ((skipped_count += 1))
    continue
  fi
  env -u QVOS_PATH -u OMARCHY_PATH bash "$test_file"
  ((executed_count += 1))
done

printf '\nAll %d applicable shell test files passed.\n' "$executed_count"
if ((skipped_count)); then
  printf '%d development-only shell test file was explicitly skipped.\n' \
    "$skipped_count"
fi
