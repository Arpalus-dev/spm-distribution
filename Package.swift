// swift-tools-version:5.7
import PackageDescription

let version = "2.0.0"
let checksum = "fee49363572544f6108aab07ff1a29cdbbce0a59fb6e08df2e1c0b2c15e60f60"

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

