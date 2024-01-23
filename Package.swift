// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "QuickLMDB",
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "QuickLMDB",
            targets: ["QuickLMDB"]),
    ],
    dependencies: [
		.package(url:"https://github.com/tannerdsilva/CLMDB.git", .exact("0.9.30")),
		.package(url:"https://github.com/tannerdsilva/rawdog.git", from:"5.3.0"),
		.package(url:"https://github.com/apple/swift-system.git", .upToNextMajor(from:"1.0.0"))
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "QuickLMDB",
			dependencies: [
				"CLMDB", 
				.product(name:"SystemPackage", package:"swift-system"),
				.product(name:"RAW", package:"rawdog")
			]),
        .testTarget(
            name: "QuickLMDBTests",
            dependencies: ["QuickLMDB"]),
    ]
)
