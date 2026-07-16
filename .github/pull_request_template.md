<!-- Formatting: never write "#<number>" (e.g. #1) anywhere — GitHub auto-links it. Use "1." for numbered lists. -->

## Summary

<!-- What changed and why. -->

## Release checklist

- [ ] Bumped `s.version` in `RelevaSDK.podspec` (patch for fixes, minor for features, major for breaking).
- [ ] Bumped `SDKVersion.current` in `Sources/RelevaSDK/Services/NetworkService.swift` to match — it is sent as `options.client.version` / the `User-Agent` on every push, so it must move with each behavior change. (Keep it equal to the podspec version.)
- [ ] Added a matching entry at the top of `CHANGELOG.md` (Keep a Changelog format; mark breaking changes with a migration note).
- [ ] Tests added/updated and `swift test` passes.

## Breaking changes

<!-- List each breaking change and its migration, or write "None". -->
