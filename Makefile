# Developer convenience wrappers around the same commands CI runs
# (.github/workflows/ci.yml). There is deliberately no Docker or Linux-toolchain
# path: this is an iOS package, so building and testing it needs macOS + Xcode.
#
# CI discovers the aggregate scheme name at runtime; locally it is stable, so it
# is spelled out here and left overridable.

SCHEME ?= RelevaSDK-Package
SPM_CACHE ?= .spm
RESULT_BUNDLE ?= TestResults.xcresult
# No default here on purpose: scripts/coverage.sh carries the one copy of the
# real floor, so this file and ci.yml can't drift out of sync with each other
# again. Set MIN_LINE_COVERAGE=<n> on the `make` invocation to override it for
# an ad-hoc local run.
MIN_LINE_COVERAGE ?=

.PHONY: all build test lint require-macos

all: build test

require-macos:
	@if [ "$$(uname -s)" != "Darwin" ]; then \
		echo "iOS builds require macOS with Xcode; CI runs these on macos-latest" >&2; \
		exit 1; \
	fi

build: require-macos
	xcodebuild build \
	  -scheme $(SCHEME) \
	  -destination 'generic/platform=iOS' \
	  -clonedSourcePackagesDirPath $(SPM_CACHE) \
	  CODE_SIGNING_ALLOWED=NO

# Picks any available iPhone simulator. CI is stricter (it takes the newest
# runtime) because it has to be reproducible; locally, whatever is installed
# will do.
#
# The coverage report still runs even if `xcodebuild test` fails, matching
# ci.yml's "Report code coverage" step - a failed test run is exactly when
# the bundle's per-test detail is worth having, and skipping the report here
# would make `make test` diverge from what CI does on failure. The target
# still exits non-zero on a test failure even if coverage passed.
test: require-macos
	@set -eu; \
	if ! command -v jq >/dev/null 2>&1; then \
	  echo "jq is needed to pick a simulator; install it with: brew install jq" >&2; \
	  exit 1; \
	fi; \
	udid=$$(xcrun simctl list devices available --json \
	  | jq -r 'first(.devices | to_entries[] | select(.key | contains("SimRuntime.iOS-")) | .value[] | select(.name | startswith("iPhone")) | .udid)'); \
	if [ -z "$$udid" ]; then \
	  echo "No iOS simulator available; add one via Xcode > Settings > Platforms" >&2; \
	  exit 1; \
	fi; \
	rm -rf $(RESULT_BUNDLE); \
	set +e; \
	xcodebuild test \
	  -scheme $(SCHEME) \
	  -destination "platform=iOS Simulator,id=$$udid" \
	  -clonedSourcePackagesDirPath $(SPM_CACHE) \
	  -enableCodeCoverage YES \
	  -resultBundlePath $(RESULT_BUNDLE) \
	  CODE_SIGNING_ALLOWED=NO; \
	test_status=$$?; \
	bash scripts/coverage.sh $(RESULT_BUNDLE) $(MIN_LINE_COVERAGE); \
	coverage_status=$$?; \
	if [ "$$test_status" -ne 0 ]; then exit "$$test_status"; fi; \
	exit "$$coverage_status"

# Not wired into CI: the existing sources violate opt-in rules that .swiftlint.yml
# switches on (implicit_return, for one), so this reports rather than gates.
lint:
	@if ! command -v swiftlint >/dev/null 2>&1; then \
		echo "swiftlint not found; install it with: brew install swiftlint" >&2; \
		exit 1; \
	fi
	swiftlint lint
