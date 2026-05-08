// swift-tools-version:5.7
import PackageDescription

let version = "2.1.4"
let checksum = "d6cfe0bc04927a3822fcd1523764e306ac2aaef14064ad33c38e87eb3a86aeb4"

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
