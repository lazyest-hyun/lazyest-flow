import Darwin
import Foundation
import LazyestCore
import Security

enum PowerHelperInstaller {
  private enum InstallerError: LocalizedError {
    case administratorRequired
    case unexpectedExecutable(String)
    case invalidApplication(String)
    case commandFailed(String)
    case invalidCodeSignature

    var errorDescription: String? {
      switch self {
      case .administratorRequired:
        return "Administrator authorization is required."
      case .unexpectedExecutable(let path):
        return "Refusing helper maintenance from unexpected executable: \(path)"
      case .invalidApplication(let message):
        return "Installed application validation failed: \(message)"
      case .commandFailed(let message):
        return message
      case .invalidCodeSignature:
        return "Unable to read the installed application's code signature."
      }
    }
  }

  static var isInstalled: Bool {
    validRootOwnedFile(path: LazyestPowerHelper.installedExecutablePath, mode: 0o755)
      && validRootOwnedFile(path: LazyestPowerHelper.installedPlistPath, mode: 0o644)
  }

  static func requestInstall(completion: @escaping (Bool, String?) -> Void) {
    requestAdministratorCommand("--install-power-helper-as-root", completion: completion)
  }

  static func requestRemoval(completion: @escaping (Bool, String?) -> Void) {
    requestAdministratorCommand("--remove-power-helper-as-root", completion: completion)
  }

  static func installAsRoot() -> Int32 {
    do {
      try requireRootAndInstalledApplication()
      try verifyCode(at: LazyestPowerHelper.installedAppPath, deep: true)
      try verifyCode(at: LazyestPowerHelper.embeddedHelperPath, deep: false)
      let clientCDHash = try codeHash(at: LazyestPowerHelper.installedAppPath)
      let clientUserID = try consoleUserID()

      try restoreOwnedSleepState()
      try bootOutLoadedHelper()

      let fileManager = FileManager.default
      try fileManager.createDirectory(
        at: URL(fileURLWithPath: "/Library/PrivilegedHelperTools", isDirectory: true),
        withIntermediateDirectories: true
      )
      try fileManager.createDirectory(
        at: URL(fileURLWithPath: "/Library/LaunchDaemons", isDirectory: true),
        withIntermediateDirectories: true
      )

      try installHelperBinary(fileManager: fileManager)
      try installLaunchDaemonPlist(
        clientCDHash: clientCDHash,
        clientUserID: clientUserID,
        fileManager: fileManager
      )
      try runChecked(
        "/bin/launchctl",
        ["bootstrap", "system", LazyestPowerHelper.installedPlistPath]
      )
      return 0
    } catch {
      fputs("Power helper installation failed: \(error.localizedDescription)\n", stderr)
      return 1
    }
  }

  static func removeAsRoot() -> Int32 {
    do {
      try requireRootAndInstalledApplication()
      try restoreOwnedSleepState()
      try bootOutLoadedHelper()
      let fileManager = FileManager.default
      try removeIfPresent(
        path: LazyestPowerHelper.installedExecutablePath, fileManager: fileManager)
      try removeIfPresent(
        path: LazyestPowerHelper.installedPlistPath, fileManager: fileManager)
      try removeIfPresent(
        path: LazyestPowerHelper.ownedSleepMarkerPath, fileManager: fileManager)
      return 0
    } catch {
      fputs("Power helper removal failed: \(error.localizedDescription)\n", stderr)
      return 1
    }
  }

  private static func requestAdministratorCommand(
    _ argument: String,
    completion: @escaping (Bool, String?) -> Void
  ) {
    guard currentExecutablePath() == LazyestPowerHelper.installedFlowExecutablePath else {
      completion(false, "Install Lazyest Flow in /Applications first.")
      return
    }
    let allowedArguments = [
      "--install-power-helper-as-root",
      "--remove-power-helper-as-root",
    ]
    guard allowedArguments.contains(argument) else {
      completion(false, "Invalid helper maintenance action.")
      return
    }

    let executable = LazyestPowerHelper.installedFlowExecutablePath
      .replacingOccurrences(of: "'", with: "'\\''")
    let command = "'\(executable)' \(argument)"
    let script = "do shell script \"\(command)\" with administrator privileges"
    DispatchQueue.global(qos: .userInitiated).async {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
      process.arguments = ["-e", script]
      let errorPipe = Pipe()
      process.standardOutput = Pipe()
      process.standardError = errorPipe
      do {
        try process.run()
        process.waitUntilExit()
        let message = String(
          data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
        DispatchQueue.main.async {
          completion(
            process.terminationStatus == 0,
            message?.isEmpty == false ? message : nil
          )
        }
      } catch {
        DispatchQueue.main.async {
          completion(false, error.localizedDescription)
        }
      }
    }
  }

  private static func requireRootAndInstalledApplication() throws {
    guard geteuid() == 0 else { throw InstallerError.administratorRequired }
    let executablePath = currentExecutablePath()
    guard executablePath == LazyestPowerHelper.installedFlowExecutablePath else {
      throw InstallerError.unexpectedExecutable(executablePath ?? "unknown")
    }
  }

  private static func installHelperBinary(fileManager: FileManager) throws {
    let source = URL(fileURLWithPath: LazyestPowerHelper.embeddedHelperPath)
    let destination = URL(fileURLWithPath: LazyestPowerHelper.installedExecutablePath)
    let temporary = destination.deletingLastPathComponent().appendingPathComponent(
      ".\(LazyestPowerHelper.label).\(UUID().uuidString).tmp")
    defer { try? fileManager.removeItem(at: temporary) }

    try fileManager.copyItem(at: source, to: temporary)
    try setRootOwnedAttributes(path: temporary.path, mode: 0o755)
    try replaceAtomically(temporary: temporary.path, destination: destination.path)
    try setRootOwnedAttributes(path: destination.path, mode: 0o755)
    try verifyCode(at: destination.path, deep: false)
  }

  private static func installLaunchDaemonPlist(
    clientCDHash: String,
    clientUserID: uid_t,
    fileManager: FileManager
  ) throws {
    let values: [String: Any] = [
      "Label": LazyestPowerHelper.label,
      "ProgramArguments": [LazyestPowerHelper.installedExecutablePath],
      "MachServices": [LazyestPowerHelper.label: true],
      "EnvironmentVariables": [
        LazyestPowerHelper.clientAppPathEnvironment:
          LazyestPowerHelper.installedAppPath,
        LazyestPowerHelper.clientCDHashEnvironment: clientCDHash,
        LazyestPowerHelper.clientUserIDEnvironment: String(clientUserID),
      ],
      "ProcessType": "Background",
    ]
    let data = try PropertyListSerialization.data(
      fromPropertyList: values, format: .xml, options: 0)
    let destination = URL(fileURLWithPath: LazyestPowerHelper.installedPlistPath)
    let temporary = destination.deletingLastPathComponent().appendingPathComponent(
      ".\(LazyestPowerHelper.plistName).\(UUID().uuidString).tmp")
    defer { try? fileManager.removeItem(at: temporary) }

    try data.write(to: temporary, options: .atomic)
    try setRootOwnedAttributes(path: temporary.path, mode: 0o644)
    try replaceAtomically(temporary: temporary.path, destination: destination.path)
    try setRootOwnedAttributes(path: destination.path, mode: 0o644)
  }

  private static func replaceAtomically(temporary: String, destination: String) throws {
    guard Darwin.rename(temporary, destination) == 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
  }

  private static func restoreOwnedSleepState() throws {
    let marker = LazyestPowerHelper.ownedSleepMarkerPath
    guard FileManager.default.fileExists(atPath: marker) else { return }
    try runChecked("/usr/bin/pmset", ["-a", "disablesleep", "0"])
    try FileManager.default.removeItem(atPath: marker)
  }

  private static func bootOutLoadedHelper() throws {
    let serviceTarget = "system/\(LazyestPowerHelper.label)"
    guard run("/bin/launchctl", ["print", serviceTarget]).status == 0 else { return }
    try runChecked("/bin/launchctl", ["bootout", serviceTarget])
  }

  private static func removeIfPresent(path: String, fileManager: FileManager) throws {
    guard fileManager.fileExists(atPath: path) else { return }
    try fileManager.removeItem(atPath: path)
  }

  private static func verifyCode(at path: String, deep: Bool) throws {
    var arguments = ["--verify", "--strict"]
    if deep { arguments.append("--deep") }
    arguments.append(path)
    let result = run("/usr/bin/codesign", arguments)
    guard result.status == 0 else {
      throw InstallerError.invalidApplication(
        result.error.isEmpty ? "codesign verification failed" : result.error)
    }
  }

  private static func codeHash(at path: String) throws -> String {
    var code: SecStaticCode?
    guard
      SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code)
        == errSecSuccess,
      let code
    else {
      throw InstallerError.invalidCodeSignature
    }
    var information: CFDictionary?
    guard
      SecCodeCopySigningInformation(
        code, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
        == errSecSuccess,
      let values = information as? [CFString: Any],
      let hash = values[kSecCodeInfoUnique] as? Data,
      !hash.isEmpty
    else {
      throw InstallerError.invalidCodeSignature
    }
    return hash.map { String(format: "%02x", $0) }.joined()
  }

  private static func consoleUserID() throws -> uid_t {
    let attributes = try FileManager.default.attributesOfItem(atPath: "/dev/console")
    guard
      let value = attributes[.ownerAccountID] as? NSNumber,
      value.uint32Value > 0
    else {
      throw InstallerError.invalidApplication("Unable to identify the console user.")
    }
    return uid_t(value.uint32Value)
  }

  private static func validRootOwnedFile(path: String, mode: Int) -> Bool {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else {
      return false
    }
    let owner = (attributes[.ownerAccountID] as? NSNumber)?.intValue
    let group = (attributes[.groupOwnerAccountID] as? NSNumber)?.intValue
    let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
    return attributes[.type] as? FileAttributeType == .typeRegular
      && owner == 0 && group == 0 && permissions == mode
  }

  private static func setRootOwnedAttributes(path: String, mode: Int) throws {
    try FileManager.default.setAttributes(
      [
        .ownerAccountID: NSNumber(value: 0),
        .groupOwnerAccountID: NSNumber(value: 0),
        .posixPermissions: NSNumber(value: mode),
      ],
      ofItemAtPath: path
    )
  }

  private static func currentExecutablePath() -> String? {
    var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
    guard proc_pidpath(getpid(), &buffer, UInt32(buffer.count)) > 0 else { return nil }
    return URL(fileURLWithPath: String(cString: buffer)).resolvingSymlinksInPath().path
  }

  @discardableResult
  private static func runChecked(_ path: String, _ arguments: [String]) throws -> CommandResult {
    let result = run(path, arguments)
    guard result.status == 0 else {
      throw InstallerError.commandFailed(
        result.error.isEmpty ? "\(path) failed with status \(result.status)" : result.error)
    }
    return result
  }

  private struct CommandResult {
    let status: Int32
    let error: String
  }

  private static func run(_ path: String, _ arguments: [String]) -> CommandResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    process.standardOutput = Pipe()
    let errorPipe = Pipe()
    process.standardError = errorPipe
    do {
      try process.run()
      process.waitUntilExit()
    } catch {
      return CommandResult(status: 1, error: error.localizedDescription)
    }
    let message =
      String(
        data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8
      )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return CommandResult(status: process.terminationStatus, error: message)
  }
}
