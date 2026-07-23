// swift-tools-version:5.7
import PackageDescription

let version = "2.1.8"
let checksum = "c5e4f5c3f337f31f3874df58ea146d32e9ed1370d8cc700c0c6b6f87725c242a"

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
