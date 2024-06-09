// swift-tools-version: 5.9
import PackageDescription
import CompilerPluginSupport

let package = Package(
    name:"QuickLMDB",
	platforms:[
		.macOS(.v10_15)
	],
    products:[
        .library(
            name: "QuickLMDB",
            targets: ["QuickLMDB"]
        ),
    ],
    dependencies:[
		.package(url:"https://github.com/tannerdsilva/CLMDB.git", branch:"master3"),
		// .package(path:"../rawdog"),
		.package(url:"https://github.com/tannerdsilva/rawdog.git", branch:"hacklash"),
		.package(url:"https://github.com/apple/swift-system.git", "1.0.0"..<"2.0.0"),
		.package(url:"https://github.com/apple/swift-syntax.git", from:"509.0.1"),
		.package(url:"https://github.com/apple/swift-log.git", "1.0.0"..<"2.0.0")
    ],
	targets: [
		.target(
			name:"QuickLMDB",
			dependencies:[
				"CLMDB",
				.product(name:"SystemPackage", package:"swift-system"),
				.product(name:"RAW", package:"rawdog"),
				"QuickLMDBMacros",
				.product(name:"RAW_chachapoly", package:"rawdog")
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
			],
			swiftSettings:[
				.define("QUICKLMDB_MACRO_LOG")
			]	
		),
		.testTarget(
			name: "QuickLMDBTests",
			dependencies: ["QuickLMDB"]
		),
	]
)
