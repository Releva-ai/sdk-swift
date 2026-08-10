#!/usr/bin/env bash
# Prints a per-target/per-file line-coverage summary for a `.xcresult` bundle,
# scoped to this package's own shipped products, and fails if the total is
# below the floor. Both `.github/workflows/ci.yml` and `make test` call this,
# so the number a developer sees locally is the same one that gates CI.
#
# Usage: scripts/coverage.sh <path-to.xcresult> [min-line-coverage]
#
# `min-line-coverage` defaults to 0 (report only, no gate) so ad-hoc local
# runs against an arbitrary bundle don't fail by surprise; CI and `make test`
# both pass the real floor explicitly.

set -euo pipefail

RESULT_BUNDLE="${1:?usage: scripts/coverage.sh <path-to.xcresult> [min-line-coverage]}"
MIN_LINE_COVERAGE="${2:-0}"

if [ ! -e "$RESULT_BUNDLE" ]; then
  echo "No result bundle at $RESULT_BUNDLE - did the test step run at all?" >&2
  exit 1
fi

xcrun xccov view --report --json "$RESULT_BUNDLE" > coverage.json

# -enableCodeCoverage instruments the whole build, so the raw report also
# lists the Firebase dependency's targets. Narrow it to this package's own
# products before printing or summing anything.
jq '[.targets[]
     | select((.name | startswith("RelevaSDK")
               or startswith("RelevaNotificationExtension"))
              and (.name | test("Tests") | not))]' \
  coverage.json > coverage-shipped.json

# Per-target, then per-file within each target, largest files first so the
# biggest untested areas are visible at the top of each block.
jq -r '
  .[]
  | "\(.name): \(.coveredLines)/\(.executableLines) lines",
    (.files | sort_by(-.executableLines) | .[]
      | "    \(.name): \(.coveredLines)/\(.executableLines) lines")
' coverage-shipped.json

# `add` on an empty array yields null, which would break the arithmetic
# below, so the empty case is spelled out rather than coalesced.
covered=$(jq '[.[].coveredLines]
  | if length == 0 then 0 else add end' coverage-shipped.json)
executable=$(jq '[.[].executableLines]
  | if length == 0 then 0 else add end' coverage-shipped.json)
if [ "$executable" -eq 0 ]; then
  echo "No shipped target reported executable lines. Targets in the report:" >&2
  jq -r '.targets[].name' coverage.json >&2
  exit 1
fi

percent=$(awk -v c="$covered" -v e="$executable" 'BEGIN { printf "%.2f", 100 * c / e }')
echo "Line coverage: ${percent}% (${covered}/${executable} lines), floor ${MIN_LINE_COVERAGE}%"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  echo "Line coverage: **${percent}%** (${covered}/${executable} lines), floor ${MIN_LINE_COVERAGE}%" \
    >> "$GITHUB_STEP_SUMMARY"
fi

awk -v p="$percent" -v min="$MIN_LINE_COVERAGE" 'BEGIN {
  if (p + 0 < min + 0) {
    printf "Line coverage %s%% is below the %s%% floor\n", p, min > "/dev/stderr"
    exit 1
  }
}'
