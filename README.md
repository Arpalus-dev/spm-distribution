# ArpalusSDK for iOS

AR-powered shelf scanning and product recognition for iOS. Uses ARKit, Vision, and CoreML to detect retail products through the device camera in real time.

All SDK interaction goes through static methods on the `Arpalus` enum — no singletons to manage.

## Requirements

- iOS 16.6 or later
- Xcode 26 or later
- Physical iOS device (AR is not supported in Simulator)
- An Arpalus access key — contact the Arpalus DevOps team

## Installation

### 1. Configure access credentials

The SDK binary is hosted on an authenticated CDN. Add credentials to your `~/.netrc` file:

```
machine sdk.arpalus.com
login token
password YOUR_JWT_TOKEN
```

Set the correct permissions:

```bash
chmod 600 ~/.netrc
```

If you don't have a JWT token, contact the Arpalus DevOps team.

### 2. Add the package

In Xcode: **File → Add Package Dependencies…** and enter:

```
git@github.com:Arpalus-dev/spm-distribution.git
```

Or add it directly to your `Package.swift`:

```swift
.package(url: "git@github.com:Arpalus-dev/spm-distribution.git", from: "3.0.1")
```

### 3. Declare camera usage

Add the following to your app's `Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>Camera access is required for shelf scanning.</string>
```

The system prompts the user automatically when the scan view is first presented.

## Quick Start

A complete scan flow is five SDK calls:

```swift
import ArpalusSDK

// 1. Authenticate
Arpalus.authenticate(token: "your-access-key") { result in
    guard case .success(let auth) = result,
          let clientId = auth.clientId,
          let projectId = auth.clients?[clientId]?.projects.first?.id
    else { return }

    // 2. Initialize (downloads ML models on first run, if the project ships any)
    Arpalus.initialize(clientId: clientId, projectId: projectId) { result in
        guard case .success(let hierarchy) = result,
              let store = hierarchy.stores.first,
              let aisle = store.aisles.first
        else { return }

        // 3. Start a session
        Arpalus.startSession(
            projectName: hierarchy.projectName,
            storeId: store.storeId,
            aisleId: aisle.id,
            displayId: aisle.displayId,
            userData: [:]
        ) { result in
            guard case .success(let sessionId) = result else { return }

            // 4. Present the scan view controller
            Arpalus.getScanViewController(sessionId: sessionId) { result in
                guard case .success(let vc) = result else { return }
                vc.setOnScanFinished { _ in
                    // 5. End and upload when done
                    Arpalus.endAndUploadSession(sessionId: sessionId) { _ in }
                }
                navigationController?.pushViewController(vc, animated: true)
            }
        }
    }
}
```

See the [Integration Guide](./INTEGRATION.md) for the full walkthrough — method signatures, data models, custom overlays, upload monitoring, offline support, and best practices.

## Documentation

- [Integration Guide](./INTEGRATION.md) — Full API reference and step-by-step integration
- [Changelog](./CHANGELOG.md) — Release notes and version history
- [Notices](./NOTICES) — Third-party software notices

## Support

For questions, access key requests, or to report issues, contact the Arpalus DevOps team.

---

© Arpalus LTD. Confidential.
