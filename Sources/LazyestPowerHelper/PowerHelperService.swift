import Darwin
import Foundation
import LazyestCore
import OSLog
import Security

private let powerHelperLogger = Logger(
  subsystem: LazyestPowerHelper.label,
  category: "runtime"
)

final class PowerHelperListenerDelegate: NSObject, NSXPCListenerDelegate {
  private let service = PowerHelperService()

  func listener(
    _ listener: NSXPCListener,
    shouldAcceptNewConnection connection: NSXPCConnection
  ) -> Bool {
    guard PowerHelperConnectionValidator.isTrusted(connection) else {
      powerHelperLogger.error("Rejected untrusted power helper client")
      return false
    }
    powerHelperLogger.info("Accepted power helper client")
    connection.exportedInterface = NSXPCInterface(with: LazyestPowerHelperProtocol.self)
    connection.exportedObject = service
    connection.resume()
    return true
  }
}

enum PowerHelperConnectionValidator {
  static var runtimeConfigurationIsValid: Bool {
    guard
      currentExecutablePath(processIdentifier: getpid())
        == LazyestPowerHelper.installedExecutablePath,
      expectedApplicationPath == LazyestPowerHelper.installedAppPath,
      expectedUserID != nil,
      let expectedCDHash,
      expectedCDHash.count == 40,
      expectedCDHash.allSatisfy({ $0.isHexDigit }),
      let applicationCode = staticCode(at: LazyestPowerHelper.installedAppPath),
      SecStaticCodeCheckValidity(applicationCode, [], nil) == errSecSuccess,
      signingIdentifier(for: applicationCode)
        == LazyestPowerHelper.agentBundleIdentifier,
      codeHash(for: applicationCode) == expectedCDHash
    else {
      return false
    }
    return true
  }

  static func isTrusted(_ connection: NSXPCConnection) -> Bool {
    guard runtimeConfigurationIsValid else {
      powerHelperLogger.error("Client rejected: invalid runtime configuration")
      return false
    }
    guard connection.effectiveUserIdentifier == expectedUserID else {
      powerHelperLogger.error("Client rejected: unexpected user")
      return false
    }
    guard
      currentExecutablePath(processIdentifier: connection.processIdentifier)
        == LazyestPowerHelper.installedFlowExecutablePath
    else {
      powerHelperLogger.error("Client rejected: unexpected executable path")
      return false
    }
    guard let expectedCDHash else {
      powerHelperLogger.error("Client rejected: missing expected code hash")
      return false
    }
    guard let guestCode = guestCode(processIdentifier: connection.processIdentifier) else {
      powerHelperLogger.error("Client rejected: running code unavailable")
      return false
    }
    let validity = SecCodeCheckValidity(guestCode, [], nil)
    guard validity == errSecSuccess else {
      powerHelperLogger.error(
        "Client rejected: running code invalid (\(validity, privacy: .public))")
      return false
    }
    guard let guestStaticCode = staticCode(for: guestCode) else {
      powerHelperLogger.error("Client rejected: static code unavailable")
      return false
    }
    guard
      signingIdentifier(for: guestStaticCode)
        == LazyestPowerHelper.agentBundleIdentifier
    else {
      powerHelperLogger.error("Client rejected: bundle identifier mismatch")
      return false
    }
    guard codeHash(for: guestStaticCode) == expectedCDHash else {
      powerHelperLogger.error("Client rejected: code hash mismatch")
      return false
    }
    return true
  }

  private static var expectedApplicationPath: String? {
    ProcessInfo.processInfo.environment[LazyestPowerHelper.clientAppPathEnvironment]
  }

  private static var expectedCDHash: String? {
    ProcessInfo.processInfo.environment[LazyestPowerHelper.clientCDHashEnvironment]?
      .lowercased()
  }

  private static var expectedUserID: uid_t? {
    guard
      let value = ProcessInfo.processInfo.environment[
        LazyestPowerHelper.clientUserIDEnvironment],
      let parsed = UInt32(value),
      parsed > 0
    else {
      return nil
    }
    return uid_t(parsed)
  }

  private static func staticCode(at path: String) -> SecStaticCode? {
    var code: SecStaticCode?
    guard
      SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code)
        == errSecSuccess
    else {
      return nil
    }
    return code
  }

  private static func staticCode(for code: SecCode) -> SecStaticCode? {
    var staticCode: SecStaticCode?
    guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess else {
      return nil
    }
    return staticCode
  }

  private static func currentExecutablePath(processIdentifier: pid_t) -> String? {
    var path = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
    guard proc_pidpath(processIdentifier, &path, UInt32(path.count)) > 0 else { return nil }
    return URL(fileURLWithPath: String(cString: path)).resolvingSymlinksInPath().path
  }

  private static func signingInformation(for code: SecStaticCode) -> [CFString: Any]? {
    var information: CFDictionary?
    guard
      SecCodeCopySigningInformation(
        code, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
        == errSecSuccess,
      let values = information as? [CFString: Any]
    else {
      return nil
    }
    return values
  }

  private static func signingIdentifier(for code: SecStaticCode) -> String? {
    signingInformation(for: code)?[kSecCodeInfoIdentifier] as? String
  }

  private static func codeHash(for code: SecStaticCode) -> String? {
    guard let hash = signingInformation(for: code)?[kSecCodeInfoUnique] as? Data else {
      return nil
    }
    return hash.map { String(format: "%02x", $0) }.joined()
  }

  private static func guestCode(processIdentifier: pid_t) -> SecCode? {
    let attributes = [kSecGuestAttributePid: NSNumber(value: processIdentifier)] as CFDictionary
    var code: SecCode?
    guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess else {
      return nil
    }
    return code
  }
}

final class PowerHelperService: NSObject, LazyestPowerHelperProtocol {
  private let queue = DispatchQueue(label: "com.estaid.mac-bootstrap-agent.power-helper.state")
  private let markerURL = URL(
    fileURLWithPath: LazyestPowerHelper.ownedSleepMarkerPath)
  private var lastHeartbeat = Date.distantPast
  private var keepAwake = false
  private var ownsSleepDisabled = false
  private var watchdogTimer: DispatchSourceTimer?

  override init() {
    super.init()
    queue.sync {
      restoreStaleOwnedState()
      startWatchdog()
    }
  }

  func setSleepDisabled(
    _ enabled: Bool,
    withReply reply: @escaping (Bool, String?) -> Void
  ) {
    queue.async {
      let result = enabled ? self.enableSleepDisabled() : self.disableOwnedSleepDisabled()
      if result.ok {
        powerHelperLogger.info("Set sleep disabled: \(enabled, privacy: .public)")
      } else {
        powerHelperLogger.error(
          "Could not set sleep disabled: \(result.error ?? "unknown error", privacy: .public)"
        )
      }
      reply(result.ok, result.error)
    }
  }

  func getSleepDisabled(withReply reply: @escaping (Bool) -> Void) {
    queue.async {
      reply(Self.isSleepDisabled())
    }
  }

  func heartbeat(withReply reply: @escaping (Bool) -> Void) {
    queue.async {
      guard self.keepAwake else {
        reply(false)
        return
      }
      self.lastHeartbeat = Date()
      reply(true)
    }
  }

  func version(withReply reply: @escaping (String) -> Void) {
    reply(LazyestPowerHelper.protocolVersion)
  }

  private func enableSleepDisabled() -> (ok: Bool, error: String?) {
    if keepAwake {
      lastHeartbeat = Date()
      return (true, nil)
    }

    if Self.isSleepDisabled() {
      keepAwake = true
      ownsSleepDisabled = FileManager.default.fileExists(atPath: markerURL.path)
      lastHeartbeat = Date()
      return (true, nil)
    }

    let result = Self.runPmset(disableSleep: true)
    guard result.ok else { return result }
    do {
      try Data().write(to: markerURL, options: .atomic)
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o600], ofItemAtPath: markerURL.path)
    } catch {
      _ = Self.runPmset(disableSleep: false)
      return (false, "Unable to create the sleep safety marker: \(error.localizedDescription)")
    }

    ownsSleepDisabled = true
    keepAwake = true
    lastHeartbeat = Date()
    return (true, nil)
  }

  private func disableOwnedSleepDisabled() -> (ok: Bool, error: String?) {
    let ownsCurrentState =
      ownsSleepDisabled || FileManager.default.fileExists(atPath: markerURL.path)
    if ownsCurrentState {
      let result = Self.runPmset(disableSleep: false)
      guard result.ok else { return result }
      try? FileManager.default.removeItem(at: markerURL)
    }
    ownsSleepDisabled = false
    keepAwake = false
    lastHeartbeat = .distantPast
    return (true, nil)
  }

  private func restoreStaleOwnedState() {
    guard FileManager.default.fileExists(atPath: markerURL.path) else { return }
    let result = Self.runPmset(disableSleep: false)
    if result.ok {
      try? FileManager.default.removeItem(at: markerURL)
    }
    ownsSleepDisabled = false
    keepAwake = false
  }

  private func startWatchdog() {
    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now() + 15, repeating: 15)
    timer.setEventHandler { [weak self] in
      guard let self, self.keepAwake else { return }
      if Date().timeIntervalSince(self.lastHeartbeat) > LazyestPowerHelper.watchdogTimeout {
        _ = self.disableOwnedSleepDisabled()
      }
    }
    timer.resume()
    watchdogTimer = timer
  }

  private static func isSleepDisabled() -> Bool {
    guard let output = capture("/usr/bin/pmset", ["-g"]) else { return false }
    return output.split(separator: "\n").contains { line in
      let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
      return fields.count >= 2
        && fields[0].lowercased() == "sleepdisabled"
        && fields[1] == "1"
    }
  }

  private static func runPmset(disableSleep: Bool) -> (ok: Bool, error: String?) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    process.arguments = ["-a", "disablesleep", disableSleep ? "1" : "0"]
    let errorPipe = Pipe()
    process.standardError = errorPipe
    do {
      try process.run()
      process.waitUntilExit()
    } catch {
      return (false, error.localizedDescription)
    }
    guard process.terminationStatus == 0 else {
      let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
      let message = String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
      return (false, message?.isEmpty == false ? message : "pmset failed")
    }
    return (true, nil)
  }

  private static func capture(_ path: String, _ arguments: [String]) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    let outputPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = Pipe()
    do {
      try process.run()
      process.waitUntilExit()
    } catch {
      return nil
    }
    return String(
      data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
  }
}
