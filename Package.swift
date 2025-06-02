// swift-tools-version:5.5
// import PackageDescription
// @import GTMSessionFetcher;


let package = Package(
    name: "LumiReader",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "LumiReader",
            targets: ["LumiReader"]),
    ],
    dependencies: [
        // Remove GCDWebServer dependency
    ],
    targets: [
        .target(
            name: "LumiReader",
            dependencies: [
                // Remove GCDWebServer product dependency
            ]),
        .testTarget(
            name: "LumiReaderTests",
            dependencies: ["LumiReader"]),
    ]
)