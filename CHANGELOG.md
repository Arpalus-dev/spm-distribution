# Changelog

All notable changes to ArpalusSDK are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

_Changes that have not yet been released will be listed here._

## [2.1.5] — 2026-05-12

### Changed
- **`Arpalus.startSession` now takes a `displayId` parameter** in addition to `aisleId`. `aisleId` is now expected to be the server-unique `Aisle.id` (used internally to resolve the aisle's `cv_category` from the hierarchy); `displayId` is the human-facing `Aisle.displayId` recorded in scan metadata. This fixes a cache-key collision where multiple stores sharing the same display label could resolve to the wrong CV category.
- Scan context is now snapshotted on the session at start, so resuming a session reuses the resolved values instead of re-walking the hierarchy.

### Added
- **`Arpalus.backendEnvironment`** — runtime-settable property to flip between `.production` and `.staging`. Persists in `UserDefaults`. Defaults to `.production` in Release builds, `.staging` in Debug. Host apps can surface this as a developer toggle; the next network request picks up the new value with no SDK restart.

### Fixed
- AM/PM marker was being dropped from `realogramFormatter` on devices with 24-Hour Time enabled. Now pinned to `en_US_POSIX` to match the other date formatters.

### Removed
- The deprecated `getScanViewController(projectName:storeId:aisleId:userData:customOverlay:)` overload. Use `startSession(…)` followed by `getScanViewController(sessionId:…)` instead.

## [2.1.4] — 2026-05-08

_Release notes to be filled in._

## [2.1.3] — 2026-05-07

_Release notes to be filled in._

## [2.1.2] — 2026-04-21

_Release notes to be filled in._

## [2.1.1] — 2026-03-11

_Release notes to be filled in._

## [2.1.0] — 2026-03-03

_Release notes to be filled in._

## [2.0.0] — 2026-02-16

_Initial 2.x release._

## Earlier Versions

Pre-2.0 releases (`v0.2.0` through `v0.3.1`) are available as Git tags. Detailed notes were not maintained for these versions.

[Unreleased]: https://github.com/Arpalus-dev/spm-distribution/compare/v2.1.5...HEAD
[2.1.5]: https://github.com/Arpalus-dev/spm-distribution/compare/v2.1.4...v2.1.5
[2.1.4]: https://github.com/Arpalus-dev/spm-distribution/compare/v2.1.3...v2.1.4
[2.1.3]: https://github.com/Arpalus-dev/spm-distribution/compare/v2.1.2...v2.1.3
[2.1.2]: https://github.com/Arpalus-dev/spm-distribution/compare/v2.1.1...v2.1.2
[2.1.1]: https://github.com/Arpalus-dev/spm-distribution/compare/v2.1.0...v2.1.1
[2.1.0]: https://github.com/Arpalus-dev/spm-distribution/compare/v2.0.0...v2.1.0
[2.0.0]: https://github.com/Arpalus-dev/spm-distribution/releases/tag/v2.0.0
