// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "QuickLMDB",
	platforms: [
		.macOS(.v10_15)
	],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "QuickLMDB",
            targets: ["QuickLMDB"]),
    ],
    dependencies: [
		.package(url:"https://github.com/tannerdsilva/CLMDB.git", from:"0.9.29"),
		.package(url:"https://github.com/tannerdsilva/rawdog.git", from:"6.0.1"),
		.package(url:"https://github.com/apple/swift-system.git", from:"1.0.0"),
		.package(url:"https://github.com/apple/swift-syntax.git", from:"509.0.1"),
		.package(url:"https://github.com/apple/swift-log.git", from:"1.4.2")
    ],
	targets: [
		.target(
			name: "QuickLMDB",
			dependencies: [
				"CLMDB", 
				.product(name:"SystemPackage", package:"swift-system"),
				.product(name:"RAW", package:"rawdog"),
				"QuickLMDBMacros"
			], swiftSettings: [.define("QUICKLMDB_MACRO_LOG")]),
		.macro(
			name:"QuickLMDBMacros",
			dependencies:[
				.product(name: "SwiftSyntax", package: "swift-syntax"),
				.product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
				.product(name: "SwiftOperators", package: "swift-syntax"),
				.product(name: "SwiftParser", package: "swift-syntax"),
				.product(name: "SwiftParserDiagnostics", package: "swift-syntax"),
				.product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
				.product(name: "Logging", package:"swift-log")
			],
			swiftSettings: [.define("QUICKLMDB_MACRO_LOG")]	
		),
		.testTarget(
			name: "QuickLMDBTests",
			dependencies: ["QuickLMDB"]),
	]
)
