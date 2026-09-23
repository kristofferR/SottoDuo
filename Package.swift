// swift-tools-version: 5.10
import PackageDescription

var products: [Product] = [
    .library(name: "SottoDuoAPI", targets: ["SottoDuoAPI"]),
    .executable(name: "sottoduo-server", targets: ["SottoDuoServer"]),
]
var targets: [Target] = [
    .target(name: "SottoDuoDomain"),
    .target(name: "SottoDuoAPIWire", dependencies: [.product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"), .product(name: "HTTPTypes", package: "swift-http-types")]),
    .target(name: "SottoDuoAPI", dependencies: ["SottoDuoDomain", "SottoDuoAPIWire"]),
    .target(name: "SottoDuoServerKit", dependencies: ["SottoDuoAPI", "SottoDuoDomain", .product(name: "Hummingbird", package: "hummingbird"), .product(name: "Crypto", package: "swift-crypto")]),
    .executableTarget(name: "SottoDuoServer", dependencies: ["SottoDuoServerKit"]),
    .testTarget(name: "SottoDuoDomainTests", dependencies: ["SottoDuoDomain"]),
    .testTarget(name: "SottoDuoAPITests", dependencies: ["SottoDuoAPI", "SottoDuoAPIWire"]),
    .testTarget(name: "SottoDuoServerTests", dependencies: ["SottoDuoServerKit", .product(name: "HummingbirdTesting", package: "hummingbird"), .product(name: "Crypto", package: "swift-crypto")]),
]

#if os(macOS)
products += [
    .executable(name: "SottoDuo", targets: ["SottoDuo"]),
    .library(name: "SottoDuoCore", targets: ["SottoDuoCore"]),
]
targets += [
    .target(name: "SottoDuoCore", dependencies: ["SottoDuoDomain"]),
    .executableTarget(name: "SottoDuo", dependencies: ["SottoDuoCore", "SottoDuoAPI"]),
    .testTarget(name: "SottoDuoCoreTests", dependencies: ["SottoDuoCore"]),
    .testTarget(name: "SottoDuoTests", dependencies: ["SottoDuo"]),
]
#endif

let package = Package(
    name: "SottoDuo",
    platforms: [.macOS(.v14)],
    products: products,
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "4.0.0"),
        .package(url: "https://github.com/apple/swift-openapi-runtime.git", exact: "1.11.0"),
        .package(url: "https://github.com/apple/swift-http-types.git", from: "1.0.0"),
    ],
    targets: targets,
    swiftLanguageVersions: [.v5]
)
