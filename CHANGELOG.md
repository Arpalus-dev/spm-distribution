# Changelog

All notable changes to ArpalusSDK are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

_Changes that have not yet been released will be listed here._

## [2.1.8] — 2026-07-23

### Added
- **Scan-expiry window.** Scans that age past the project's expiry window (backend-configured, default 8h from session start) are retired instead of uploaded. The session becomes terminally `.failed` with `UploadFailureInfo.causeCode == "session.expired"`, its local data is deleted, and `retryUpload(sessionId:)` refuses it with the new `ArpalusError.session(.expired)` (`code == "session.expired"`). `listActiveSessions()` sweeps expired sessions before returning, so the list never shows a live-looking `"pending"` for a scan that can no longer upload.
- **`UploadFailureInfo.isExpired`** — `true` when a scan can no longer be uploaded because time ran out: either the scan-expiry window elapsed (`session.expired`) or its one-time upload link expired (`upload.urlExpired`). Render these as **"Expired"** rather than a generic failure, hide the retry affordance, and suggest re-scanning.
- **`AuthResponse.minAppVersion`** — the minimum host-app version the backend allows. Purely informational: the SDK never enforces it and carries it through like `user.role`, so hosts that want a version gate can implement one. `nil`/empty means "no gate".
- **Per-image compass heading.** Saved frames now record the heading of the camera's optical axis in their image metadata (`compass.heading` in degrees clockwise from north, `compass.headingAccuracy`, `compass.headingReference`). Heading is `-1` when no north reference is available. No API change — this improves the data uploaded for backend processing.
- **Person flagging on saved frames** is now driven by the project config, and each saved image records a `person` flag in its metadata.

### Changed
- **`endAndUploadSession(sessionId:completion:)` is now idempotent.** Calling it again for a session that was already ended — `pending`, `uploading`, or `uploaded` — reports success again instead of failing with `session.notActive`. `session.notActive` is now returned only when a previous upload failed terminally (use `retryUpload(sessionId:)`).
- **Dead upload links are detected earlier and more broadly.** The uploader probes the resumable upload session's status before sending: an upload the server already committed is healed and marked uploaded, and a `410 Gone` resumable session now also counts as an expired link (`causeCode == "upload.urlExpired"`) alongside `401`/`403`, so a dead URL fails fast instead of burning retries.

### Fixed
- **Memory leak on repeated scans** — the AR scene view and its session delegate are now released when the scan view controller goes away.
- **Model download crash/failure under concurrency** — two downloads of the same model no longer race when moving the file into the cache.
- **A session that already reached `.uploaded` can no longer be resurrected** by a late or duplicate failure callback (which previously re-queued an upload whose local files were gone, failing forever). `.uploaded` is also persisted before the session's files are deleted, so an interruption mid-cleanup can't lose the record.
- **Cancelled report fetches are no longer reported as errors** (e.g. the app backgrounded mid-poll), and a failed report payload decodes instead of throwing.
- **`min_version` is no longer cached across a token refresh**, so a changed backend value takes effect.

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

[Unreleased]: https://github.com/Arpalus-dev/spm-distribution/compare/v2.1.8...HEAD
[2.1.8]: https://github.com/Arpalus-dev/spm-distribution/compare/v2.1.7...v2.1.8
[2.1.7]: https://github.com/Arpalus-dev/spm-distribution/compare/v2.1.6...v2.1.7
[2.1.6]: https://github.com/Arpalus-dev/spm-distribution/compare/v2.1.5...v2.1.6
[2.1.5]: https://github.com/Arpalus-dev/spm-distribution/compare/v2.1.3...v2.1.5
[2.1.3]: https://github.com/Arpalus-dev/spm-distribution/compare/v2.1.2...v2.1.3
[2.0.0]: https://github.com/Arpalus-dev/spm-distribution/releases/tag/v2.0.0
