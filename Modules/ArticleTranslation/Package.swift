// swift-tools-version:6.2
import PackageDescription

let package = Package(
	name: "ArticleTranslation",
	platforms: [.macOS(.v15), .iOS(.v17)],
	products: [
		.library(
			name: "ArticleTranslation",
			type: .dynamic,
			targets: ["ArticleTranslation"])
	],
	dependencies: [
		.package(path: "../RSWeb")
	],
	targets: [
		.target(
			name: "ArticleTranslation",
			dependencies: ["RSWeb"],
			swiftSettings: [
				.unsafeFlags(["-warnings-as-errors"]),
				.enableUpcomingFeature("NonisolatedNonsendingByDefault"),
				.enableUpcomingFeature("InferIsolatedConformances")
			]
		),
		.testTarget(
			name: "ArticleTranslationTests",
			dependencies: ["ArticleTranslation"])
	]
)
