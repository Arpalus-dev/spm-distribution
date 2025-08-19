// swift-tools-version:5.7
import PackageDescription

let version = "0.2.0"
let checksum = "cb2553aa5c55fa2d1624555e5a9846ffa55ae8df8f2c656c18aed2e4589d4c6b"

let package = Package(
    name: "ArpalusSDK",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "ArpalusSDK",
            targets: ["ArpalusSDK"]
        )
    ],
    targets: [
        .binaryTarget(
            name: "ArpalusSDK",
            url: "https://backend-api-105992620489.europe-west1.run.app/firebase/sdks/sdk.zip?platform=ios&version=\(version)",
            checksum: checksum
        )
    ]
)

