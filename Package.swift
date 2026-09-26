// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LocusCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "LocusCore", targets: ["LocusCore"])],
    targets: [
        .target(name: "LocusCore", path: "Locus/Core"),
        .testTarget(name: "LocusCoreTests", dependencies: ["LocusCore"], path: "Tests/LocusCoreTests")
    ]
)
