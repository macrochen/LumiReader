// swift-tools-version:5.5
import PackageDescription
@import GTMSessionFetcher;


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
        .package(url: "https://github.com/google/GoogleSignIn-iOS.git", from: "7.0.0"),
        .package(url: "https://github.com/google/google-api-objectivec-client-for-rest.git", from: "3.0.0"),
        .package(url: "https://github.com/google/gtm-session-fetcher.git", from: "4.5.0")
    ],
    targets: [
        .target(
            name: "LumiReader",
            dependencies: [
                .product(name: "GoogleSignIn", package: "GoogleSignIn-iOS"),
                .product(name: "GoogleAPIClientForREST_Drive", package: "google-api-objectivec-client-for-rest"),
                .product(name: "GTMSessionFetcher", package: "gtm-session-fetcher")
            ]),
        .testTarget(
            name: "LumiReaderTests",
            dependencies: ["LumiReader"]),
    ]
)