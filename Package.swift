// swift-tools-version:5.7
import PackageDescription

let version = "2.1.6"
let checksum = "5d477aa4361d4d7a3cf4a88fe807649f81bbd3bbe5def1cfa3afb5ba21ec0798"

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
