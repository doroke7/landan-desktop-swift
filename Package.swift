// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "USBCamera",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "USBCamera", path: "Sources/USBCamera")
    ]
)
