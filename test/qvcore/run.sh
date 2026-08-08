#!/bin/bash
set -euo pipefail

test_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$test_dir/../.." && pwd)"
mapfile -d '' test_files < <(
  find "$repo_root/test" -type f -name '*-test.sh' -print0 | sort -z
)

(( ${#test_files[@]} > 0 )) || {
  echo "No qvOS shell tests found." >&2
  exit 1
}

for test_file in "${test_files[@]}"; do
  printf '\n==> %s\n' "${test_file#"$repo_root/"}"
  env -u QVOS_PATH -u OMARCHY_PATH bash "$test_file"
done

printf '\nAll %d shell test files passed.\n' "${#test_files[@]}"
