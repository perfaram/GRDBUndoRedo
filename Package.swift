// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "GRDBUndoRedo",
    platforms: [
      .iOS(.v13),
      .macOS(.v10_15),
      .tvOS(.v13),
      .watchOS(.v7)
    ],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "GRDBUndoRedo",
            targets: ["GRDBUndoRedo"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.0.0-beta.6")
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "GRDBUndoRedo",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]),
        .testTarget(
            name: "GRDBUndoRedoTests",
            dependencies: ["GRDBUndoRedo"]),
    ]
)
