# Developer convenience wrappers around the same commands CI runs
# (.github/workflows/ci.yml). There is deliberately no Docker or Linux-toolchain
# path: this is an iOS package, so building and testing it needs macOS + Xcode.
#
# CI discovers the aggregate scheme name at runtime; locally it is stable, so it
# is spelled out here and left overridable.

SCHEME ?= RelevaSDK-Package
SPM_CACHE ?= .spm
RESULT_BUNDLE ?= TestResults.xcresult
# Must match the MIN_LINE_COVERAGE set on the "Report code coverage" step in
# .github/workflows/ci.yml, so a local `make test` fails exactly when CI would.
MIN_LINE_COVERAGE ?= 15.0

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
	xcodebuild test \
	  -scheme $(SCHEME) \
	  -destination "platform=iOS Simulator,id=$$udid" \
	  -clonedSourcePackagesDirPath $(SPM_CACHE) \
	  -enableCodeCoverage YES \
	  -resultBundlePath $(RESULT_BUNDLE) \
	  CODE_SIGNING_ALLOWED=NO
	bash scripts/coverage.sh $(RESULT_BUNDLE) $(MIN_LINE_COVERAGE)

# Not wired into CI: the existing sources violate opt-in rules that .swiftlint.yml
# switches on (implicit_return, for one), so this reports rather than gates.
lint:
	@if ! command -v swiftlint >/dev/null 2>&1; then \
		echo "swiftlint not found; install it with: brew install swiftlint" >&2; \
		exit 1; \
	fi
	swiftlint lint
