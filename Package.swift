// swift-tools-version:5.7
import PackageDescription

let version = "0.3.1"
let checksum = "b0a4a2f2a1dd35f4986b76151f889de3af6faf376a1ecb1cc47147853eccfb06"

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

