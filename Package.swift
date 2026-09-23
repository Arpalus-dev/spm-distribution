// swift-tools-version:5.7
import PackageDescription

let version = "3.0.2"
let checksum = "2f5927d7121d0e0b45b4eb9b58c93e2ba7797af576a6fe87f7f82f7e5260bfad"

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
