// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "bowtie-swift-corvus-json-schema",
    dependencies: [
        // The implementation under test: Dependabot keeps it (and Package.resolved) at the latest release.
        .package(url: "https://github.com/corvus-dotnet/corvus-json-schema-swift", exact: "0.1.0"),
    ],
    targets: [
        .executableTarget(
            name: "BowtieCorvusJsonSchema",
            dependencies: [.product(name: "CorvusJsonSchema", package: "corvus-json-schema-swift")]
        ),
    ]
)
