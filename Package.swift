// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PromptPin",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "PromptPin", targets: ["PromptPin"])],
    targets: [
        .target(name: "PromptPinCore"),
        .executableTarget(name: "PromptPin", dependencies: ["PromptPinCore"]),
        .executableTarget(name: "PromptPinCoreChecks", dependencies: ["PromptPinCore"], path: "Tests/PromptPinCoreTests")
    ],
    swiftLanguageModes: [.v5]
)
