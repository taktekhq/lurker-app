// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LurkerKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "LurkerKit", targets: ["LurkerKit"])
    ],
    targets: [
        .target(name: "LurkerKit"),
        .testTarget(name: "LurkerKitTests", dependencies: ["LurkerKit"])
    ]
)
