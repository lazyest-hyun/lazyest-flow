import Darwin
import Foundation
import MacBootstrapCore
import ServiceManagement

enum LoginLaunchStatus: Equatable {
  case disabled
  case enabled
  case requiresApproval
  case needsRepair
  case appNotInstalled
}

enum LoginLaunchError: LocalizedError {
  case appNotInstalled
  case unsafeLaunchAgentsDirectory
  case unsafePropertyList
  case commandFailed(String)
  case verificationFailed

  var errorDescription: String? {
    switch self {
    case .appNotInstalled:
      return "MacBootstrapAgent.app is not installed in /Applications."
    case .unsafeLaunchAgentsDirectory:
      return "The user LaunchAgents directory is not a safe local directory."
    case .unsafePropertyList:
      return "The legacy login item property list is not owned by MacBootstrapAgent."
    case .commandFailed(let message):
      return message.isEmpty ? "launchctl could not remove the legacy login item." : message
    case .verificationFailed:
      return "The login item state could not be verified."
    }
  }
}

final class LoginLaunchManager {
  static let shared = LoginLaunchManager()

  private let fileManager: FileManager
  private let userID: uid_t
  private let legacyPropertyListURL: URL

  init(
    fileManager: FileManager = .default,
    userID: uid_t = getuid(),
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
  ) {
    self.fileManager = fileManager
    self.userID = userID
    self.legacyPropertyListURL =
      homeDirectory
      .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
      .appendingPathComponent("\(LegacyLoginLaunchPolicy.label).plist", isDirectory: false)
  }

  var status: LoginLaunchStatus {
    guard
      fileManager.isExecutableFile(
        atPath: LegacyLoginLaunchPolicy.installedAgentExecutablePath)
    else { return legacyRegistrationExists ? .needsRepair : .appNotInstalled }

    switch SMAppService.mainApp.status {
    case .enabled:
      return legacyRegistrationExists ? .needsRepair : .enabled
    case .requiresApproval:
      return .requiresApproval
    case .notRegistered:
      return legacyRegistrationExists ? .needsRepair : .disabled
    case .notFound:
      return legacyRegistrationExists ? .needsRepair : .disabled
    @unknown default:
      return .needsRepair
    }
  }

  func setEnabled(_ enabled: Bool, refreshRegistration: Bool = false) throws {
    if enabled {
      try enable(refreshRegistration: refreshRegistration)
    } else {
      try disable()
    }
  }

  func migrateLegacyRegistrationIfNeeded() {
    guard legacyRegistrationExists else { return }
    do {
      try enable(refreshRegistration: false)
    } catch {
      NSLog("Login item migration was not completed: \(error.localizedDescription)")
    }
  }

  func openSystemSettings() {
    SMAppService.openSystemSettingsLoginItems()
  }

  private func enable(refreshRegistration: Bool) throws {
    guard
      fileManager.isExecutableFile(
        atPath: LegacyLoginLaunchPolicy.installedAgentExecutablePath)
    else { throw LoginLaunchError.appNotInstalled }

    let service = SMAppService.mainApp
    if refreshRegistration, service.status == .enabled {
      try service.unregister()
    }
    if service.status == .notRegistered || service.status == .notFound {
      try service.register()
    }

    switch service.status {
    case .enabled, .requiresApproval:
      try removeLegacyRegistration()
    case .notRegistered, .notFound:
      throw LoginLaunchError.verificationFailed
    @unknown default:
      throw LoginLaunchError.verificationFailed
    }
  }

  private func disable() throws {
    let service = SMAppService.mainApp
    if service.status == .enabled || service.status == .requiresApproval {
      try service.unregister()
    }
    try removeLegacyRegistration()
    guard service.status == .notRegistered || service.status == .notFound,
      !legacyRegistrationExists
    else {
      throw LoginLaunchError.verificationFailed
    }
  }

  private var legacyDomain: String {
    "gui/\(userID)"
  }

  private var legacyServiceTarget: String {
    "\(legacyDomain)/\(LegacyLoginLaunchPolicy.label)"
  }

  private var legacyServiceIsRegistered: Bool {
    (try? launchctl(["print", legacyServiceTarget], includeError: false)) != nil
  }

  private var legacyRegistrationExists: Bool {
    fileManager.fileExists(atPath: legacyPropertyListURL.path) || legacyServiceIsRegistered
  }

  private func removeLegacyRegistration() throws {
    try validateLegacyLaunchAgentsDirectory()
    try validateLegacyPropertyList()
    if legacyServiceIsRegistered {
      try launchctl(["bootout", legacyServiceTarget])
    }
    if fileManager.fileExists(atPath: legacyPropertyListURL.path) {
      try fileManager.removeItem(at: legacyPropertyListURL)
    }
    guard !legacyRegistrationExists else { throw LoginLaunchError.verificationFailed }
  }

  private func validateLegacyLaunchAgentsDirectory() throws {
    let directory = legacyPropertyListURL.deletingLastPathComponent()
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory) else { return }
    let values = try directory.resourceValues(forKeys: [.isSymbolicLinkKey])
    guard isDirectory.boolValue, values.isSymbolicLink != true else {
      throw LoginLaunchError.unsafeLaunchAgentsDirectory
    }
  }

  private func validateLegacyPropertyList() throws {
    guard fileManager.fileExists(atPath: legacyPropertyListURL.path) else { return }
    let values = try legacyPropertyListURL.resourceValues(
      forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
    guard values.isRegularFile == true, values.isSymbolicLink != true,
      try isManagedLegacyPropertyList()
    else { throw LoginLaunchError.unsafePropertyList }
  }

  private func isManagedLegacyPropertyList() throws -> Bool {
    let attributes = try fileManager.attributesOfItem(atPath: legacyPropertyListURL.path)
    guard let size = attributes[.size] as? NSNumber, size.intValue <= 64 * 1024 else {
      return false
    }
    let data = try Data(contentsOf: legacyPropertyListURL, options: .mappedIfSafe)
    let value = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
    return LegacyLoginLaunchPolicy.isManagedPropertyList(value)
  }

  @discardableResult
  private func launchctl(_ arguments: [String], includeError: Bool = true) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    let errorPipe = Pipe()
    process.standardError = includeError ? errorPipe : FileHandle.nullDevice
    try process.run()
    let errorData = includeError ? errorPipe.fileHandleForReading.readDataToEndOfFile() : Data()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      let message = String(decoding: errorData, as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      throw LoginLaunchError.commandFailed(message)
    }
    return ""
  }
}

enum LoginLaunchMaintenance {
  static func setEnabled(_ enabled: Bool, refreshRegistration: Bool = false) -> Int32 {
    do {
      try LoginLaunchManager.shared.setEnabled(
        enabled, refreshRegistration: refreshRegistration)
      return 0
    } catch {
      fputs("Login launch update failed: \(error.localizedDescription)\n", stderr)
      return 1
    }
  }

  static func statusText() -> String {
    switch LoginLaunchManager.shared.status {
    case .disabled:
      return "disabled"
    case .enabled:
      return "enabled"
    case .requiresApproval:
      return "requires-approval"
    case .needsRepair:
      return "needs-repair"
    case .appNotInstalled:
      return "app-not-installed"
    }
  }

  static func isEnabled() -> Int32 {
    LoginLaunchManager.shared.status == .enabled ? 0 : 1
  }
}
