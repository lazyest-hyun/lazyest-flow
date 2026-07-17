import Foundation

enum DockAutoHideTimingMode: Equatable {
  case systemDefault
  case fast
  case custom(delay: Double?, animationDuration: Double?)
}

enum DockAutoHideTiming {
  static let fastDelay = 0.0
  static let fastAnimationDuration = 0.15

  static func currentMode() -> DockAutoHideTimingMode {
    let delay = readValue(named: "autohide-delay")
    let animationDuration = readValue(named: "autohide-time-modifier")

    guard delay != nil || animationDuration != nil else { return .systemDefault }
    if delay == fastDelay, animationDuration == fastAnimationDuration { return .fast }
    return .custom(delay: delay, animationDuration: animationDuration)
  }

  static func setFastEnabled(_ enabled: Bool) throws {
    if enabled {
      try run(
        "/usr/bin/defaults",
        ["write", "com.apple.dock", "autohide-delay", "-float", String(fastDelay)]
      )
      try run(
        "/usr/bin/defaults",
        [
          "write", "com.apple.dock", "autohide-time-modifier", "-float",
          String(fastAnimationDuration),
        ]
      )
    } else {
      // Missing keys are already the macOS default, so each deletion is optional.
      _ = try? run("/usr/bin/defaults", ["delete", "com.apple.dock", "autohide-delay"])
      _ = try? run(
        "/usr/bin/defaults", ["delete", "com.apple.dock", "autohide-time-modifier"])
    }
    try run("/usr/bin/killall", ["Dock"])
  }

  private static func readValue(named key: String) -> Double? {
    guard let output = try? run("/usr/bin/defaults", ["read", "com.apple.dock", key]) else {
      return nil
    }
    return Double(output.trimmingCharacters(in: .whitespacesAndNewlines))
  }

  @discardableResult
  private static func run(_ launchPath: String, _ arguments: [String]) throws -> String {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = arguments
    process.standardOutput = output
    process.standardError = Pipe()
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw CocoaError(.executableNotLoadable) }
    return String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
  }
}
