// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacMural",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "MacMural", targets: ["MacMural"])],
    targets: [
        .target(name: "MacMuralCore"),
        .executableTarget(name: "MacMural", dependencies: ["MacMuralCore"]),
        .testTarget(name: "MacMuralCoreTests", dependencies: ["MacMuralCore"])
    ]
)
