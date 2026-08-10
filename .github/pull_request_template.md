<!-- Formatting: never write "#<number>" (e.g. #1) anywhere — GitHub auto-links it. Use "1." for numbered lists. -->

## Summary

<!-- What changed and why. -->

## Release checklist

- [ ] Bumped `SDKVersion.current` in `Sources/RelevaSDK/Services/NetworkService.swift` (patch for fixes, minor for features, major for breaking) — it is sent as `options.client.version` / the `User-Agent` on every push, so it must move with each behavior change. Keep it equal to the `vX.Y.Z` release tag the maintainer pushes after merge; SPM resolves consumers by that tag.
- [ ] Added a matching entry at the top of `CHANGELOG.md` (Keep a Changelog format; mark breaking changes with a migration note).
- [ ] Tests added/updated and the iOS CI workflow is green. (The package is iOS-only, so a host `swift test` cannot build it; CI runs `xcodebuild test` on a simulator.)

## Breaking changes

<!-- List each breaking change and its migration, or write "None". -->
