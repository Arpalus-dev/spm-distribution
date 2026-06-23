// swift-tools-version:5.7
import PackageDescription

let version = "2.1.7"
let checksum = "6fd1051189b6f9ff6dcdc2df72680cf318de062e5c94a57089f3b4f64b50d703"

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
            url: "https://sdk.arpalus.com/firebase/sdks/sdk.zip?platform=ios&version=\(version)",
            checksum: checksum
        )
    ]
)
