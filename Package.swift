// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BeatTrainMPC",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "beattrain", targets: ["beattrain"]),
        .executable(name: "beattrain-hwtest", targets: ["beattrain-hwtest"]),
    ],
    targets: [
        // Pure game logic, independent of the MPC hardware (Foundation only).
        .target(name: "BeatTrainCore"),
        // Minimal C shims for the Linux kernel interfaces (DRM/KMS).
        .target(name: "CMPCHardware"),
        // Display, control surface and renderer for the MPC Sample.
        .target(name: "MPCHardware", dependencies: ["CMPCHardware"]),
        // The game on the MPC Sample.
        .executableTarget(name: "beattrain", dependencies: ["BeatTrainCore", "MPCHardware"]),
        .executableTarget(name: "beattrain-hwtest", dependencies: ["MPCHardware"]),
        .testTarget(name: "BeatTrainCoreTests", dependencies: ["BeatTrainCore"]),
        .testTarget(name: "MPCHardwareTests", dependencies: ["MPCHardware"]),
        .testTarget(name: "BeatTrainAppTests", dependencies: ["beattrain"]),
    ]
)
