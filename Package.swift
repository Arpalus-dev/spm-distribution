// swift-tools-version:5.7
import PackageDescription

let version = "0.2.0"
let checksum = "3a209c9693b72a006727c1056a44b8be2a5680dd77edc9cd2c0c45e42695462a"

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

