// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "TranceCore", platforms: [.macOS(.v14)], products: [.library(name: "TranceCore", targets: ["TranceCore"])], targets: [.target(name: "TranceCore", path: "Models"), .testTarget(name: "TranceCoreTests", dependencies: ["TranceCore"], path: "Tests")], swiftLanguageModes: [.v6])
