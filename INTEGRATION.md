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
    completion: @escaping (Result<AuthResponse, Error>) -> Void
)
```

| Parameter | Type | Description |
| :--- | :--- | :--- |
| `token` | `String` | The SDK access key provided by the Arpalus DevOps team. |
| `completion` | `Result<AuthResponse, Error>` | Called on completion with the authentication response or an error. |

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
    completion: @escaping (Result<Hierarchy, Error>) -> Void
)
```

| Parameter | Type | Description |
| :--- | :--- | :--- |
| `clientId` | `String` | The client identifier from the `AuthResponse`. |
| `projectId` | `String` | The project identifier selected from the client's projects. |
| `completion` | `Result<Hierarchy, Error>` | Called with the store/aisle hierarchy or an error. |

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
    completion: @escaping (Result<String, Error>) -> Void
)
```

| Parameter | Type | Description |
| :--- | :--- | :--- |
| `projectName` | `String` | The project name from `hierarchy.projectName`. |
| `storeId` | `String` | The store identifier from the selected `Store.storeId`. |
| `aisleId` | `String` | The **server-unique** `Aisle.id` from the selected aisle. Used internally to resolve the aisle's `cv_category` from the hierarchy. |
| `displayId` | `String` | The **human-facing** `Aisle.displayId` (e.g. `"Aisle-4"`). Recorded as `display_id` in the scan metadata that flows downstream. |
| `userData` | `[String: Any]` | Optional free-form metadata attached to session logs. |
| `completion` | `Result<String, Error>` | Called with the `sessionId` string on success. |

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
    completion: @escaping (Result<ScanViewController, Error>) -> Void
)
```

| Parameter | Type | Description |
| :--- | :--- | :--- |
| `sessionId` | `String` | The session ID returned by `startSession()`. |
| `customOverlay` | `(() -> ScanOverlay)?` | Optional closure providing a custom UI overlay. Pass `nil` for built-in UI. |
| `completion` | `Result<ScanViewController, Error>` | Called with the configured scan view controller. |

### ScanViewController

```swift
public final class ScanViewController: UIViewController {
    /// Called when a scan finishes successfully.
    public func setOnScanFinished(_ handler: ((ScanResult) -> Void)?)

    /// Called when the user cancels the scan session.
    public func setOnScanCancelled(_ handler: ((String) -> Void)?)
}
```

> **Important:** The `ScanViewController` manages its own AR session, camera feed, and UI. Present it full-screen and dismiss it in response to the `onScanFinished` or `onScanCancelled` callbacks.

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
    completion: @escaping (Result<ScanResult, Error>) -> Void
)
```

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
        }

        // Per-session progress
        for (sessionId, progress) in info.sessions {
            print("Session \(sessionId): \(progress)%")
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
    case uploading(progress: Int)  // 0 — 100
    case paused(progress: Int)     // 0 — 100
}

public struct UploadInfo: Equatable {
    public let state: UploadState
    public let sessions: [String: Int]  // Per-session progress (0 — 100), keyed by sessionId

    public static let idle = UploadInfo(state: .idle, sessions: [:])
}
```

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

Abandons a session and **permanently deletes** all its data from disk.

```swift
Arpalus.cancelSession(sessionId: sessionId)
```

### ActiveSession

```swift
public struct ActiveSession {
    public let sessionId: String
    public let projectName: String
    public let storeId: String
    public let aisleId: String
    public let scanCount: Int
    public let startDate: Date
    public let uploadState: String
    // uploadState: "active", "pending", "uploading", "uploaded"
}
```

## 12. Utility Methods

| Method | Return Type | Description |
| :--- | :--- | :--- |
| `Arpalus.isSDKReady()` | `Bool` | Returns `true` after successful authentication and initialization. |
| `Arpalus.getSDKVersion()` | `String` | Returns the SDK version string (e.g., `"1.2(3)"`). |
| `Arpalus.getSessionsFolderSize()` | `Double` | Returns total local session storage in megabytes. |
| `Arpalus.clearSessionFolder()` | `Void` | Deletes all local session data. Pending uploads will be lost. |

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
| `UploadInfo` | struct | Overall upload state plus per-session progress. |
| `UploadState` | enum | Upload pipeline state: `idle`, `uploading`, `paused`. |
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

Every asynchronous SDK action reports failure through its completion handler as a `Result<T, Error>`:

- `authenticate(token:completion:)`
- `login(email:password:completion:)`
- `initialize(clientId:projectId:completion:)`
- `startSession(…:completion:)`
- `endAndUploadSession(sessionId:completion:)`
- `getScanViewController(…:completion:)`

`cancelSession(sessionId:)` does not report errors.

Errors are surfaced as the standard Swift `Error`. Handle the `.failure` case and read `error.localizedDescription` for a human-readable message:

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
        // proceed
        break
    case .failure(let error):
        print("Arpalus error: \(error.localizedDescription)")
        // Identify the condition from the message text (see table below).
    }
}
```

> **Note:** SDK 2.1.5 does not expose stable, machine-readable error codes. Identify a failure by the condition / message described below, and use `localizedDescription` for logs and user-facing fallback text.

### Error Reference

| Condition | `localizedDescription` | When it occurs | Recommended action |
| :--- | :--- | :--- | :--- |
| Configuration error | `Configuration error occurred`, or a specific detail such as `Missing client ID`, `Missing user ID`, `Session not found or not active: <id>`, `Invalid base URL`, or `Failed to save configuration` | Calling actions out of order or with invalid identifiers, referencing an unknown/inactive session, configuration fetch/save failures, or recognition-model download/compile failures | Authenticate and `initialize` before scanning; verify client/project/store/aisle and session identifiers; retry on a stable connection |
| Unauthorized | `Unauthorized Access` | Access token, refresh token, or credentials were missing or rejected | Authenticate again before retrying |
| Resource not found | `Resource Not Found` | A requested server resource was not found | Verify the identifiers used for the request |
| Server error | `Server Error (<code>)` | Backend returned a server-side (5xx) error | Retry later; contact Arpalus support if it persists |
| Network error | `Network Error: <detail>` — e.g. `Network Error: Cannot connect to host`, `Network Error: Invalid or unexpected response type`, `Network Error: Upload failed with status code: <n>` | Device is offline, transport failed, an unexpected response was received, or a background upload failed | Retry when connectivity returns |
| HTTP error | `HTTP Error (<statusCode>)` | Server returned a non-success HTTP status | Inspect the status code; retry if appropriate |
| Missing permissions | `Missing Permissions: <list>` — e.g. `CheckPermissions: Camera access denied`, `CheckPermissions: Location access restricted or denied` | Required camera or location permission is denied or restricted (checked before scanning) | Grant the required permissions in iOS Settings and retry |
| Missing resources | `Missing Resources: <list>` — e.g. `CheckResources: ARKit capability is not supported`, `CheckResources: Not enough ram`, `CheckResources: not enough disk space`, `CheckResources: Disk capacity is unavailable` | A required device capability or resource is unavailable (checked before scanning) | Use a supported physical device; close other apps to free memory; free device storage |
| Location error | `Location Error` | A location-related failure occurred | Check location permission/services and retry |
| Wrapped / underlying error | `Error: <underlying message>` | A lower-level system or Vision/CoreML error was wrapped by the SDK; raw `URLError` or decoding errors may also surface directly | Inspect the underlying message; retry and share it with support if it persists |
| Scan view creation failed | `Failed to create ScanViewController: <detail>` | The scan UI could not be created | Verify session state, permissions, device resources, and that initialization succeeded |

### Errors by API

| API | Conditions it can surface |
| :--- | :--- |
| `authenticate` / `login` | Unauthorized, Network error, HTTP error, Server error, Configuration error |
| `initialize` | Configuration error, Network/HTTP/Server error, Missing permissions, Missing resources |
| `startSession` | Configuration error, Missing permissions, Missing resources |
| `getScanViewController` | Configuration error, Missing permissions, Missing resources, Scan view creation failed |
| `endAndUploadSession` | Configuration error, Network error |

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
