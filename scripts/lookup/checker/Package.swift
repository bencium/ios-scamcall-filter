// swift-tools-version: 6.1
// Asks a lookup server, exactly as iOS would, whether given numbers are blocked.
import PackageDescription

let package = Package(
    name: "CheckLookup",
    platforms: [.macOS(.v15)],
    dependencies: [
        // Same commit as server/Dockerfile, so client and server speak the same protocol.
        .package(url: "https://github.com/apple/live-caller-id-lookup-example.git",
                 revision: "87e080a9262c8c9d728c6a20de5baf708fbae1fa"),
        .package(url: "https://github.com/apple/swift-homomorphic-encryption", branch: "release/1.1"),
        .package(url: "https://github.com/hummingbird-project/hummingbird", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-http-types.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(name: "CheckLookup", dependencies: [
            .product(name: "PIRServiceTesting", package: "live-caller-id-lookup-example"),
            .product(name: "PrivateInformationRetrieval", package: "swift-homomorphic-encryption"),
            .product(name: "HomomorphicEncryption", package: "swift-homomorphic-encryption"),
            .product(name: "Hummingbird", package: "hummingbird"),
            .product(name: "HummingbirdTesting", package: "hummingbird"),
            .product(name: "HTTPTypes", package: "swift-http-types"),
            .product(name: "NIOCore", package: "swift-nio"),
        ]),
    ])
