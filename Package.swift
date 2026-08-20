// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexPetLink",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CodexPetLinkCore", targets: ["CodexPetLinkCore"]),
        .executable(name: "codex-pet-link", targets: ["codex-pet-link"]),
    ],
    targets: [
        .target(name: "CodexPetLinkCore"),
        .executableTarget(name: "codex-pet-link", dependencies: ["CodexPetLinkCore"]),
        .testTarget(name: "CodexPetLinkCoreTests", dependencies: ["CodexPetLinkCore"]),
    ]
)
