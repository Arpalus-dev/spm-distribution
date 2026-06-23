# Changelog

All notable changes to ArpalusSDK are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

_Changes that have not yet been released will be listed here._

## [2.1.7] — 2026-06-23

### Added
- **Expired upload links are now a distinct, non-retryable failure.** A resumable upload URL is only valid for a limited window (~8h); once it lapses the resumable `PUT` is rejected (`401`/`403`) and the upload fails terminally with `UploadFailureInfo.causeCode == "upload.urlExpired"`. Surface this as a separate "Expired" status — distinct from an ordinary retryable failure — so the user knows a fresh `retryUpload(sessionId:)` (which re-zips and fetches a new URL) is required.

### Fixed
- **Resumable upload could get stuck in a `409 Conflict` loop** after a prior `4xx` on the `PUT`. The uploader now reconciles against the server's committed byte offset (or restarts the upload) instead of replaying the same stale request.
- **Reuse the persisted resumable upload URL across retries** instead of re-requesting one on every attempt; an expired URL is marked stale and re-fetched on the next try rather than driving the `409` loop.
- **`SIGSEGV` in `BackgroundUploadManager`** — concurrent mutation of upload-task state is now serialized behind a lock.
- **Zip failures are classified by actual free space** — a genuine out-of-space condition is reported as a terminal storage failure, with more granular zip error details.

## [2.1.6] — 2026-06-18

### Added
- **Session restore & logout** — `Arpalus.restoreSession(completion:)` restores a previously authenticated session on launch (refreshing tokens when online), and `Arpalus.logout(completion:)` clears cached auth state. Cached active sessions survive a logout for later upload.
- **`Arpalus.onSessionExpired`** — an `AnyPublisher<Void, Never>` that fires when the silent token refresh fails because the refresh token is no longer valid. Observe it to route the user to sign-in; the SDK stays logged in so unfinished sessions can still upload.
- **Manual upload retry** — `Arpalus.retryUpload(sessionId:completion:)`. Failed uploads are no longer retried automatically; call this to give the user an explicit "retry" action (clears the recorded failure, resets the attempt counter, and restarts the upload if the network is available).
- **Scan event stream** — `ScanViewController.scanEvents` (an `AsyncStream<ScanEvent>`) and `ScanViewController.scanEventsPublisher` (a Combine publisher) surface the scanner lifecycle: state changes, calibration progress/failure/completion, warnings, modals, image/scan counts, AR-tracking loss & restore, `scanError(ScanError)`, and `productsDetected` (detections written to the scan's `ScanInfo.json`). New public types: `ScanEvent`, `ScanError`, `CalibrationFailureReason`, `CameraUnavailableReason`, `ARTrackingLossReason`, `WarningClearScope`.
- **Per-category detector flow (models_v2)** — for projects shipping non-generic per-category detectors:
  - `Arpalus.hasDownloadableModels` / `Arpalus.requiredModels()` (returns a `RequiredModelsManifest`) to inspect the required model set and cache state after `initialize`.
  - `Arpalus.downloadRequiredModels(…)` and `Arpalus.getModelDownloadViewController(…)` for a manual model-download flow.
  - `Arpalus.availableDetectors(forAisleCvCategory:)` (returns `[DetectorOption]`), `Arpalus.prepareDetectors(…)`, and `Arpalus.getScanViewController(sessionId:detectorId:customOverlay:completion:)` to present a detector picker and pin the chosen detector for a scan.
- **`Arpalus.handleBackgroundURLSessionEvents(identifier:completion:) -> Bool`** — forward background `URLSession` relaunch events from your `AppDelegate` so resumable uploads can finish while the app is suspended. Returns `true` only for the SDK's own background session, so apps with their own background sessions can still handle theirs.
- **`Arpalus.cancelSession(sessionId:completion:)`** — a completion-based variant that reports a `session.notFound` failure.

### Changed
- **Completion handlers now deliver a structured `ArpalusError` instead of a bare `Error`** (source-breaking). `ArpalusError` exposes a stable `code` and a human-readable `message`, with nested failure categories (`auth`, `configuration`, `network`, `session`, `device`). Affects `authenticate`, `login`, `initialize`, `startSession`, `endAndUploadSession`, `getScanViewController`, and the new APIs above.
- **`startSession` now surfaces auth-expiry on an expired/cleared session** (so the host's re-login recovery fires) instead of a generic, unrecoverable configuration error.
- **Upload failures are now terminal** and not retried automatically — use `retryUpload(sessionId:)`. `UploadState` gains a `.failed` case, and `ActiveSession` gains `scanIds` and an optional `uploadFailure`.

### Deprecated
- `Arpalus.cancelSession(sessionId:)` — use `cancelSession(sessionId:completion:)` to observe `session.notFound`.

### Fixed
- Handle `409 Conflict` from the resumable upload endpoint.
- Rebuild stale session zips and detect zip write failures instead of reusing or shipping a truncated archive (silent data loss).
- Sessions with zero scans are dropped instead of uploaded.
- Low storage: warn the user and surface a zip out-of-space condition as a terminal storage failure.
- Crash fixes around the active-sessions list and `getUploadInfo()`.
- Auth hardening: only treat `401` on token refresh as expiry, keep offline state when clearing, and apply the latest configuration on offline load.

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

## [2.0.0] — 2026-02-16

Initial 2.x release. Major rewrite covering:
- Unified authentication (access key + email/password) with offline mode.
- New session management API: `startSession` / `getScanViewController(sessionId:)` / `endAndUploadSession` / `cancelSession` / `listActiveSessions`.
- Resumable background uploads with `getUploadInfo()` Combine publisher.

[Unreleased]: https://github.com/Arpalus-dev/spm-distribution/compare/v2.1.7...HEAD
[2.1.7]: https://github.com/Arpalus-dev/spm-distribution/compare/v2.1.6...v2.1.7
[2.1.6]: https://github.com/Arpalus-dev/spm-distribution/compare/v2.1.5...v2.1.6
[2.1.5]: https://github.com/Arpalus-dev/spm-distribution/compare/v2.1.3...v2.1.5
[2.1.3]: https://github.com/Arpalus-dev/spm-distribution/compare/v2.1.2...v2.1.3
[2.0.0]: https://github.com/Arpalus-dev/spm-distribution/releases/tag/v2.0.0
