// swift-tools-version:5.7
import PackageDescription

let version = "2.1.5"
let checksum = "60fd3c7c4252fdf5e3ce367b3317903d4d57e1e5ee546bc1985664388130065e"

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
