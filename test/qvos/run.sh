#!/bin/bash
set -euo pipefail

test_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$test_dir/../.." && pwd)"
test_files=(
  "$repo_root/test"/*-test.sh
  "$test_dir"/*-test.sh
)

for test_file in "${test_files[@]}"; do
  printf '\n==> %s\n' "${test_file#"$repo_root/"}"
  bash "$test_file"
done

printf '\nAll %d shell test files passed.\n' "${#test_files[@]}"
