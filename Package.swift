// swift-tools-version:6.0
import PackageDescription
import CompilerPluginSupport

let package = Package(
    name:"QuickLMDB",
	platforms:[
		.macOS(.v15)
	],
    products:[
        .library(
            name: "QuickLMDB",
            targets: ["QuickLMDB"]
        ),
    ],
    dependencies:[
		.package(url:"https://github.com/tannerdsilva/CLMDB.git", "0.9.26"..<"0.9.31"),
		.package(url:"https://github.com/tannerdsilva/rawdog.git", "16.0.0"..<"17.0.0"),
		.package(url:"https://github.com/apple/swift-system.git", "1.0.0"..<"2.0.0"),
		.package(url:"https://github.com/apple/swift-syntax.git", "600.0.1"..<"601.0.0"),
		.package(url:"https://github.com/apple/swift-log.git", "1.0.0"..<"2.0.0")
    ],
	targets: [
		.target(
			name:"QuickLMDB",
			dependencies:[
				"CLMDB",
				.product(name:"SystemPackage", package:"swift-system"),
				.product(name:"RAW", package:"rawdog"),
				"QuickLMDBMacros"
			]
		),
		.macro(
			name:"QuickLMDBMacros",
			dependencies:[
				.product(name:"SwiftSyntax", package:"swift-syntax"),
				.product(name:"SwiftSyntaxMacros", package:"swift-syntax"),
				.product(name:"SwiftOperators", package:"swift-syntax"),
				.product(name:"SwiftParser", package:"swift-syntax"),
				.product(name:"SwiftParserDiagnostics", package:"swift-syntax"),
				.product(name:"SwiftCompilerPlugin", package:"swift-syntax"),
				.product(name:"Logging", package:"swift-log")
			]
		),
		.testTarget(
			name: "QuickLMDBTests",
			dependencies: ["QuickLMDB"]
		),
	]
)
