// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexPetIDE",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "CodexPetIDECore", targets: ["CodexPetIDECore"]),
        .executable(name: "CodexPetIDEController", targets: ["CodexPetIDEController"])
    ],
    targets: [
        .target(
            name: "CodexPetIDECore",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreServices")
            ]
        ),
        .executableTarget(
            name: "CodexPetIDEController",
            dependencies: ["CodexPetIDECore"],
            linkerSettings: [
                .linkedFramework("WebKit")
            ]
        ),
        .testTarget(
            name: "CodexPetIDECoreTests",
            dependencies: ["CodexPetIDECore"]
        )
    ],
    swiftLanguageModes: [.v5]
)
