// swift-tools-version: 6.2
import PackageDescription

let package = Package(
	name: "Unifind",
	platforms: [.macOS(.v26)],
	targets: [
		.executableTarget(name: "Unifind", path: "Sources/Unifind"),
		.testTarget(name: "UnifindTests", dependencies: ["Unifind"]),
	]
)
