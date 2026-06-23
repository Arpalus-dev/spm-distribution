# ArpalusSDK — iOS Integration Guide

**Minimum iOS:** 16.6 &nbsp;|&nbsp; **Xcode:** 26+ &nbsp;|&nbsp; **Physical Device Required**

_For questions or access key requests, contact the Arpalus DevOps team._

---

## 1. Overview

**ArpalusSDK** is an iOS framework for real-time, AR-powered shelf scanning and product recognition. It uses ARKit, Vision, and CoreML to detect products on retail shelves via the device camera.

The SDK handles the full scanning pipeline — 3D calibration, image capture, on-device computer vision, session management, and cloud upload — exposing a streamlined API that lets you integrate shelf scanning into your app with minimal effort.

All SDK interaction happens through the static methods on the `Arpalus` enum. There are no singleton instances to manage.

## 2. Prerequisites

- An **Arpalus access key** provided by the Arpalus DevOps team
- Xcode 26 or later
- A physical iOS device running iOS 16.6+
- Camera permission granted by the user

## 3. Required Permissions

Add the following key to your app's `Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>Camera access is required for shelf scanning.</string>
```

The SDK uses ARKit which requires camera access. The system will prompt the user automatically when the scan view is first presented.

## 4. Integration Flow at a Glance

The diagram below shows the five-step integration flow from authentication to upload:

```
┌─────────────────┐
│   authenticate  │  Provide your access key
└────────┬────────┘
         │ Returns: AuthResponse (clientId, projects)
         ▼
┌─────────────────┐
│   initialize    │  Pass clientId + projectId
└────────┬────────┘
         │ Returns: Hierarchy (stores and aisles)
         │ Downloads & compiles ML models (first run)
         ▼
┌─────────────────┐
│  startSession   │  Pass store + aisle identifiers
└────────┬────────┘
         │ Returns: sessionId
         ▼
┌──────────────────────────┐
│  getScanViewController   │  Returns: ScanViewController
└────────┬─────────────────┘
         │ Present in navigation stack
         ▼
┌─────────────────────────┐
│   User performs scans   │  SDK handles AR, CV, capture
└────────┬────────────────┘
         │ onScanFinished / onScanCancelled
         ▼
┌────────────────────────┐
│  endAndUploadSession   │  Finalizes and uploads data
└────────────────────────┘
```

## 5. Step 1 — Authenticate

Authenticate using the access key provided by the Arpalus DevOps team. This must be the first SDK call in your app.

```swift
import ArpalusSDK

Arpalus.authenticate(token: "your-access-key") { result in
    switch result {
    case .success(let authResponse):
        // authResponse.clientId  — your client identifier
        // authResponse.clients   — available clients and projects
    case .failure(let error):
        print("Authentication failed: \(error.localizedDescription)")
    }
}
```

### Method Signature

```swift
public static func authenticate(
    token: String,
    completion: @escaping (Result<AuthResponse, ArpalusError>) -> Void
)
```

| Parameter | Type | Description |
| :--- | :--- | :--- |
| `token` | `String` | The SDK access key provided by the Arpalus DevOps team. |
| `completion` | `Result<AuthResponse, ArpalusError>` | Called on completion with the authentication response or a structured `ArpalusError` (see [§18. Error Handling](#18-error-handling)). |

> **Failure (`ArpalusError`) codes:** `auth.unauthorized`, `auth.offlineCredentialsUnavailable`, `network.*`, `http.*`, `unknown`.

### Restoring a Session & Logging Out

Once a user has authenticated, you don't need to prompt them for the access key on every launch. Call `restoreSession` on startup to re-establish the cached session (refreshing tokens when online, falling back to cached credentials when offline):

```swift
Arpalus.restoreSession { result in
    switch result {
    case .success(let auth):
        // Session restored — SDK is authenticated again.
        break
    case .failure(let error):
        // No valid cached session — route the user to your sign-in screen.
        print("Restore failed: \(error.code)")
    }
}
```

```swift
public static func restoreSession(
    completion: @escaping (Result<AuthResponse, ArpalusError>) -> Void
)
```

> **Failure codes:** `auth.unauthorized`, `auth.offlineCredentialsUnavailable`, `network.*`, `http.*`, `unknown`.

To clear cached authentication state (sign out), call `logout`. Any cached active sessions are **retained** so their data can still upload later:

```swift
public static func logout(completion: (() -> Void)? = nil)
```

### Detecting Session Expiry

If the SDK's silent token refresh fails because the refresh token is no longer valid, the user's session has truly expired. Observe the `onSessionExpired` publisher and route the user back to sign-in. The SDK is **not** logged out automatically, so any unfinished sessions survive for later upload:

```swift
import Combine

Arpalus.onSessionExpired
    .receive(on: DispatchQueue.main)
    .sink { presentSignIn() }
    .store(in: &cancellables)
```

```swift
public static var onSessionExpired: AnyPublisher<Void, Never> { get }
```

> `login(email:password:completion:)` shares the same shape as `authenticate`, returning `Result<AuthResponse, ArpalusError>`. Its failure codes also include `configuration.invalid`.

### AuthResponse

```swift
public struct AuthResponse: Codable, Equatable {
    public let accessToken: String
    public let refreshToken: String
    public let tokenType: String
    public let expiresIn: Int

    // User login only
    public let user: User?

    // Access key / SDK only
    public let clientId: String?
    public let accessKeyId: String?
    public let accessKeyName: String?

    public let clients: [String: Client]?  // Key: client ID
}

public struct User: Codable, Equatable {
    public let role: String
}

public struct Client: Codable, Equatable {
    public let name: String
    public let projects: [Project]
}

public struct Project: Codable, Equatable {
    public let id: String
    public let name: String
}
```

After authentication, extract the `clientId` and select a `projectId` from the available projects:

```swift
let clientId = authResponse.clientId!
let project = authResponse.clients![clientId]!.projects.first!
let projectId = project.id
```

## 6. Step 2 — Initialize the SDK

After successful authentication, initialize the SDK with the chosen client and project. This downloads the project configuration and ML models required for scanning.

```swift
Arpalus.initialize(clientId: clientId, projectId: projectId) { result in
    switch result {
    case .success(let hierarchy):
        // SDK is ready for scanning
        // hierarchy.stores — array of Store objects
    case .failure(let error):
        print("Initialization failed: \(error.localizedDescription)")
    }
}
```

### Method Signature

```swift
public static func initialize(
    clientId: String,
    projectId: String,
    completion: @escaping (Result<Hierarchy, ArpalusError>) -> Void
)
```

| Parameter | Type | Description |
| :--- | :--- | :--- |
| `clientId` | `String` | The client identifier from the `AuthResponse`. |
| `projectId` | `String` | The project identifier selected from the client's projects. |
| `completion` | `Result<Hierarchy, ArpalusError>` | Called with the store/aisle hierarchy or a structured `ArpalusError`. |

### What Happens During Initialization

1. Downloads project configuration (scan settings, thresholds) from the Arpalus server.
2. Downloads CoreML model files if not already cached locally.
3. Compiles CoreML models for the current device (first run only — cached afterward).
4. Returns the `Hierarchy` containing the store and aisle structure.

> **Note:** The first initialization on a device may take longer due to model download and compilation. Subsequent launches use cached models and are significantly faster.

### Hierarchy

```swift
public struct Hierarchy: Codable, Equatable {
    public let projectId: String
    public let projectName: String
    public let stores: [Store]
}

public struct Store: Codable, Equatable {
    public let id: String
    public let name: String
    public let storeId: String
    public let displayLine: String
    public let locationId: String
    public let gpsLat: Double?
    public let gpsLong: Double?
    public let aisles: [Aisle]
}

public struct Aisle: Codable, Equatable {
    public let id: String
    public let name: String
    public let aisleNumber: String?
    public let displayId: String
    public let displayLine: String
    public let cvCategory: String?
    public let plan: PlanInfo?
}

public struct PlanInfo: Codable, Equatable {
    public let version: String
    public let products: [String: Int]
}
```

### Downloading Models for Per-Category Detectors (Optional)

Some projects ship **per-category detectors** (the "models_v2" flow) — a dedicated detector per CV category instead of a single generic model. For these projects you can drive an explicit, user-visible model-download step before scanning. Projects that use only the classic/generic detector don't need any of this; models download silently.

Use `hasDownloadableModels` after `initialize` to branch your UX:

```swift
public static var hasDownloadableModels: Bool { get }
```

When `true`, present the manual download flow and observe `ScanViewController.scanEvents` for `.productsDetected` during scanning (see [§8](#8-step-4--present-the-scan-view-controller)). When `false`, skip the download screen entirely.

Inspect what the active project requires (and what's already cached) via `requiredModels()`:

```swift
public static func requiredModels() -> RequiredModelsManifest?   // nil before initialize succeeds

public struct RequiredModelsManifest: Equatable {
    public struct CategoryGroup: Equatable {
        public let cvCategory: String
        public let detector: ModelDescriptor?
        public let classifiers: [ModelDescriptor]
    }
    public let groups: [CategoryGroup]
    public let modelsNeedingDownload: [ModelDescriptor]   // not yet on disk, deduplicated
    public var totalEstimatedBytes: Int64? { get }        // nil if no model reported a size
    public var isEmpty: Bool { get }
}

public struct ModelDescriptor: Equatable, Hashable {
    public enum Role: String { case detector, classifier }
    public let name: String
    public let url: URL
    public let role: Role
    public let cvCategory: String?
    public let isCached: Bool
    public let estimatedBytes: Int64?
}
```

Trigger the download yourself with `downloadRequiredModels` (safe to call repeatedly — cached models are skipped):

```swift
public static func downloadRequiredModels(
    selectedCvCategories: Set<String>? = nil,   // nil = download everything
    progress: @escaping (ModelDownloadProgress) -> Void,
    completion: @escaping (Result<Void, Error>) -> Void
)

public enum ModelDownloadProgress: Equatable {
    case downloading(currentModel: String, bytesDownloaded: Int64, totalBytes: Int64?, modelIndex: Int, modelCount: Int)
    case unzipping(currentModel: String, modelIndex: Int, modelCount: Int)
    case compiling(currentModel: String, modelIndex: Int, modelCount: Int)
}
```

Or let the SDK present a ready-made progress UI. `getModelDownloadViewController` returns `nil` when there's nothing to download, so you can skip presentation:

```swift
// Must be called on the main thread.
if let downloadVC = Arpalus.getModelDownloadViewController(completion: { /* user tapped Continue */ }) {
    navigationController?.pushViewController(downloadVC, animated: true)
} else {
    // Nothing to download — proceed straight to scanning.
}

public static func getModelDownloadViewController(
    completion: @escaping () -> Void
) -> ModelDownloadViewController?
```

## 7. Step 3 — Start a Scan Session

Before presenting the scan camera, create a session. A session groups one or more individual scans together (e.g., scanning multiple shelf sections in the same aisle).

```swift
Arpalus.startSession(
    projectName: hierarchy.projectName,
    storeId: selectedStore.storeId,
    aisleId: selectedAisle.id,                 // server-unique Aisle.id
    displayId: selectedAisle.displayId,        // human-facing label
    userData: ["operatorId": "user-123"]       // Optional metadata
) { result in
    switch result {
    case .success(let sessionId):
        print("Session started: \(sessionId)")
    case .failure(let error):
        print("Failed to start session: \(error.localizedDescription)")
    }
}
```

### Method Signature

```swift
public static func startSession(
    projectName: String,
    storeId: String,
    aisleId: String,
    displayId: String,
    userData: [String: Any],
    completion: @escaping (Result<String, ArpalusError>) -> Void
)
```

| Parameter | Type | Description |
| :--- | :--- | :--- |
| `projectName` | `String` | The project name from `hierarchy.projectName`. |
| `storeId` | `String` | The store identifier from the selected `Store.storeId`. |
| `aisleId` | `String` | The **server-unique** `Aisle.id` from the selected aisle. Used internally to resolve the aisle's `cv_category` from the hierarchy. |
| `displayId` | `String` | The **human-facing** `Aisle.displayId` (e.g. `"Aisle-4"`). Recorded as `display_id` in the scan metadata that flows downstream. |
| `userData` | `[String: Any]` | Optional free-form metadata attached to session logs. |
| `completion` | `Result<String, ArpalusError>` | Called with the `sessionId` string on success. |

> **Failure codes:** `session.createFailed` (with an underlying cause such as `auth.unauthorized`, `configuration.*`, `storage.writeFailed`, or `resources.insufficientStorage`). If the auth session expired or was cleared, the cause is `auth.unauthorized` — route the user to re-login. Observe [`onSessionExpired`](#restoring-a-session--logging-out) to catch this globally.

> **Why both `aisleId` and `displayId`?** `Aisle.id` is guaranteed unique per project, so the SDK uses it as the cache key when looking up the aisle's CV category. `Aisle.displayId` is the human-readable label that ends up in downstream reports. Passing both removes the ambiguity that occurred when multiple stores happened to share the same `displayId`.

> **`userData`:** This dictionary is embedded in the session's scan logs and uploaded alongside the scan data. Use it to attach any metadata relevant to your workflow. Pass `[:]` if not needed.

## 8. Step 4 — Present the Scan View Controller

Retrieve a `ScanViewController` for the active session and present it in your app's navigation.

```swift
Arpalus.getScanViewController(sessionId: sessionId) { result in
    switch result {
    case .success(let scanViewController):
        scanViewController.setOnScanFinished { scanResult in
            print("Scan finished: \(scanResult.id)")
        }
        scanViewController.setOnScanCancelled { message in
            print("Scan cancelled: \(message)")
        }
        navigationController?.pushViewController(
            scanViewController, animated: true
        )
    case .failure(let error):
        print("Failed: \(error.localizedDescription)")
    }
}
```

### Method Signature

```swift
public static func getScanViewController(
    sessionId: String,
    customOverlay: (() -> ScanOverlay)? = nil,
    completion: @escaping (Result<ScanViewController, ArpalusError>) -> Void
)
```

| Parameter | Type | Description |
| :--- | :--- | :--- |
| `sessionId` | `String` | The session ID returned by `startSession()`. |
| `customOverlay` | `(() -> ScanOverlay)?` | Optional closure providing a custom UI overlay. Pass `nil` for built-in UI. |
| `completion` | `Result<ScanViewController, ArpalusError>` | Called with the configured scan view controller. |

> **Failure codes:** `session.notFound`, `session.notActive`, `scan.viewCreationFailed`, plus the pre-scan `permissions.denied` / `resources.*` checks.

### ScanViewController

```swift
public final class ScanViewController: UIViewController {
    /// Called when a scan finishes successfully.
    public func setOnScanFinished(_ handler: ((ScanResult) -> Void)?)

    /// Called when the user cancels the scan session.
    public func setOnScanCancelled(_ handler: ((String) -> Void)?)

    /// Async stream of user-visible scanner events (see "Observing Scan Events").
    public var scanEvents: AsyncStream<ScanEvent> { get }

    /// Combine equivalent of `scanEvents`.
    public var scanEventsPublisher: AnyPublisher<ScanEvent, Never> { get }
}
```

> **Important:** The `ScanViewController` manages its own AR session, camera feed, and UI. Present it full-screen and dismiss it in response to the `onScanFinished` or `onScanCancelled` callbacks.

### Choosing a Detector (Per-Category Projects)

For projects with per-category detectors, you can let the user pick which detector runs for a scan. List the detectors available for an aisle's CV category (the "General Product" fallback is always appended):

```swift
public static func availableDetectors(forAisleCvCategory cvCategory: String?) -> [DetectorOption]

public struct DetectorOption: Equatable {
    public let id: String           // SDK-internal model name — pass to getScanViewController(detectorId:)
    public let displayName: String  // human label for the picker
    public let cvCategory: String
    public let isGeneric: Bool       // true for the "General Product" fallback
}
```

Optionally pre-download every detector available to the aisle when the user enters a session, so the picker can offer a fast selection:

```swift
public static func prepareDetectors(
    forAisleCvCategory cvCategory: String?,
    progress: ((String) -> Void)? = nil,
    completion: @escaping (Result<Void, Error>) -> Void
)
```

Then present the scan view controller pinned to the chosen detector:

```swift
public static func getScanViewController(
    sessionId: String,
    detectorId: String,                              // DetectorOption.id
    customOverlay: (() -> ScanOverlay)? = nil,
    completion: @escaping (Result<ScanViewController, ArpalusError>) -> Void
)
```

### Observing Scan Events

`ScanViewController` exposes a stream of user-visible events emitted while an individual scan is running — useful for driving a custom overlay or analytics. Consume it as an `AsyncStream` or a Combine publisher:

```swift
Task {
    for await event in scanViewController.scanEvents {
        switch event {
        case .scanStateChanged(let state): updateUI(state)
        case .calibrationProgressChanged(let progress): show(progress)
        case .scanSaved(let scanId, let scanNumber): print("Saved \(scanId) (#\(scanNumber))")
        case .productsDetected(let image, let detections): overlay(detections, on: image)
        case .scanError(let error): handle(error)
        default: break
        }
    }
}
```

```swift
public enum ScanEvent: Equatable {
    case scanStateChanged(ScanState)
    case calibrationProgressChanged(CalibrationProgress)
    case calibrationFailed(reason: CalibrationFailureReason)
    case calibrationCompleted(duration: TimeInterval)
    case warningShown(WarningType)
    case warningsCleared(scope: WarningClearScope)
    case modalShown(ScanModal)
    case imageCountChanged(Int)
    case scanStarted(scanId: String)
    case scanSaved(scanId: String, scanNumber: Int)
    case scanCancelled
    case scanReset
    case scanInterrupted
    case arTrackingRestored
    case scanError(ScanError)
    /// Emitted by the per-category detector flow for each saved image.
    case productsDetected(image: ScanDetectionImage, detections: [ScanDetection])
}
```

The detection payloads mirror what is written to the scan's `ScanInfo.json`. Detection `x`/`y` are the **normalized center** of the bounding box; `width`/`height` are normalized dimensions:

```swift
public struct ScanDetection: Equatable {
    public let id: Int
    public let name: String
    public let categoryName: String
    public let modelName: String
    public let confidence: Double
    public let x: Double          // normalized bounding-box center X
    public let y: Double          // normalized bounding-box center Y
    public let width: Double
    public let height: Double
    public let frameNumber: Int
}

public struct ScanDetectionImage: Equatable {
    public let scanId: String
    public let imageIndex: Int
    public let timestamp: String
    public let width: Int
    public let height: Int
}
```

> `scanEvents` / `scanEventsPublisher` emit on the scanner's internal queue. Use `receive(on:)` (Combine) or hop to the main actor before touching UIKit.

### ScanResult

```swift
public struct ScanResult: Codable, Equatable, Identifiable, Hashable {
    public let id: String       // Session/scan GUID
    public let aisleId: String  // Aisle identifier
    public let storeId: String  // Store identifier
    public let date: Date       // Scan timestamp
}
```

## 9. Step 5 — End Session & Upload

After the user has finished scanning, end the session to finalize and upload the data.

```swift
Arpalus.endAndUploadSession(sessionId: sessionId) { result in
    switch result {
    case .success(let scanResult):
        print("Session ended. Scan ID: \(scanResult.id)")
    case .failure(let error):
        print("Failed to end session: \(error.localizedDescription)")
    }
}
```

### Method Signature

```swift
public static func endAndUploadSession(
    sessionId: String,
    completion: @escaping (Result<ScanResult, ArpalusError>) -> Void
)
```

> **Failure codes:** `session.notFound`, `session.notActive`, `storage.writeFailed`, `resources.insufficientStorage`, `unknown`. Upload *delivery* failures are **not** reported here — observe them via `getUploadInfo()` (see [§10](#10-monitoring-upload-progress)).

This method performs the following:

1. Writes final scan logs to disk.
2. Packages the session data into a zip archive.
3. Initiates background upload to the Arpalus cloud.
4. Returns immediately — the upload continues in the background.

## 10. Monitoring Upload Progress

The SDK provides a single Combine publisher to observe upload status. Subscribe to it to show progress in your UI.

```swift
import Combine

var cancellables = Set<AnyCancellable>()

// Observe upload info (state + per-session progress)
Arpalus.getUploadInfo()
    .receive(on: DispatchQueue.main)
    .sink { info in
        switch info.state {
        case .idle:
            print("No active uploads")
        case .uploading(let progress):
            progressBar.progress = Float(progress) / 100.0
        case .paused(let progress):
            print("Upload paused at \(progress)%")
        case .failed(let failure):
            // A terminal failure that won't retry on its own — offer a manual retry.
            print("Upload failed: \(failure.message) [\(failure.code)]")
            showRetryButton(for: failure.sessionId)
        }

        // Per-session progress
        for (sessionId, progress) in info.sessions {
            print("Session \(sessionId): \(progress)%")
        }

        // Per-session failure details (including ones still being auto-retried)
        for (sessionId, failure) in info.failures {
            print("Session \(sessionId) error: \(failure.message)")
        }
    }
    .store(in: &cancellables)
```

### Publisher Signature

| Method | Publisher Type | Description |
| :--- | :--- | :--- |
| `getUploadInfo()` | `AnyPublisher<UploadInfo, Never>` | Emits an `UploadInfo` value containing the overall upload state and per-session progress. |

### UploadInfo & UploadState

```swift
public enum UploadState: Equatable {
    case idle
    case uploading(progress: Int)      // 0 — 100
    case paused(progress: Int)         // 0 — 100
    case failed(UploadFailureInfo)     // a terminal failure pins this state
}

public struct UploadInfo: Equatable {
    public let state: UploadState
    public let sessions: [String: Int]                 // Per-session progress (0 — 100), keyed by sessionId
    public let failures: [String: UploadFailureInfo]   // Per-session failure details, keyed by sessionId

    public static let idle = UploadInfo(state: .idle, sessions: [:], failures: [:])
}

public struct UploadFailureInfo: Codable, Equatable {
    public let sessionId: String
    public let code: String                  // e.g. "network.error", "http.error"
    public let message: String
    public let recoverySuggestion: String?
    public let underlyingDescription: String?
    public let isRetryable: Bool
    /// `true` when the error was retryable but the SDK stopped after exhausting its retry cap.
    public let attemptsExhausted: Bool
    // Plus the originating cause: causeCode / causeMessage / causeRecoverySuggestion / causeUnderlyingDescription.
}
```

> **Expired upload link (`causeCode == "upload.urlExpired"`).** A resumable upload URL is only valid for a limited window (~8h). Once it lapses, the resumable `PUT` is rejected (`401`/`403`) and the upload becomes a **terminal, non-retryable** failure carrying `causeCode == "upload.urlExpired"`. Treat this as a distinct **"Expired"** status, separate from an ordinary retryable failure — a fresh `retryUpload(sessionId:)` re-zips the session and fetches a new upload URL.

> **Only *terminal* failures pin the `.failed` state.** A session marked `.failed` (a non-retryable error, or one that exhausted the retry cap) won't upload again without user action — call [`retryUpload(sessionId:)`](#11-session-management). Transient failures that the SDK is still auto-retrying don't change `state`; their details still appear in `info.failures`.

## 11. Session Management

The SDK provides methods to manage sessions beyond the basic start/end flow.

### List Active Sessions

```swift
let sessions: [ActiveSession] = Arpalus.listActiveSessions()
for session in sessions {
    print("\(session.sessionId) — \(session.uploadState)")
}
```

### Cancel a Session

Abandons a session and **permanently deletes** all its data from disk. Prefer the completion-based variant so you can observe a `session.notFound` failure:

```swift
Arpalus.cancelSession(sessionId: sessionId) { result in
    // .failure(.session(.notFound)) if the id is unknown
}

public static func cancelSession(
    sessionId: String,
    completion: @escaping (Result<Void, ArpalusError>) -> Void
)
```

> The fire-and-forget `cancelSession(sessionId:)` (no completion) is **deprecated** in 2.1.6 — use the variant above.

### Retry a Failed Upload

A failed upload (surfaced as `UploadState.failed` via `getUploadInfo()`) is **not** retried automatically — neither a non-retryable error nor an exhausted retry cap reschedules it. Give the user an explicit "retry" action: this clears the recorded failure, resets the attempt counter, and starts a fresh upload if the network is available.

```swift
Arpalus.retryUpload(sessionId: sessionId) { result in
    // .failure(.session(.notFound)) if the id is unknown
}

public static func retryUpload(
    sessionId: String,
    completion: @escaping (Result<Void, ArpalusError>) -> Void
)
```

### ActiveSession

```swift
public struct ActiveSession {
    public let sessionId: String
    public let projectName: String
    public let storeId: String
    public let aisleId: String
    public let scanCount: Int
    public let scanIds: [String]                  // identifiers of the scans captured so far
    public let startDate: Date
    public let uploadState: String
    // uploadState: "active", "pending", "uploading", "uploaded", "failed"
    public let uploadFailure: UploadFailureInfo?  // populated when uploadState == "failed"
}
```

## 12. Utility Methods

| Method | Return Type | Description |
| :--- | :--- | :--- |
| `Arpalus.isSDKReady()` | `Bool` | Returns `true` after successful authentication and initialization. |
| `Arpalus.getSDKVersion()` | `String` | Returns the SDK version string (e.g., `"1.2(3)"`). |
| `Arpalus.getSessionsFolderSize()` | `Double` | Returns total local session storage in megabytes. |
| `Arpalus.clearSessionFolder()` | `Void` | Deletes all local session data. Pending uploads will be lost. |

### Finishing Background Uploads

Resumable uploads continue while your app is suspended. For them to finish, forward the system's background-session relaunch event from your `AppDelegate`. The call returns `true` only when the identifier belongs to the SDK's own background session, so apps that run their own background sessions can still handle theirs:

```swift
func application(_ application: UIApplication,
                 handleEventsForBackgroundURLSession identifier: String,
                 completionHandler: @escaping () -> Void) {
    guard Arpalus.handleBackgroundURLSessionEvents(identifier: identifier,
                                                   completion: completionHandler) else {
        // Not an Arpalus session — handle your own background session here.
        return
    }
}

@discardableResult
public static func handleBackgroundURLSessionEvents(
    identifier: String,
    completion: @escaping () -> Void
) -> Bool
```

### Backend Environment

The SDK can talk to either the production or staging backend. The active environment is exposed as a settable property on `Arpalus`:

```swift
public static var backendEnvironment: BackendEnvironment { get set }

public enum BackendEnvironment: String, Codable, CaseIterable {
    case production
    case staging
}
```

**Defaults:** Release builds default to `.production`; Debug builds default to `.staging`. The override is persisted in `UserDefaults`, so the value survives app restarts.

Host apps that want to expose a developer toggle (e.g. a hidden in-app menu) can flip the environment at runtime — subsequent network requests pick up the new value with no SDK restart required:

```swift
Arpalus.backendEnvironment = .staging
// later…
Arpalus.backendEnvironment = .production
```

> **Production safety:** App Store / TestFlight builds (Release configuration) always start on `.production`. You don't need to set this explicitly for normal customer-facing builds.

## 13. Custom Scan UI (Advanced)

By default, the `ScanViewController` includes a built-in overlay with scan buttons, instructions, warnings, and confirmation modals. If you need to customize this UI, you can provide your own overlay.

### Overview

Pass a `customOverlay` closure when requesting the scan view controller:

```swift
Arpalus.getScanViewController(
    sessionId: sessionId,
    customOverlay: { MyCustomOverlayViewController() }
) { result in
    // ...
}
```

Your custom overlay must conform to the `ScanOverlay` protocol:

```swift
public protocol ScanOverlay: UIViewController {
    var buttonsLayer: ScanButtonsLayer? { get }
    var instructionLayer: InstructionLayer? { get }
    var warningsLayer: WarningsLayer? { get }
    var modalsLayer: ModalsLayer? { get }
}
```

Each layer is optional — return `nil` for any layer you want the SDK to skip.

### Layer Protocols

#### ScanButtonsLayer — Scan Controls

```swift
public protocol ScanButtonsLayer: UIViewController {
    func setScanner(_ scanner: ScanControlsInput)
    func scanStateChanged(_ state: ScanState)
    func calibrationProgressChanged(_ calibrationProgress: CalibrationProgress)
    func sessionScanCountChanged(_ count: Int)
}
```

#### ScanControlsInput — Actions You Can Trigger

```swift
public protocol ScanControlsInput: AnyObject {
    func startScan()               // Begin a new scan
    func stopScan()                // Stop the current scan
    func resetScan()               // Discard current scan, return to idle
    func forceSaveScan()           // Force-save even if minimum thresholds not met
    func cancelScan(force: Bool)   // Cancel entire session
    func endScan()                 // End the session normally
}
```

#### InstructionLayer — On-Screen Instructions

```swift
public protocol InstructionLayer: UIViewController {
    func scanStateChanged(_ state: ScanState)
}
```

#### WarningsLayer — Warning Toasts

```swift
public protocol WarningsLayer: UIViewController {
    func sessionInterrupted()
    func showWarning(_ warning: Warning)
    func clearWarning(_ priority: Int?)
}
```

#### ModalsLayer — Confirmation Dialogs

```swift
public protocol ModalsLayer: UIViewController {
    func setScanner(_ scanner: ScanControlsInput)
    func showModal(_ modal: ScanModal)
}
```

### Base Classes for Custom Overlays

The SDK provides `HostingParentController` and `HostingParentView` as base classes for custom overlays. They automatically handle touch pass-through and clear SwiftUI hosting view backgrounds.

```swift
open class HostingParentController: UIViewController {
    public var makeBackgroundsClear = true
    public var forwardBaseTouchesTo: UIView?
}
```

### Minimal Custom Overlay Example

```swift
class MyOverlay: UIViewController, ScanOverlay {
    let myButtons = MyButtonsLayer()
    var buttonsLayer: ScanButtonsLayer? { myButtons }
    var instructionLayer: InstructionLayer? { nil }
    var warningsLayer: WarningsLayer? { nil }
    var modalsLayer: ModalsLayer? { nil }
}

class MyButtonsLayer: UIViewController, ScanButtonsLayer {
    private weak var scanner: ScanControlsInput?

    func setScanner(_ scanner: ScanControlsInput) {
        self.scanner = scanner
    }

    func scanStateChanged(_ state: ScanState) {
        switch state {
        case .idle:
            startButton.isEnabled = true
        case .calibrating:
            startButton.isEnabled = false
        case .scanning:
            stopButton.isEnabled = true
        case .saving:
            stopButton.isEnabled = false
        }
    }

    func calibrationProgressChanged(_ progress: CalibrationProgress) {
        progressLabel.text = "\(Int(progress.percentage * 100))%"
    }

    func sessionScanCountChanged(_ count: Int) {
        scanCountLabel.text = "Scans: \(count)"
    }

    @objc func startTapped() { scanner?.startScan() }
    @objc func stopTapped() { scanner?.stopScan() }
}
```

## 14. Scan States & Lifecycle

Each scan within a session progresses through the following states:

```swift
public enum ScanState: String {
    case idle         // Ready to start a new scan
    case calibrating  // Calibrating against the shelf
    case scanning     // Actively capturing and processing
    case saving       // Finalizing the current scan
}
```

### State Flow

```
           startScan()
   idle ─────────────────► calibrating
    ▲                          │
    │                          │ (shelf detected, calibration complete)
    │                          ▼
    │                       scanning
    │                          │
    │              stopScan()  │
    │                          ▼
    └────────────────────── saving ──► back to idle
                                       (scan saved)
```

### CalibrationProgress

```swift
public struct CalibrationProgress: Equatable {
    public let current: Int       // Calibration points captured
    public let total: Int         // Total points required
    public var percentage: Double // 0.0 to 1.0
    public var isComplete: Bool   // true when current >= total
}
```

## 15. Warnings & Modals

### Warning Types

During scanning, the SDK generates warnings to guide the user:

```swift
public enum WarningType: Equatable, Hashable {
    // Scanning guidance
    case movingTooFast
    case rotatingTooFast
    case tooCloseToShelf
    case tooFarFromShelf
    case angleTooSteep(AngleType)

    // Calibration guidance
    case invalidCalibrationAngle(AngleType)
    case calibrationTooClose

    // Success / info
    case scanSaved(scanNumber: Int)
    case sessionCompleted(scanCount: Int)
    case calibrationComplete
    case scanDiscarded

    // Error
    case sessionInterrupted

    public enum AngleType {
        case pitch, yaw, roll
    }
}

public struct Warning: Equatable, Hashable {
    public let type: WarningType
}
```

### Modal Types

The SDK presents confirmation dialogs via the `ModalsLayer`:

```swift
public enum ScanModal: Identifiable, Equatable {
    case insufficientData
    case scanCancellationRequested(scanCount: Int, scanInProgress: Bool)
    case imageLimitReached
    case warningLimitReached
}
```

When displaying these modals, use the `ScanControlsInput` methods to handle user choices (e.g., `forceSaveScan()` to save anyway, `resetScan()` to discard, `cancelScan(force: true)` to confirm cancellation).

## 16. Data Models Reference

### Complete Type Summary

| Type | Kind | Description |
| :--- | :--- | :--- |
| `Arpalus` | enum | Static SDK API — all interaction goes through this type. |
| `AuthResponse` | struct | Authentication result with tokens and client/project info. |
| `User` | struct | User info (returned for email/password login only). |
| `Client` | struct | A client organization with its projects. |
| `Project` | struct | A project within a client (has `id` and `name`). |
| `Hierarchy` | struct | Project configuration with stores and aisles. |
| `Store` | struct | A store location containing aisles. |
| `Aisle` | struct | An aisle within a store. |
| `PlanInfo` | struct | Optional planogram info attached to an aisle. |
| `ScanResult` | struct | Summary of a completed scan. |
| `ActiveSession` | struct | Snapshot of a session's state and upload progress. |
| `UploadInfo` | struct | Overall upload state, per-session progress, and per-session failures. |
| `UploadState` | enum | Upload pipeline state: `idle`, `uploading`, `paused`, `failed`. |
| `UploadFailureInfo` | struct | Details of an upload failure (code, message, retryability). |
| `ArpalusError` | enum | Structured error returned by every completion handler (`code`, `message`). |
| `DetectorOption` | struct | A selectable detector for an aisle (per-category projects). |
| `RequiredModelsManifest` | struct | Model set the active project requires, plus cache state. |
| `ModelDescriptor` | struct | A single model file to download (or already cached). |
| `ModelDownloadProgress` | enum | Progress events while `downloadRequiredModels` runs. |
| `ModelDownloadViewController` | class | Built-in model-download progress UI. |
| `ScanEvent` | enum | User-visible events emitted during a scan via `ScanViewController.scanEvents`. |
| `ScanError` | enum | Error payload of `ScanEvent.scanError`. |
| `ScanDetection` | struct | A single product detection (normalized center + dimensions). |
| `ScanDetectionImage` | struct | Image a set of `ScanDetection`s belongs to. |
| `ScanState` | enum | Current scan state: `idle`, `calibrating`, `scanning`, `saving`. |
| `CalibrationProgress` | struct | Calibration point progress during `calibrating` state. |
| `WarningType` | enum | Types of guidance warnings during scanning. |
| `Warning` | struct | A warning instance with its type. |
| `ScanModal` | enum | Confirmation dialog types during scan lifecycle. |
| `BackendEnvironment` | enum | Active backend host: `.production` or `.staging`. Read/written via `Arpalus.backendEnvironment`. |
| `ScanViewController` | class | The full-screen AR scan view controller. |
| `ScanOverlay` | protocol | Custom overlay protocol for UI customization. |
| `ScanButtonsLayer` | protocol | Custom buttons layer protocol. |
| `InstructionLayer` | protocol | Custom instruction layer protocol. |
| `WarningsLayer` | protocol | Custom warning display protocol. |
| `ModalsLayer` | protocol | Custom modal display protocol. |
| `ScanControlsInput` | protocol | Scan action methods provided to custom UI layers. |
| `HostingParentController` | class | Optional base class for custom overlays with touch pass-through. |
| `HostingParentView` | class | The view backing `HostingParentController`. |

## 17. Offline Support

The SDK supports offline operation after at least one successful online session:

- **Authentication** — Cached credentials allow offline authentication using a previously valid access key.
- **Initialization** — Cached project configuration and compiled ML models are used when the server is unreachable.
- **Session upload** — Scan data is persisted locally and uploaded automatically when connectivity is restored. Uploads resume in the background.

No additional code is required to enable offline support — it works transparently.

## 18. Error Handling

As of 2.1.6, every asynchronous SDK action reports failure through its completion handler as a structured **`ArpalusError`** — `Result<T, ArpalusError>` — instead of a bare `Error`. `ArpalusError` exposes a **stable, machine-readable `code`** and a human-readable `message`, so you can branch on the failure programmatically:

```swift
Arpalus.startSession(
    projectName: hierarchy.projectName,
    storeId: store.storeId,
    aisleId: aisle.id,
    displayId: aisle.displayId,
    userData: [:]
) { result in
    switch result {
    case .success(let sessionId):
        break // proceed
    case .failure(let error):
        switch error.code {
        case "auth.unauthorized":
            presentSignIn()                       // session expired — re-login
        case "resources.insufficientStorage":
            promptFreeUpStorage()
        default:
            showAlert(error.message)              // human-readable fallback
        }
    }
}
```

`ArpalusError` is an enum grouped into failure categories, each with its own stable code:

```swift
public indirect enum ArpalusError: Error, LocalizedError {
    case auth(AuthFailure)
    case configuration(ConfigurationFailure)
    case network(NetworkFailure)
    case session(SessionFailure)
    case device(DeviceFailure)
    case unexpected(underlying: Error)

    public var code: String { get }                  // e.g. "auth.unauthorized"
    public var message: String { get }               // human-readable
    public var recoverySuggestion: String? { get }
    public var underlyingDescription: String? { get }
    public var isRetryable: Bool { get }
}
```

> The completion-based `cancelSession(sessionId:completion:)` and `retryUpload(sessionId:completion:)` also deliver `ArpalusError` (typically `session.notFound`). The deprecated `cancelSession(sessionId:)` (no completion) reports nothing.

### Error Code Reference

| `code` | `message` (example) | When it occurs | Recommended action |
| :--- | :--- | :--- | :--- |
| `auth.unauthorized` | `Unauthorized access` | Token/credentials missing or rejected; auth session expired or cleared | Re-authenticate (or `restoreSession`); observe `onSessionExpired` to catch this globally |
| `auth.offlineCredentialsUnavailable` | `…` | Offline, but no valid cached credentials to authenticate with | Reconnect and authenticate online at least once |
| `auth.noActiveSession` | `No active session to restore; sign in first` | `restoreSession` with nothing cached | Route the user to sign-in |
| `configuration.invalid` / `configuration.missing` / `configuration.notFound` | `…` | Called out of order, missing/invalid project configuration | `authenticate` + `initialize` before scanning; verify identifiers |
| `model.downloadFailed` / `model.compileFailed` | `Failed to download/compile model <name>` | A required CoreML model couldn't be fetched or compiled | Retry on a stable connection; free storage |
| `network.unavailable` / `network.error` / `network.invalidResponse` | `…` | Device offline, transport failed, or an unexpected response | Retry when connectivity returns |
| `http.error` / `http.notFound` / `http.serverError` | `HTTP request failed with status code <n>` / `Resource not found` / `Server error (<n>)` | Server returned a non-success or 5xx status | Inspect the status; retry later; contact support if it persists |
| `permissions.denied` | `Missing Permissions: …` | Camera/location permission denied or restricted (checked before scanning) | Ask the user to grant permissions in iOS Settings |
| `resources.unsupportedDevice` / `resources.lowMemory` / `resources.insufficientStorage` / `resources.unavailable` | `Missing Resources: …` | A required capability/resource is unavailable (checked before scanning) | Use a supported physical device; free memory/storage |
| `storage.writeFailed` | `…` | Writing session data to disk failed | Free storage and retry |
| `session.notFound` / `session.notActive` | `Session not found: <id>` / `Session is not active: <id>` | Unknown or non-active session id | Verify the `sessionId` and session state |
| `session.createFailed` | `…` | `startSession` failed — inspect the underlying cause (often `auth.unauthorized`) | Branch on the cause; re-login if auth expired |
| `session.uploadFailed` | `Session upload failed: <id>` | A background upload failed (surfaced via `getUploadInfo()`) | Offer `retryUpload(sessionId:)` |
| `scan.detectionUnavailable` | `Computer-vision detection is unavailable` | Detection setup failed | Verify models downloaded; retry |
| `scan.viewCreationFailed` | `…` | The scan UI could not be created | Verify session state, permissions, resources, and that `initialize` succeeded |
| `unknown` | `…` | A lower-level system / Vision / CoreML error was wrapped | Inspect `underlyingDescription`; share with support if it persists |

### Errors by API

| API | Codes it can surface |
| :--- | :--- |
| `authenticate` / `login` / `restoreSession` | `auth.unauthorized`, `auth.offlineCredentialsUnavailable`, `network.*`, `http.*`, `unknown` (`login` adds `configuration.invalid`; `restoreSession` adds `auth.noActiveSession`) |
| `initialize` | `configuration.*`, `model.downloadFailed`, `model.compileFailed`, `network.*`, `http.*`, `unknown` |
| `startSession` | `session.createFailed` (cause: `auth.unauthorized`, `configuration.*`, `storage.writeFailed`, `resources.insufficientStorage`, …) |
| `getScanViewController` | `session.notFound`, `session.notActive`, `permissions.denied`, `resources.*`, `scan.viewCreationFailed` |
| `endAndUploadSession` | `session.notFound`, `session.notActive`, `storage.writeFailed`, `resources.insufficientStorage`, `unknown` — upload *delivery* failures are **not** delivered here; see note below |
| `cancelSession` / `retryUpload` | `session.notFound` |

> **Upload outcomes are not reported through `endAndUploadSession`.** Its completion fires with `.success` as soon as the upload is dispatched. To observe whether the upload actually succeeds, retries, or fails, subscribe to `getUploadInfo()` (see [§10. Monitoring Upload Progress](#10-monitoring-upload-progress)) and track `UploadState` / `info.failures`. Terminal failures don't retry automatically — offer the user `retryUpload(sessionId:)`.

## 19. Best Practices

1. **Authenticate once at app launch.** Store the access key securely (e.g., in the Keychain or a secure configuration file).
2. **Initialize after authentication.** Call `initialize` once per app session. The `Hierarchy` can be cached in memory.
3. **Always use Release build configuration** when building and testing. The SDK is optimized for Release builds.
4. **Handle the session lifecycle explicitly.** Always call `endAndUploadSession` or `cancelSession` — do not leave sessions in an "active" state indefinitely.
5. **Monitor uploads for user feedback.** Subscribe to `getUploadInfo()` to keep users informed of overall and per-session upload progress.
6. **Check `isSDKReady()` before starting sessions.** This confirms that authentication and initialization completed successfully.
7. **Use `getSessionsFolderSize()` to monitor storage.** Scan data can accumulate. Consider prompting the user when storage grows large.
8. **Physical device only.** AR features require a physical device. Include appropriate checks for Simulator builds.

## 20. Complete Integration Example

The following example demonstrates the full SDK integration flow in a single controller class:

```swift
import UIKit
import ArpalusSDK
import Combine

class ScanFlowController {
    private var hierarchy: Hierarchy?
    private var currentSessionId: String?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Step 1: Authenticate
    func authenticate(accessKey: String,
                      completion: @escaping (Bool) -> Void) {
        Arpalus.authenticate(token: accessKey) { [weak self] result in
            switch result {
            case .success(let auth):
                let clientId = auth.clientId!
                let projectId = auth.clients[clientId]!
                    .projects.first!.id
                self?.initialize(
                    clientId: clientId,
                    projectId: projectId,
                    completion: completion
                )
            case .failure(let error):
                print("Auth failed: \(error.localizedDescription)")
                completion(false)
            }
        }
    }

    // MARK: - Step 2: Initialize
    private func initialize(clientId: String,
                            projectId: String,
                            completion: @escaping (Bool) -> Void) {
        Arpalus.initialize(
            clientId: clientId,
            projectId: projectId
        ) { [weak self] result in
            switch result {
            case .success(let hierarchy):
                self?.hierarchy = hierarchy
                completion(true)
            case .failure(let error):
                print("Init failed: \(error.localizedDescription)")
                completion(false)
            }
        }
    }

    // MARK: - Step 3: Start Session
    func startSession(store: Store, aisle: Aisle,
                      completion: @escaping (Bool) -> Void) {
        guard let hierarchy = hierarchy else { return }
        Arpalus.startSession(
            projectName: hierarchy.projectName,
            storeId: store.storeId,
            aisleId: aisle.id,
            displayId: aisle.displayId,
            userData: [:]
        ) { [weak self] result in
            switch result {
            case .success(let sessionId):
                self?.currentSessionId = sessionId
                completion(true)
            case .failure:
                completion(false)
            }
        }
    }

    // MARK: - Step 4: Present Scanner
    func presentScanner(from nav: UINavigationController) {
        guard let sessionId = currentSessionId else { return }
        Arpalus.getScanViewController(
            sessionId: sessionId
        ) { result in
            switch result {
            case .success(let scanVC):
                scanVC.setOnScanFinished { _ in
                    nav.popViewController(animated: true)
                }
                scanVC.setOnScanCancelled { _ in
                    nav.popViewController(animated: true)
                }
                DispatchQueue.main.async {
                    nav.pushViewController(scanVC, animated: true)
                }
            case .failure(let error):
                print("Scanner failed: \(error)")
            }
        }
    }

    // MARK: - Step 5: End Session & Upload
    func endSession(completion: @escaping (ScanResult?) -> Void) {
        guard let sessionId = currentSessionId else { return }
        Arpalus.endAndUploadSession(
            sessionId: sessionId
        ) { [weak self] result in
            switch result {
            case .success(let scanResult):
                self?.currentSessionId = nil
                completion(scanResult)
            case .failure:
                completion(nil)
            }
        }
    }

    // MARK: - Upload Monitoring
    func observeUploads() {
        Arpalus.getUploadInfo()
            .receive(on: DispatchQueue.main)
            .sink { info in
                switch info.state {
                case .idle:
                    print("No active uploads")
                case .uploading(let progress):
                    print("Uploading: \(progress)%")
                case .paused(let progress):
                    print("Upload paused at \(progress)%")
                }
            }
            .store(in: &cancellables)
    }
}
```

---

_For questions or access key requests, contact the Arpalus DevOps team._
