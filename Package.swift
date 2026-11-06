// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MnemoCore",
    platforms: [.iOS("26.0"), .macOS(.v14)],
    products: [.library(name: "MnemoCore", targets: ["MnemoCore"]), .library(name: "CZstd", targets: ["CZstd"])],
    dependencies: [.package(path: "Vendor/swift-fsrs")],
    targets: [
        .target(name: "MnemoCore", dependencies: [.product(name: "FSRS", package: "swift-fsrs")], path: "Core"),
        .target(name: "CZstd", path: "Vendor/zstd", sources: ["common", "decompress"], publicHeadersPath: "include", cSettings: [.headerSearchPath("."), .headerSearchPath("common"), .headerSearchPath("decompress"), .define("ZSTD_LEGACY_SUPPORT", to: "0"), .define("ZSTD_DISABLE_ASM")]),
        .testTarget(name: "MnemoCoreTests", dependencies: ["MnemoCore", .product(name: "FSRS", package: "swift-fsrs")], path: "Tests/CoreTests")
    ]
)
