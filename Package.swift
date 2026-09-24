// swift-tools-version: 5.10
import PackageDescription

var products: [Product] = [
    .library(name: "SottoDuoAPI", targets: ["SottoDuoAPI"]),
    .executable(name: "sottoduo-server", targets: ["SottoDuoServer"]),
]
var targets: [Target] = [
    .target(name: "SottoDuoDomain", path: "Shared/Sources/SottoDuoDomain"),
    .target(name: "SottoDuoAPIWire", dependencies: [.product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"), .product(name: "HTTPTypes", package: "swift-http-types")], path: "Shared/Sources/SottoDuoAPIWire"),
    .target(name: "SottoDuoAPI", dependencies: ["SottoDuoDomain", "SottoDuoAPIWire"], path: "Shared/Sources/SottoDuoAPI"),
    .target(name: "SottoDuoServerKit", dependencies: ["SottoDuoAPI", "SottoDuoDomain", .product(name: "Hummingbird", package: "hummingbird"), .product(name: "Crypto", package: "swift-crypto")], path: "Server/Swift/Sources/SottoDuoServerKit"),
    .executableTarget(name: "SottoDuoServer", dependencies: ["SottoDuoServerKit"], path: "Server/Swift/Sources/SottoDuoServer"),
    .testTarget(name: "SottoDuoDomainTests", dependencies: ["SottoDuoDomain"], path: "Shared/Tests/SottoDuoDomainTests"),
    .testTarget(name: "SottoDuoAPITests", dependencies: ["SottoDuoAPI", "SottoDuoAPIWire"], path: "Shared/Tests/SottoDuoAPITests"),
    .testTarget(name: "SottoDuoServerTests", dependencies: ["SottoDuoServerKit", .product(name: "HummingbirdTesting", package: "hummingbird"), .product(name: "Crypto", package: "swift-crypto")], path: "Server/Swift/Tests/SottoDuoServerTests"),
]

#if os(macOS)
products += [
    .executable(name: "SottoDuo", targets: ["SottoDuo"]),
    .library(name: "SottoDuoCore", targets: ["SottoDuoCore"]),
]
targets += [
    .target(name: "SottoDuoCore", dependencies: ["SottoDuoDomain"], path: "Clients/macOS/Sources/SottoDuoCore"),
    .executableTarget(name: "SottoDuo", dependencies: ["SottoDuoCore", "SottoDuoAPI"], path: "Clients/macOS/Sources/SottoDuo"),
    .testTarget(name: "SottoDuoCoreTests", dependencies: ["SottoDuoCore"], path: "Clients/macOS/Tests/SottoDuoCoreTests"),
    .testTarget(name: "SottoDuoTests", dependencies: ["SottoDuo"], path: "Clients/macOS/Tests/SottoDuoTests"),
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
