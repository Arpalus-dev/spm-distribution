# ArpalusSDK — iOS Integration Guide

**Minimum iOS:** 16.6 &nbsp;|&nbsp; **Xcode:** 26+ &nbsp;|&nbsp; **Physical Device Required**

_For questions or access key requests, contact the Arpalus DevOps team._

---

## 1. Overview

**ArpalusSDK** is an iOS framework for real-time, AR-powered shelf scanning and product recognition. It uses ARKit, Vision, and CoreML to detect products on retail shelves via the device camera.

The SDK handles the full scanning pipeline — 3D calibration, image capture, on-device computer vision, session management, and cloud upload — exposing a streamlined API that lets you integrate shelf scanning into your app with minimal effort.

All SDK interaction happens through the static methods on the `Arpalus` enum. There are no singleton instances to manage.

### How Scanning Works

There is a **single scanning flow** for every aisle. The detectors an aisle runs come from the project's `models_v2` configuration, keyed by the aisle's `cvCategory`:

- The generic "General Product" detector is an ordinary configured detector. It downloads and runs like any other, and is **not** appended as an implicit fallback.
- An aisle whose category has no configured detector runs **no computer vision**. AR calibration, coverage tracking, and image capture still work — the scan is a valid capture-only scan.
- **Models are optional project-wide.** A project with no models at all is a supported configuration: `initialize`, `downloadRequiredModels`, and `prepareDetectors` all succeed as no-ops. Model presence never gates initialization or scanning.

Within a scan, detectors run at two cadences: **live**, feeding the AR-tracked boxes drawn on screen, and **at save time**, once per saved image on the exact saved pixels. The save-time results are what gets written to the scan's `ScanInfo.json` and emitted as [`ScanEvent.productsDetected`](#observing-scan-events).

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
         │ Downloads & compiles ML models, if the project ships any (first run)
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

    /// Minimum host-app version the backend allows, e.g. "1.0.22" (wire key: `min_version`).
    /// Informational only — the SDK never enforces it. `nil`/empty means "no gate".
    public let minAppVersion: String?
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
    autoDownloadModels: Bool = true,
    completion: @escaping (Result<Hierarchy, ArpalusError>) -> Void
)
```

| Parameter | Type | Description |
| :--- | :--- | :--- |
| `clientId` | `String` | The client identifier from the `AuthResponse`. |
| `projectId` | `String` | The project identifier selected from the client's projects. |
| `autoDownloadModels` | `Bool` | Defaults to `true`: the completion does not fire until every required model is downloaded and compiled. Pass `false` to return as soon as the configuration is fetched and drive the download yourself (see below). |
| `completion` | `Result<Hierarchy, ArpalusError>` | Called with the store/aisle hierarchy or a structured `ArpalusError`. |

### What Happens During Initialization

1. Downloads project configuration (scan settings, thresholds) from the Arpalus server.
2. Downloads CoreML model files if not already cached locally (when `autoDownloadModels` is `true`).
3. Compiles CoreML models for the current device (first run only — cached afterward).
4. Returns the `Hierarchy` containing the store and aisle structure.

> **Note:** The first initialization on a device may take longer due to model download and compilation. Subsequent launches use cached models and are significantly faster.

> **Models are optional.** A project that configures no models is a valid capture-only configuration — `initialize` succeeds with nothing to download, online or offline. Model presence never gates initialization or scanning.

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
    public let imageUrl: URL?   // Signed link to the aisle's planogram image; nil when absent
}
```

### Downloading Models Explicitly (Optional)

By default (`autoDownloadModels: true`) models download silently inside `initialize`. If you'd rather show the user an explicit download step — useful when a project ships several large per-category detectors — pass `autoDownloadModels: false` and drive it yourself with the API below.

Use `hasDownloadableModels` after `initialize` to branch your UX:

```swift
public static var hasDownloadableModels: Bool { get }
```

When `true`, present the manual download flow and observe `ScanViewController.scanEvents` for `.productsDetected` during scanning (see [§8](#8-step-4--present-the-scan-view-controller)). When `false`, there is nothing to download — skip the download screen entirely.

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

> **Nothing to download is not an error.** For a project with no models, `requiredModels()` returns an empty manifest (`isEmpty == true`), `hasDownloadableModels` is `false`, `getModelDownloadViewController` returns `nil`, and `downloadRequiredModels` completes successfully having done nothing.

## 7. Step 3 — Start a Scan Session

Before presenting the scan camera, create a session. A session groups one or more individual scans together (e.g., scanning multiple shelf sections in the same aisle) — when the project allows it; see [Single-Scan Projects](#single-scan-projects) below.

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

### Single-Scan Projects

Whether a session may hold several scans is decided **per project**:

```swift
public static var allowsUserSegments: Bool { get }
```

Only meaningful after `initialize`. Projects (and cached configurations) that don't set it default to `true`.

When it is `false`, the session is one scan long. The SDK's own scan screen already enforces this — the "Done" button is hidden, and stopping the scan ends the session and hands control straight back to your app. Read this property to keep your own UI consistent: suppress any "scan another section into this session" affordance and call `endAndUploadSession` once the single scan finishes.

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

### Choosing a Detector

You can let the user pick which detector runs for a scan. `availableDetectors` returns exactly the detectors configured for that aisle's CV category — **no generic detector is appended**. The generic "General Product" detector appears only when it is genuinely configured for the category, in which case `isGeneric` labels it.

```swift
public static func availableDetectors(forAisleCvCategory cvCategory: String?) -> [DetectorOption]

public struct DetectorOption: Equatable {
    public let id: String           // SDK-internal model name — pass to getScanViewController(detectorId:)
    public let displayName: String  // human label for the picker
    public let cvCategory: String
    public let isGeneric: Bool      // labels the "General Product" detector; no special behavior
}
```

> **An empty result is not an error.** It means the aisle has no configured detector and will run no computer vision. Skip the picker and present a normal, capture-only scan: AR calibration, coverage, and image capture all work, and the scan saves without any detection-count check.

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
// Grab the stream first, so the Task captures only the stream —
// NOT the view controller (see the warning below).
let events = scanViewController.scanEvents

Task {
    for await event in events {
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

> **Warning — never capture the view controller inside the task.** Writing `for await event in scanViewController.scanEvents { ... }` directly inside a `Task` closure holds a strong reference to the `ScanViewController` for the lifetime of the loop — and the stream only finishes when the controller deinitializes. Neither can release the other, so the whole scanner (view controller, AR session, camera resources) leaks after dismissal. Capture the stream in a local constant as shown above, or cancel the task yourself when the scanner is dismissed.

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
    /// A configured detector produced detections for a saved image.
    case productsDetected(image: ScanDetectionImage, detections: [ScanDetection])
}
```

`productsDetected` is emitted once per saved image for any aisle that has configured detectors, and the payload mirrors exactly what is written to the scan's `ScanInfo.json` (`frameResults.specificModelResults`). Detection `x`/`y` are the **normalized center** of the bounding box; `width`/`height` are normalized dimensions:

```swift
public struct ScanDetection: Equatable {
    /// Tracked-product id. Stable across saved images for the same physical
    /// product, and unique within the session — use it to group a product's
    /// appearances without re-matching boxes yourself.
    public let id: Int

    /// The product SKU tag (see "Product identity" below).
    public let name: String

    /// The detector class label that produced this detection.
    public let categoryName: String

    public let modelName: String
    public let confidence: Double // detector confidence, [0, 1]
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

#### Product identity: `name` vs `categoryName`

`categoryName` is always the **detector's** class label. `name` is the **product SKU tag**, resolved per detection in three tiers:

1. The frame's classifier top-1, when its confidence clears the project's classifier threshold.
2. Otherwise, the tracked box's accumulated **voted SKU** — a confidence-weighted vote over that box's classifications so far — when one SKU dominates the tally.
3. Otherwise, the fixed default tag `"101000000000000000"`.

A project that configures no classifiers gets the default tag on every detection, and `name` carries no product information. Because tier 2 depends on the box's accumulated history, the same `id` can report a more specific `name` in later images of the same scan.

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

> **Idempotent since 2.1.8.** Calling this again for a session that was already ended (`pending`, `uploading`, or `uploaded`) reports success again, so a double-tap or a retried call is harmless. `session.notActive` now means only that a previous upload failed terminally — offer [`retryUpload(sessionId:)`](#11-session-management) instead.

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
    /// `true` when the scan can no longer be uploaded because time ran out —
    /// `causeCode` is either "session.expired" or "upload.urlExpired".
    public var isExpired: Bool { get }
    // Plus the originating cause: causeCode / causeMessage / causeRecoverySuggestion / causeUnderlyingDescription.
}
```

> **Expired scans (`isExpired == true`).** Two distinct causes end a scan's life:
>
> - **`causeCode == "session.expired"`** — the scan aged past the project's **scan-expiry window** (backend-configured, default 8h from session start). Company policy is that stale shelf data isn't wanted, so the scan is retired and its local data deleted. This is **terminal**: `retryUpload(sessionId:)` refuses it with `ArpalusError.session(.expired)` (`code == "session.expired"`).
> - **`causeCode == "upload.urlExpired"`** — the resumable upload URL is dead (rejected with `401`/`403`, or the resumable session returned `410 Gone`). Also terminal; a fresh `retryUpload(sessionId:)` re-zips the session and fetches a new upload URL.
>
> Render both as a distinct **"Expired"** status rather than a generic failure, and suggest re-scanning if the data is still needed. Branch on `causeCode` if you want different copy for the two. `listActiveSessions()` sweeps expired sessions before returning, so a list built from it never shows a live-looking `"pending"` for a scan that can no longer upload.

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
    // .failure(.session(.expired)) if the scan aged past the scan-expiry window
}

public static func retryUpload(
    sessionId: String,
    completion: @escaping (Result<Void, ArpalusError>) -> Void
)
```

> **Don't offer retry for an expired scan.** When the failure's `isExpired` is `true`, retrying is refused — a scan retired by the scan-expiry window fails with `session.expired` (its local data is already deleted). Hide the retry affordance in that case and suggest re-scanning. See [§10](#uploadinfo--uploadstate).

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
| `Arpalus.clearSessionFolder()` | `Void` | Deletes the local scan data of every session waiting to upload and drops their records — those uploads are lost. A session whose archive is actually being streamed right now is left alone and cleaned up when its upload finishes; already-uploaded sessions have no files left, so their records stay for your session list. |
| `Arpalus.log(_:_:)` | `Void` | Routes a host log line into the SDK's per-scan debug log, so host and SDK events interleave in the `DebugLog.txt` shipped with the scan. |

### Telemetry (Optional)

The SDK can forward its own errors and breadcrumbs to your app, report them to Arpalus, or both. **Reporting to Arpalus is opt-in and off by default.**

```swift
public static func setTelemetryHandler(
    _ observer: ArpalusTelemetryObserver?,
    sdkSelfReports: Bool = false
)

public static var sdkSelfReportsTelemetry: Bool { get set }

public protocol ArpalusTelemetryObserver: AnyObject {
    /// Delivered on the main thread.
    func arpalus(didEmit event: ArpalusTelemetryEvent)
}

public struct ArpalusTelemetryEvent: Equatable {
    public enum Kind: String, Equatable { case error, breadcrumb }
    public enum Level: String, Equatable { case info, warning, error, fatal }

    public let kind: Kind
    public let name: String              // e.g. "session.uploadFailed"
    public let level: Level
    public let message: String?
    public let attributes: [String: String]
    /// Grouping hint: signals sharing a fingerprint collapse into one issue.
    public let fingerprint: [String]?
}
```

The observer is held **weakly** — retain it yourself. Registering one does not change `sdkSelfReportsTelemetry`, so you can forward telemetry into your own backend without opting into Arpalus reporting. This controls telemetry only; crash reporting is a separate channel.

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
    /// Device ran out of storage mid-scan; scanning stopped because no more
    /// images can be saved.
    case insufficientStorage
}
```

When displaying these modals, use the `ScanControlsInput` methods to handle user choices (e.g., `forceSaveScan()` to save anyway, `resetScan()` to discard, `cancelScan(force: true)` to confirm cancellation).

> **`insufficientData` only applies to scans that run a detector.** It is the stop-time scan-validity gate (minimum images captured, minimum scan duration, minimum detections — all backend-configured). A capture-only scan, on an aisle with no configured detector, has no meaningful detection count and saves directly with no checks at all.

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
| `PlanInfo` | struct | Optional planogram info attached to an aisle (version, products, `imageUrl`). |
| `ScanResult` | struct | Summary of a completed scan. |
| `ActiveSession` | struct | Snapshot of a session's state and upload progress. |
| `UploadInfo` | struct | Overall upload state, per-session progress, and per-session failures. |
| `UploadState` | enum | Upload pipeline state: `idle`, `uploading`, `paused`, `failed`. |
| `UploadFailureInfo` | struct | Details of an upload failure (code, message, retryability, `isExpired`). |
| `ArpalusError` | enum | Structured error returned by every completion handler (`code`, `message`). |
| `DetectorOption` | struct | A selectable detector for an aisle (per-category projects). |
| `RequiredModelsManifest` | struct | Model set the active project requires, plus cache state. |
| `ModelDescriptor` | struct | A single model file to download (or already cached). |
| `ModelDownloadProgress` | enum | Progress events while `downloadRequiredModels` runs. |
| `ModelDownloadViewController` | class | Built-in model-download progress UI. |
| `ScanEvent` | enum | User-visible events emitted during a scan via `ScanViewController.scanEvents`. |
| `ScanError` | enum | Error payload of `ScanEvent.scanError`. |
| `ScanDetection` | struct | A single product detection (stable track id, SKU tag, normalized center + dimensions). |
| `ScanDetectionImage` | struct | Image a set of `ScanDetection`s belongs to. |
| `ArpalusTelemetryEvent` | struct | A telemetry signal (error or breadcrumb) emitted by the SDK. |
| `ArpalusTelemetryObserver` | protocol | Receives SDK telemetry; register via `setTelemetryHandler`. |
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

> **Offline data doesn't wait forever.** A scan that stays unuploaded past the project's scan-expiry window (backend-configured, default 8h from session start) is retired rather than uploaded — see [§10](#uploadinfo--uploadstate). Encourage users to get back online the same shift.

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

> The completion-based `cancelSession(sessionId:completion:)` and `retryUpload(sessionId:completion:)` also deliver `ArpalusError` (typically `session.notFound`; `retryUpload` adds `session.expired`). The deprecated `cancelSession(sessionId:)` (no completion) reports nothing.

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
| `session.notFound` / `session.notActive` | `Session not found: <id>` / `Session is not active: <id>` | Unknown session id, or a session whose upload already failed terminally | Verify the `sessionId`; for `notActive` offer `retryUpload(sessionId:)` |
| `session.expired` | `This scan expired before it could be uploaded` | The scan aged past the project's scan-expiry window and was retired without uploading | Terminal — show an "Expired" status and suggest re-scanning; don't offer retry |
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
| `cancelSession` | `session.notFound` |
| `retryUpload` | `session.notFound`, `session.expired` |

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
9. **Respect `allowsUserSegments`.** Don't offer a "scan another section" affordance when the project restricts a session to a single scan.
10. **Don't treat "no models" as a failure.** An empty `availableDetectors(...)` result, an empty `requiredModels()` manifest, or a `nil` download view controller all mean the project is capture-only — proceed straight to scanning.

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
                let projectId = auth.clients![clientId]!
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
                case .failed(let failure):
                    print("Upload failed: \(failure.message) [\(failure.causeCode)]")
                }
            }
            .store(in: &cancellables)
    }
}
```

---

_For questions or access key requests, contact the Arpalus DevOps team._
