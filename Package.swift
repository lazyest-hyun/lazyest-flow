// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "LazyestFlow",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .executable(name: "LazyestFlow", targets: ["LazyestFlow"]),
    .executable(name: "LazyestPowerHelper", targets: ["LazyestPowerHelper"]),
    .executable(name: "LazyestCoreChecks", targets: ["LazyestCoreChecks"]),
  ],
  targets: [
    .target(name: "LazyestCore"),
    .executableTarget(name: "LazyestFlow", dependencies: ["LazyestCore"]),
    .executableTarget(
      name: "LazyestPowerHelper",
      dependencies: ["LazyestCore"],
      exclude: ["Info.plist"],
      linkerSettings: [
        .unsafeFlags([
          "-Xlinker", "-sectcreate",
          "-Xlinker", "__TEXT",
          "-Xlinker", "__info_plist",
          "-Xlinker", "Sources/LazyestPowerHelper/Info.plist",
        ])
      ]
    ),
    .executableTarget(
      name: "LazyestCoreChecks",
      dependencies: ["LazyestCore"],
      path: "Checks/LazyestCoreChecks"
    ),
  ]
)
