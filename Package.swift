// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LocalInference",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "LocalInference", targets: ["LocalInference"])],
    dependencies: [.package(url: "https://github.com/mattt/llama.swift.git", exact: "2.10549.0")],
    targets: [
        .target(name: "LocalInference", dependencies: [.product(name: "LlamaSwift", package: "llama.swift")]),
        .testTarget(name: "LocalInferenceTests", dependencies: ["LocalInference"])
    ]
)
