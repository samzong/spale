// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "spale",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "spale", targets: ["spale"])],
    targets: [
        .target(name: "SpaleCore"),
        .executableTarget(
            name: "spale",
            dependencies: ["SpaleCore"],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", "Info.plist"]),
            ]
        ),
        .executableTarget(name: "CoreContracts", dependencies: ["SpaleCore"], path: "Tests/SpaleCoreTests")
    ],
    swiftLanguageModes: [.v5]
)
