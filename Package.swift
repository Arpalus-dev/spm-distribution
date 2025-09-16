// swift-tools-version:5.7
import PackageDescription

let version = "0.2.1"
let checksum = "66e9edfea8fe3e80279baeccf1bb59c12ece36bde4217dffde36004c78b3755d"

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

