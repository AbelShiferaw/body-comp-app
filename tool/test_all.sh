#!/usr/bin/env bash
# Runs unit and widget tests in every workspace package. Integration tests
# (tag: integration) are skipped here; see CLAUDE.md for how to run them.
# Usage: tool/test_all.sh [extra flutter test args, e.g. --coverage]
set -euo pipefail
cd "$(dirname "$0")/.."

failed=()
for dir in packages/*/ app/; do
  [ -d "$dir/test" ] || continue
  echo "::group::flutter test $dir"
  if ! (cd "$dir" && flutter test "$@"); then failed+=("$dir"); fi
  echo "::endgroup::"
done

if [ ${#failed[@]} -gt 0 ]; then
  echo "Tests failed in: ${failed[*]}" >&2
  exit 1
fi
echo "All package tests passed."
