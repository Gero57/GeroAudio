// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "GeroAudio",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "GeroAudio", targets: ["GeroAudio"])],
    targets: [.executableTarget(name: "GeroAudio", path: "Sources/GeroAudio")]
)
