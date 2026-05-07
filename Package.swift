// swift-tools-version:5.7
import PackageDescription

let version = "2.1.3"
let checksum = "f23f6d1db7b61e1716d376896374488c92748cfc5e317eb9f77566bb0bb69f3f"

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
