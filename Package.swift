// swift-tools-version:5.7
import PackageDescription

let version = "0.2.9"
let checksum = "ad8437c1ab742225da81d24a3abe68d8bee961e4dfeb1b13dda453ad3a005a4e"

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

