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

## [2.1.3] — 2026-05-07

### Fixed
- Restored custom overlay functionality (regression in 2.1.2).
- Crash during AR hit testing.
- Date formatters now use `en_US_POSIX` locale so AM/PM markers are not dropped on devices configured for 24-Hour Time.

## [2.1.2] — 2026-04-21

### Added
- `@_spi(Reports)` API surface for opt-in access to realogram report data.
- Support for plan and report data alongside scans (new `PlanInfo` model on `Aisle`).
- Sentry crash reporting filters exception frames before sending events.
- Hierarchy responses now track `location_id` and `display_id`.

### Fixed
- Background task crash.
- Race crash in `SessionManager` caused by `@Published` dictionary access from off-main threads.
- Public API kept `nonisolated` so consumers aren't broken under Swift 6 strict concurrency.
- Several detection-pipeline, depth-map, and FPS-counter crashes.
- Stale cache no longer leaks across project switches.
- `uploadInfo` is now updated on the main thread only.
- Offline localization fallback.

### Internal
- Added NOTICES (third-party licenses) and Postman collection alongside the SDK.

## [2.1.1] — 2026-03-11

### Fixed
- Crash reporting is no longer started when the host app is running under a debugger.

## [2.1.0] — 2026-03-03

### Added
- Crash reporting service.
- Analytics service.
- Localization infrastructure with Hebrew translations.
- GPS coordinate parsing for store metadata (`Store.gpsLat` / `Store.gpsLong`).
- New calibration hint animation.
- Session filtering by user ID.

### Fixed
- Custom overlay is now invoked on the main thread.
- Network reachability handling at SDK init (uses `SCNetworkReachability` for the first network state).
- Invalid email format error handling on login.

## [2.0.0] — 2026-02-16

Initial 2.x release. Major rewrite covering:
- Unified authentication (access key + email/password) with offline mode.
- New session management API: `startSession` / `getScanViewController(sessionId:)` / `endAndUploadSession` / `cancelSession` / `listActiveSessions`.
- Resumable background uploads with `getUploadInfo()` Combine publisher.

[Unreleased]: https://github.com/Arpalus-dev/spm-distribution/compare/v2.1.5...HEAD
[2.1.5]: https://github.com/Arpalus-dev/spm-distribution/compare/v2.1.3...v2.1.5
[2.1.3]: https://github.com/Arpalus-dev/spm-distribution/compare/v2.1.2...v2.1.3
[2.1.2]: https://github.com/Arpalus-dev/spm-distribution/compare/v2.1.1...v2.1.2
[2.1.1]: https://github.com/Arpalus-dev/spm-distribution/compare/v2.1.0...v2.1.1
[2.1.0]: https://github.com/Arpalus-dev/spm-distribution/compare/v2.0.0...v2.1.0
[2.0.0]: https://github.com/Arpalus-dev/spm-distribution/releases/tag/v2.0.0
