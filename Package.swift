// swift-tools-version:5.7
import PackageDescription

let version = "3.0.3"
let checksum = "bba920def5504341dbe0dc90001b6429c1440ca6f67869f92aac538b21aa337b"

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
