// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "MacBootstrapAgent",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .executable(name: "MacBootstrapAgent", targets: ["MacBootstrapAgent"]),
    .executable(name: "MacBootstrapPowerHelper", targets: ["MacBootstrapPowerHelper"]),
    .executable(name: "MacBootstrapCoreChecks", targets: ["MacBootstrapCoreChecks"]),
  ],
  targets: [
    .target(name: "MacBootstrapCore"),
    .executableTarget(name: "MacBootstrapAgent", dependencies: ["MacBootstrapCore"]),
    .executableTarget(
      name: "MacBootstrapPowerHelper",
      dependencies: ["MacBootstrapCore"],
      exclude: ["Info.plist"],
      linkerSettings: [
        .unsafeFlags([
          "-Xlinker", "-sectcreate",
          "-Xlinker", "__TEXT",
          "-Xlinker", "__info_plist",
          "-Xlinker", "Sources/MacBootstrapPowerHelper/Info.plist",
        ])
      ]
    ),
    .executableTarget(
      name: "MacBootstrapCoreChecks",
      dependencies: ["MacBootstrapCore"],
      path: "Checks/MacBootstrapCoreChecks"
    ),
  ]
)
