import Darwin
import Foundation
import IOKit.ps
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
      geteuid() == 0,
      installationConfigurationIsRootOwned,
      currentExecutablePath(processIdentifier: getpid())
        == LazyestPowerHelper.installedExecutablePath,
      expectedApplicationPath == LazyestPowerHelper.installedAppPath,
      expectedUserID != nil,
      expectedClientCDHash != nil,
      let applicationCode = staticCode(at: LazyestPowerHelper.installedAppPath),
      SecStaticCodeCheckValidity(applicationCode, [], nil) == errSecSuccess,
      signingIdentifier(for: applicationCode)
        == LazyestPowerHelper.agentBundleIdentifier,
      codeHash(for: applicationCode) == expectedClientCDHash,
      let helperCode = staticCode(at: LazyestPowerHelper.installedExecutablePath),
      SecStaticCodeCheckValidity(helperCode, [], nil) == errSecSuccess,
      signingIdentifier(for: helperCode) == LazyestPowerHelper.label,
      teamIdentifier(for: helperCode) == teamIdentifier(for: applicationCode),
      let embeddedHelperCode = staticCode(at: LazyestPowerHelper.embeddedHelperPath),
      SecStaticCodeCheckValidity(embeddedHelperCode, [], nil) == errSecSuccess,
      codeHash(for: helperCode) == codeHash(for: embeddedHelperCode)
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
    guard
      let applicationCode = staticCode(at: LazyestPowerHelper.installedAppPath),
      codeHash(for: guestStaticCode) == expectedClientCDHash,
      teamIdentifier(for: guestStaticCode) == teamIdentifier(for: applicationCode)
    else {
      powerHelperLogger.error("Client rejected: signing team mismatch")
      return false
    }
    return true
  }

  private static var installationConfigurationIsRootOwned: Bool {
    guard
      let values = try? FileManager.default.attributesOfItem(
        atPath: LazyestPowerHelper.installedPlistPath
      )
    else { return false }
    return values[.type] as? FileAttributeType == .typeRegular
      && (values[.ownerAccountID] as? NSNumber)?.intValue == 0
      && (values[.groupOwnerAccountID] as? NSNumber)?.intValue == 0
      && (values[.posixPermissions] as? NSNumber)?.intValue == 0o644
  }

  private static var expectedClientCDHash: String? {
    guard
      let hash = ProcessInfo.processInfo.environment[LazyestPowerHelper.clientCDHashEnvironment],
      hash.count == 40, hash.allSatisfy({ $0.isHexDigit })
    else { return nil }
    return hash.lowercased()
  }

  private static func codeHash(for code: SecStaticCode) -> String? {
    guard let hash = signingInformation(for: code)?[kSecCodeInfoUnique] as? Data, !hash.isEmpty
    else { return nil }
    return hash.map { String(format: "%02x", $0) }.joined()
  }

  private static var expectedApplicationPath: String? {
    ProcessInfo.processInfo.environment[LazyestPowerHelper.clientAppPathEnvironment]
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

  private static func teamIdentifier(for code: SecStaticCode) -> String? {
    signingInformation(for: code)?[kSecCodeInfoTeamIdentifier] as? String
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
  private let queue = DispatchQueue(label: "\(LazyestPowerHelper.label).state")
  private let markerURL = URL(
    fileURLWithPath: LazyestPowerHelper.ownedSleepMarkerPath)
  private var lastHeartbeatUptime: TimeInterval = 0
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
      let result = self.withSleepSettingLock {
        enabled ? self.enableSleepDisabled() : self.disableOwnedSleepDisabled()
      }
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
      let result = self.withSleepSettingLock {
        guard self.keepAwake, Self.powerSafetyAllowsKeepAwake else {
          _ = self.disableOwnedSleepDisabled()
          return (false, "Sleep prevention lease or power safety expired.")
        }
        if !Self.isSleepDisabled() {
          let enableResult = self.enableSleepDisabled()
          guard enableResult.ok else { return enableResult }
        }
        self.lastHeartbeatUptime = ProcessInfo.processInfo.systemUptime
        return (true, nil)
      }
      reply(result.ok)
    }
  }

  func version(withReply reply: @escaping (String) -> Void) {
    reply(LazyestPowerHelper.protocolVersion)
  }

  private func enableSleepDisabled() -> (ok: Bool, error: String?) {
    guard Self.powerSafetyAllowsKeepAwake else {
      _ = disableOwnedSleepDisabled()
      return (false, "Sleep prevention paused for battery or temperature safety.")
    }
    guard let sleepDisabled = Self.readSleepDisabled() else {
      return (false, "Unable to read the current system sleep setting.")
    }
    if keepAwake && sleepDisabled {
      lastHeartbeatUptime = ProcessInfo.processInfo.systemUptime
      return (true, nil)
    }

    if sleepDisabled {
      guard FileManager.default.fileExists(atPath: markerURL.path) else {
        return (false, "Another app controls system sleep. Use one lid controller at a time.")
      }
      keepAwake = true
      ownsSleepDisabled = true
      lastHeartbeatUptime = ProcessInfo.processInfo.systemUptime
      return (true, nil)
    }

    // Write ownership before changing power state so a crash between these steps
    // still leaves enough information for the watchdog or next launch to restore.
    do {
      try Data().write(to: markerURL, options: .atomic)
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o600], ofItemAtPath: markerURL.path)
    } catch {
      return (false, "Unable to create the sleep safety marker: \(error.localizedDescription)")
    }
    ownsSleepDisabled = true
    let result = Self.runPmset(disableSleep: true)
    guard result.ok else {
      _ = disableOwnedSleepDisabled()
      return result
    }

    ownsSleepDisabled = true
    keepAwake = true
    lastHeartbeatUptime = ProcessInfo.processInfo.systemUptime
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
    lastHeartbeatUptime = 0
    return (true, nil)
  }

  private func restoreStaleOwnedState() {
    _ = withSleepSettingLock { disableOwnedSleepDisabled() }
  }

  private func withSleepSettingLock(
    _ operation: () -> (ok: Bool, error: String?)
  ) -> (ok: Bool, error: String?) {
    do { return try LazyestSystemSleepLock.withLock(operation) } catch {
      return (false, error.localizedDescription)
    }
  }

  private func startWatchdog() {
    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now() + 15, repeating: 15)
    timer.setEventHandler { [weak self] in
      guard let self else { return }
      let hasOwnedMarker = FileManager.default.fileExists(atPath: self.markerURL.path)
      guard self.keepAwake || self.ownsSleepDisabled || hasOwnedMarker else { return }
      let leaseExpired =
        ProcessInfo.processInfo.systemUptime - self.lastHeartbeatUptime
        > LazyestPowerHelper.watchdogTimeout
      if !self.keepAwake || leaseExpired || !Self.powerSafetyAllowsKeepAwake {
        _ = self.withSleepSettingLock { self.disableOwnedSleepDisabled() }
      }
    }
    timer.resume()
    watchdogTimer = timer
  }

  private static var powerSafetyAllowsKeepAwake: Bool {
    let thermal = ProcessInfo.processInfo.thermalState
    guard thermal != .serious && thermal != .critical else { return false }
    guard let unmanagedInfo = IOPSCopyPowerSourcesInfo() else { return false }
    let info = unmanagedInfo.takeRetainedValue()
    let source = IOPSGetProvidingPowerSourceType(info).takeUnretainedValue() as String
    if source == kIOPSACPowerValue as String { return true }
    guard let unmanagedList = IOPSCopyPowerSourcesList(info) else { return false }
    for source in unmanagedList.takeRetainedValue() as [AnyObject] {
      guard let unmanaged = IOPSGetPowerSourceDescription(info, source),
        let battery = unmanaged.takeUnretainedValue() as? [String: Any],
        battery[kIOPSTypeKey as String] as? String == kIOPSInternalBatteryType as String,
        let current = battery[kIOPSCurrentCapacityKey as String] as? Int,
        let maximum = battery[kIOPSMaxCapacityKey as String] as? Int,
        maximum > 0
      else { continue }
      return Double(current) / Double(maximum) * 100
        > Double(SleepPreventionPolicy.defaultLowBatteryCutoff)
    }
    return false
  }

  private static func isSleepDisabled() -> Bool {
    readSleepDisabled() == true
  }

  private static func readSleepDisabled() -> Bool? {
    guard let output = capture("/usr/bin/pmset", ["-g"]) else { return nil }
    for line in output.split(separator: "\n") {
      let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
      guard fields.count >= 2, fields[0].lowercased() == "sleepdisabled" else { continue }
      if fields[1] == "1" { return true }
      if fields[1] == "0" { return false }
      return nil
    }
    return nil
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
    guard process.terminationStatus == 0 else { return nil }
    return String(
      data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
  }
}
