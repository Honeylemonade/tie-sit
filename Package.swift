// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "TIESit",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "TIESit", targets: ["TIESit"])
    ],
    targets: [
        .executableTarget(
            name: "TIESit",
            path: "Sources/TIESit"
        )
    ]
)