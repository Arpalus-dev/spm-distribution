// swift-tools-version:5.7
import PackageDescription

let version = "2.1.0"
let checksum = "e7995069c1628f7b2cabd21f2d8254e29af3b885a6a22c446b25571e47eee4a3"

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
