# Developer convenience wrappers around the same commands CI runs
# (.github/workflows/ci.yml). There is deliberately no Docker or Linux-toolchain
# path: this is an iOS package, so building and testing it needs macOS + Xcode.
#
# CI discovers the aggregate scheme name at runtime; locally it is stable, so it
# is spelled out here and left overridable.

SCHEME ?= RelevaSDK-Package
SPM_CACHE ?= .spm
RESULT_BUNDLE ?= TestResults.xcresult

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
	xcrun xccov view --report $(RESULT_BUNDLE)

# Not wired into CI: the existing sources still trip some of the opt-in rules in
# .swiftlint.yml, so this reports warnings rather than gating.
lint:
	@if ! command -v swiftlint >/dev/null 2>&1; then \
		echo "swiftlint not found; install it with: brew install swiftlint" >&2; \
		exit 1; \
	fi
	swiftlint lint
