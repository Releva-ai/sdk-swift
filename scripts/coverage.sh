#!/usr/bin/env bash
# Prints a per-target/per-file line-coverage summary for a `.xcresult` bundle,
# scoped to this package's own shipped products, and fails if the total is
# below the floor. Both `.github/workflows/ci.yml` and `make test` call this,
# so the number a developer sees locally is the same one that gates CI.
#
# Usage: bash scripts/coverage.sh <path-to.xcresult> [min-line-coverage]
#
# (Invoke with `bash`, not directly - the file isn't marked executable and
# both callers below already run it this way.)
#
# `min-line-coverage` defaults to the figure below (the real CI floor) so a
# local `make test` fails exactly when CI would without either caller having
# to carry its own copy of the number - that duplication is what let the two
# drift out of sync before. An ad-hoc run that wants report-only behaviour can
# still get it by passing an explicit 0.

set -euo pipefail

RESULT_BUNDLE="${1:?usage: bash scripts/coverage.sh <path-to.xcresult> [min-line-coverage]}"
# Set just under the figure this suite actually achieves, so the gate is real
# rather than nominal: the measured figure is 27.74% (2743/9889 lines), and
# 27.0 leaves only enough slack for run-to-run jitter. Do not lower it to
# accommodate a regression - add tests instead. Raise it when coverage
# genuinely climbs.
DEFAULT_MIN_LINE_COVERAGE=27.0
MIN_LINE_COVERAGE="${2:-$DEFAULT_MIN_LINE_COVERAGE}"

# The comparison below hands this straight to awk, which coerces anything
# non-numeric (an empty string, a typo like "none", a stray "27%") to 0 -
# silently disabling the floor instead of failing loudly. Reject it here
# while the value is still known to be user input.
case "$MIN_LINE_COVERAGE" in
  ''|*[!0-9.]*|*.*.*)
    echo "min-line-coverage must be a number, got '$MIN_LINE_COVERAGE'" >&2
    exit 1
    ;;
esac

if [ ! -e "$RESULT_BUNDLE" ]; then
  echo "No result bundle at $RESULT_BUNDLE - did the test step run at all?" >&2
  exit 1
fi

if ! xcrun xccov view --report --json "$RESULT_BUNDLE" > coverage.json; then
  echo "Could not read coverage data from $RESULT_BUNDLE - most likely the test run failed before any test executed, but a bundle written by a different Xcode version or truncated by a killed runner would also land here. See the test step above." >&2
  exit 1
fi

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
