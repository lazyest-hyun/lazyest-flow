import AppKit
import Carbon
import Foundation
import IOKit
import IOKit.ps
import IOKit.pwr_mgt
import LazyestCore

let keepAwakeStatusNotification = Notification.Name("LazyestFlowKeepAwakeStatusDidChange")

struct PowerSnapshot: Equatable {
  let onACPower: Bool
  let batteryPercent: Int?
  let charging: Bool
}

enum KeepAwakeStatus: Equatable {
  case off(PowerSnapshot)
  case activating(PowerSnapshot)
  case active(PowerSnapshot)
  case waitingForPower(PowerSnapshot)
  case lowBattery(PowerSnapshot)
  case thermalSafety(PowerSnapshot)
  case helperApprovalRequired(PowerSnapshot)
  case helperUnavailable(PowerSnapshot)

  var isActive: Bool {
    if case .active = self { return true }
    return false
  }

  var power: PowerSnapshot {
    switch self {
    case .off(let power), .activating(let power), .active(let power),
      .waitingForPower(let power), .lowBattery(let power), .thermalSafety(let power),
      .helperApprovalRequired(let power), .helperUnavailable(let power):
      return power
    }
  }
}

final class KeepAwakeController {
  private let config: Config
  private let helper = PowerHelperManager()
  private let powerMonitor = SystemPowerSourceMonitor()
  private let lidMonitor = LidStateMonitor()
  private var thermalObserver: NSObjectProtocol?
  private var assertionID = IOPMAssertionID(0)
  private var assertionActive = false
  private var helperActive = false
  private var helperRequestInFlight = false
  private var authorizationRequestInFlight = false
  private var heartbeatTimer: Timer?
  private var generation = 0
  private(set) var status: KeepAwakeStatus

  init(config: Config) {
    self.config = config
    self.status = .off(powerMonitor.snapshot)
    powerMonitor.onChange = { [weak self] in
      self?.evaluate()
    }
    lidMonitor.onChange = { [weak self] isClosed in
      self?.handleLidChange(isClosed: isClosed)
    }
    thermalObserver = NotificationCenter.default.addObserver(
      forName: ProcessInfo.thermalStateDidChangeNotification,
      object: ProcessInfo.processInfo,
      queue: .main
    ) { [weak self] _ in
      self?.evaluate()
    }
  }

  deinit {
    shutdown()
    if let thermalObserver {
      NotificationCenter.default.removeObserver(thermalObserver)
    }
  }

  var isActive: Bool {
    status.isActive && assertionActive && helperActive
  }

  func reload() {
    config.reloadBootstrap()
    evaluate()
  }

  func requestAuthorization(forceReinstall: Bool = false) {
    guard config.keepAwakeEnabled else { return }
    if helper.status == .installed && !forceReinstall {
      return
    }
    guard !authorizationRequestInFlight else { return }
    authorizationRequestInFlight = true
    publish(.activating(powerMonitor.snapshot))
    helper.install { [weak self] success, message in
      guard let self else { return }
      self.authorizationRequestInFlight = false
      if success {
        self.evaluate()
      } else {
        if let message {
          NSLog("Power helper installation was not completed: \(message)")
        }
        self.stopIdleSleepAssertion()
        self.publish(.helperApprovalRequired(self.powerMonitor.snapshot))
      }
    }
  }

  func shutdown(waitForHelper: Bool = false) {
    generation += 1
    heartbeatTimer?.invalidate()
    heartbeatTimer = nil
    stopIdleSleepAssertion()
    if helper.status == .installed {
      var completed = false
      helper.setSleepDisabled(false) { _, _ in
        completed = true
      }
      if waitForHelper {
        let deadline = Date().addingTimeInterval(3)
        while !completed && Date() < deadline {
          RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
      }
    }
    helperActive = false
  }

  private func evaluate() {
    dispatchPrecondition(condition: .onQueue(.main))
    generation += 1
    let currentGeneration = generation
    let power = powerMonitor.snapshot
    let thermalState = ProcessInfo.processInfo.thermalState
    let decision = SleepPreventionPolicy.resolve(
      enabled: config.keepAwakeEnabled,
      includeBattery: config.keepAwakeOnBattery,
      onACPower: power.onACPower,
      batteryPercent: power.batteryPercent,
      thermalSafetyRequired: thermalState == .serious || thermalState == .critical
    )

    switch decision {
    case .disabled:
      deactivateHelper(generation: currentGeneration, status: .off(power))
    case .waitingForPower:
      deactivateHelper(generation: currentGeneration, status: .waitingForPower(power))
    case .lowBattery:
      deactivateHelper(generation: currentGeneration, status: .lowBattery(power))
    case .thermalSafety:
      deactivateHelper(generation: currentGeneration, status: .thermalSafety(power))
    case .active:
      activate(generation: currentGeneration, power: power)
    }
  }

  private func activate(generation currentGeneration: Int, power: PowerSnapshot) {
    guard startIdleSleepAssertion() else {
      publish(.helperUnavailable(power))
      return
    }

    switch helper.status {
    case .installed:
      if helperActive {
        publish(.active(power))
        startHeartbeat()
        return
      }
      guard !helperRequestInFlight else {
        publish(.activating(power))
        return
      }
      helperRequestInFlight = true
      publish(.activating(power))
      helper.setSleepDisabled(true) { [weak self] success, message in
        guard let self else { return }
        self.helperRequestInFlight = false
        guard self.generation == currentGeneration else {
          if success {
            self.helperActive = true
            self.helperRequestInFlight = true
            self.helper.setSleepDisabled(false) { [weak self] disabled, _ in
              guard let self else { return }
              self.helperRequestInFlight = false
              self.helperActive = !disabled
              self.evaluate()
            }
          } else {
            self.helperActive = false
            self.evaluate()
          }
          return
        }
        self.helperActive = success
        if success {
          self.publish(.active(self.powerMonitor.snapshot))
          self.startHeartbeat()
        } else {
          if let message {
            NSLog("Power helper activation failed: \(message)")
          }
          self.stopIdleSleepAssertion()
          self.publish(.helperUnavailable(self.powerMonitor.snapshot))
        }
      }
    case .notInstalled:
      stopIdleSleepAssertion()
      helperActive = false
      publish(.helperApprovalRequired(power))
    }
  }

  private func deactivateHelper(generation currentGeneration: Int, status target: KeepAwakeStatus) {
    heartbeatTimer?.invalidate()
    heartbeatTimer = nil
    stopIdleSleepAssertion()
    guard helperActive || helperRequestInFlight, helper.status == .installed else {
      helperActive = false
      helperRequestInFlight = false
      publish(target)
      return
    }

    helperRequestInFlight = true
    helper.setSleepDisabled(false) { [weak self] success, _ in
      guard let self else { return }
      self.helperRequestInFlight = false
      self.helperActive = !success
      guard self.generation == currentGeneration else {
        self.evaluate()
        return
      }
      self.publish(success ? target : .helperUnavailable(self.powerMonitor.snapshot))
    }
  }

  private func startIdleSleepAssertion() -> Bool {
    if assertionActive { return true }
    var id = IOPMAssertionID(0)
    let result = IOPMAssertionCreateWithName(
      kIOPMAssertionTypeNoIdleSleep as CFString,
      IOPMAssertionLevel(kIOPMAssertionLevelOn),
      "LazyestFlow sleep mode prevention" as CFString,
      &id
    )
    guard result == kIOReturnSuccess else {
      NSLog("Failed to create sleep assertion: \(result)")
      return false
    }
    assertionID = id
    assertionActive = true
    return true
  }

  private func stopIdleSleepAssertion() {
    guard assertionActive else { return }
    let result = IOPMAssertionRelease(assertionID)
    guard result == kIOReturnSuccess else {
      NSLog("Failed to release sleep assertion; retaining handle for retry: \(result)")
      return
    }
    assertionID = 0
    assertionActive = false
  }

  private func startHeartbeat() {
    guard heartbeatTimer == nil else { return }
    let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
      guard let self, self.helperActive else { return }
      self.helper.heartbeat { success in
        if !success {
          self.helperActive = false
          self.evaluate()
        }
      }
    }
    RunLoop.main.add(timer, forMode: .common)
    heartbeatTimer = timer
  }

  private func handleLidChange(isClosed: Bool) {
    guard isClosed, config.keepAwakeEnabled, config.lockOnLidClose else { return }
    ScreenLocker.lockAndSleepDisplays()
  }

  private func publish(_ newStatus: KeepAwakeStatus) {
    guard status != newStatus else { return }
    status = newStatus
    NotificationCenter.default.post(name: keepAwakeStatusNotification, object: newStatus)
  }
}

private enum PowerHelperStatus {
  case installed
  case notInstalled
}

private final class PowerHelperManager {
  private var connection: NSXPCConnection?

  var status: PowerHelperStatus {
    PowerHelperInstaller.isInstalled ? .installed : .notInstalled
  }

  func install(completion: @escaping (Bool, String?) -> Void) {
    connection?.invalidate()
    connection = nil
    PowerHelperInstaller.requestInstall(completion: completion)
  }

  func setSleepDisabled(
    _ enabled: Bool,
    completion: @escaping (Bool, String?) -> Void
  ) {
    callWithTimeout(completion: completion) { proxy, finish in
      proxy.setSleepDisabled(enabled) { success, message in
        finish(success, message)
      }
    }
  }

  func heartbeat(completion: @escaping (Bool) -> Void) {
    callWithTimeout(
      timeout: 5,
      completion: { success, _ in completion(success) },
      { proxy, finish in
        proxy.heartbeat { success in finish(success, nil) }
      })
  }

  func remove(completion: @escaping (Bool, String?) -> Void) {
    connection?.invalidate()
    connection = nil
    PowerHelperInstaller.requestRemoval(completion: completion)
  }

  private func connect() -> NSXPCConnection {
    if let connection { return connection }
    let newConnection = NSXPCConnection(
      machServiceName: LazyestPowerHelper.label,
      options: .privileged
    )
    newConnection.remoteObjectInterface = NSXPCInterface(
      with: LazyestPowerHelperProtocol.self)
    newConnection.invalidationHandler = { [weak self] in self?.connection = nil }
    newConnection.interruptionHandler = {}
    newConnection.resume()
    connection = newConnection
    return newConnection
  }

  private func callWithTimeout(
    timeout: TimeInterval = 8,
    completion: @escaping (Bool, String?) -> Void,
    _ body: (
      LazyestPowerHelperProtocol,
      @escaping (Bool, String?) -> Void
    ) -> Void
  ) {
    var finished = false
    let finish: (Bool, String?) -> Void = { success, message in
      DispatchQueue.main.async {
        guard !finished else { return }
        finished = true
        completion(success, message)
      }
    }
    guard
      let proxy = connect().remoteObjectProxyWithErrorHandler({ error in
        finish(false, error.localizedDescription)
      }) as? LazyestPowerHelperProtocol
    else {
      finish(false, "Power helper connection unavailable")
      return
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
      finish(false, "Power helper did not respond")
    }
    body(proxy, finish)
  }

}

enum PowerHelperMaintenance {
  static func register() -> Int32 {
    let helper = PowerHelperManager()
    var finished = false
    var installed = false
    helper.install { success, message in
      installed = success
      if !success, let message, !message.isEmpty {
        fputs("Power helper registration failed: \(message)\n", stderr)
      }
      finished = true
    }
    guard wait(until: { finished }, timeout: 120) else { return 1 }
    return installed && helper.status == .installed ? 0 : 1
  }

  static func installAsRoot() -> Int32 {
    PowerHelperInstaller.installAsRoot()
  }

  static func removeAsRoot() -> Int32 {
    PowerHelperInstaller.removeAsRoot()
  }

  static func disable() -> Int32 {
    let helper = PowerHelperManager()
    return disable(helper)
  }

  static func isRegistered() -> Int32 {
    let helper = PowerHelperManager()
    switch helper.status {
    case .installed:
      return 0
    case .notInstalled:
      return 1
    }
  }

  static func uninstall() -> Int32 {
    let helper = PowerHelperManager()
    if helper.status == .notInstalled { return 0 }
    _ = disable(helper)
    var finished = false
    var removed = false
    helper.remove { success, _ in
      removed = success
      finished = true
    }
    guard wait(until: { finished }, timeout: 120) else { return 1 }
    return removed && helper.status == .notInstalled ? 0 : 1
  }

  private static func disable(_ helper: PowerHelperManager) -> Int32 {
    switch helper.status {
    case .notInstalled:
      return 0
    case .installed:
      var finished = false
      var disabled = false
      helper.setSleepDisabled(false) { success, _ in
        disabled = success
        finished = true
      }
      if wait(until: { finished }, timeout: 5), disabled {
        return 0
      }
      return systemSleepIsDisabled() ? 1 : 0
    }
  }

  private static func wait(until condition: () -> Bool, timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() && Date() < deadline {
      RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }
    return condition()
  }

  private static func systemSleepIsDisabled() -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    process.arguments = ["-g"]
    let output = Pipe()
    process.standardOutput = output
    process.standardError = Pipe()
    do {
      try process.run()
      process.waitUntilExit()
    } catch {
      return true
    }
    guard process.terminationStatus == 0 else { return true }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    guard let text = String(data: data, encoding: .utf8) else { return true }
    return text.split(separator: "\n").contains { line in
      let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
      return fields.count >= 2
        && fields[0].lowercased() == "sleepdisabled"
        && fields[1] == "1"
    }
  }
}

private final class SystemPowerSourceMonitor {
  var onChange: (() -> Void)?
  private var runLoopSource: CFRunLoopSource?
  private(set) var snapshot = SystemPowerSourceMonitor.readSnapshot()

  init() {
    let context = Unmanaged.passUnretained(self).toOpaque()
    guard
      let unmanagedSource = IOPSNotificationCreateRunLoopSource(
        { context in
          guard let context else { return }
          let monitor = Unmanaged<SystemPowerSourceMonitor>.fromOpaque(context)
            .takeUnretainedValue()
          monitor.refresh()
        },
        context
      )
    else {
      return
    }
    let source = unmanagedSource.takeRetainedValue()
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    runLoopSource = source
  }

  deinit {
    if let runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    }
  }

  private func refresh() {
    let updated = Self.readSnapshot()
    guard updated != snapshot else { return }
    snapshot = updated
    onChange?()
  }

  private static func readSnapshot() -> PowerSnapshot {
    guard let unmanagedInfo = IOPSCopyPowerSourcesInfo() else {
      return PowerSnapshot(onACPower: true, batteryPercent: nil, charging: false)
    }
    let info = unmanagedInfo.takeRetainedValue()
    let type = IOPSGetProvidingPowerSourceType(info).takeUnretainedValue() as String
    let onACPower = type == (kIOPSACPowerValue as String)
    guard let unmanagedList = IOPSCopyPowerSourcesList(info) else {
      return PowerSnapshot(onACPower: onACPower, batteryPercent: nil, charging: false)
    }
    let sources = unmanagedList.takeRetainedValue() as [AnyObject]
    for source in sources {
      guard
        let unmanagedDescription = IOPSGetPowerSourceDescription(info, source),
        let description = unmanagedDescription.takeUnretainedValue() as? [String: Any],
        description[kIOPSTypeKey as String] as? String == (kIOPSInternalBatteryType as String)
      else {
        continue
      }
      let current = description[kIOPSCurrentCapacityKey as String] as? Int
      let maximum = description[kIOPSMaxCapacityKey as String] as? Int
      let percent = current.flatMap { current in
        maximum.flatMap { maximum in
          maximum > 0 ? Int((Double(current) / Double(maximum) * 100).rounded()) : nil
        }
      }
      let charging = description[kIOPSIsChargingKey as String] as? Bool ?? false
      return PowerSnapshot(
        onACPower: onACPower,
        batteryPercent: percent,
        charging: charging
      )
    }
    return PowerSnapshot(onACPower: onACPower, batteryPercent: nil, charging: false)
  }
}

private final class LidStateMonitor {
  // Swift cannot import iokit_family_msg(...); this mirrors the public IOKit macro layout.
  private static let clamshellStateChangeMessage = natural_t(
    (UInt32(0x38) << 26) | (UInt32(13) << 14) | UInt32(0x100)
  )
  var onChange: ((Bool) -> Void)?
  private var notificationPort: IONotificationPortRef?
  private var notification: io_object_t = 0
  private var rootDomain: io_service_t = 0
  private var lastState: Bool?

  init() {
    rootDomain = IOServiceGetMatchingService(
      kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
    guard rootDomain != 0, let port = IONotificationPortCreate(kIOMainPortDefault) else {
      return
    }
    notificationPort = port
    IONotificationPortSetDispatchQueue(port, DispatchQueue.main)
    let context = Unmanaged.passUnretained(self).toOpaque()
    let result = IOServiceAddInterestNotification(
      port,
      rootDomain,
      kIOGeneralInterest,
      { context, _, messageType, messageArgument in
        guard let context else { return }
        let monitor = Unmanaged<LidStateMonitor>.fromOpaque(context).takeUnretainedValue()
        monitor.handleMessage(type: messageType, argument: messageArgument)
      },
      context,
      &notification
    )
    if result == kIOReturnSuccess {
      lastState = readClosedState()
    }
  }

  deinit {
    if notification != 0 { IOObjectRelease(notification) }
    if rootDomain != 0 { IOObjectRelease(rootDomain) }
    if let notificationPort { IONotificationPortDestroy(notificationPort) }
  }

  private func handleMessage(type: natural_t, argument: UnsafeMutableRawPointer?) {
    guard type == Self.clamshellStateChangeMessage else { return }
    let messageArgument = argument.map { UInt(bitPattern: $0) } ?? 0
    let closed = LidStatePolicy.isClosed(clamshellMessageArgument: messageArgument)
    guard closed != lastState else { return }
    lastState = closed
    NSLog("Lid state changed: \(closed ? "closed" : "open")")
    onChange?(closed)
  }

  private func readClosedState() -> Bool? {
    guard rootDomain != 0 else { return nil }
    return IORegistryEntryCreateCFProperty(
      rootDomain,
      "AppleClamshellState" as CFString,
      kCFAllocatorDefault,
      0
    )?.takeRetainedValue() as? Bool
  }
}

private enum ScreenLocker {
  private static let legacyCGSessionPath =
    "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession"

  static func lockAndSleepDisplays() {
    DispatchQueue.global(qos: .userInitiated).async {
      guard requestSessionLock() else {
        NSLog("Unable to request an immediate session lock")
        return
      }
      Thread.sleep(forTimeInterval: 0.3)
      if !run("/usr/bin/pmset", ["displaysleepnow"]) {
        NSLog("Unable to turn off displays after requesting a session lock")
      }
    }
  }

  private static func requestSessionLock() -> Bool {
    if FileManager.default.isExecutableFile(atPath: legacyCGSessionPath) {
      return run(legacyCGSessionPath, ["-suspend"])
    }
    return postSystemLockShortcut()
  }

  private static func postSystemLockShortcut() -> Bool {
    guard AXIsProcessTrusted() else { return false }
    guard
      let source = CGEventSource(stateID: .hidSystemState),
      let keyDown = CGEvent(
        keyboardEventSource: source,
        virtualKey: CGKeyCode(kVK_ANSI_Q),
        keyDown: true
      ),
      let keyUp = CGEvent(
        keyboardEventSource: source,
        virtualKey: CGKeyCode(kVK_ANSI_Q),
        keyDown: false
      )
    else {
      return false
    }
    let modifiers: CGEventFlags = [.maskControl, .maskCommand]
    keyDown.flags = modifiers
    keyUp.flags = modifiers
    keyDown.post(tap: .cghidEventTap)
    keyUp.post(tap: .cghidEventTap)
    return true
  }

  @discardableResult
  private static func run(_ path: String, _ arguments: [String]) -> Bool {
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
      NSLog("Unable to run \(path): \(error)")
      return false
    }
    guard process.terminationStatus == 0 else {
      let error = String(
        data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
        encoding: .utf8
      )?.trimmingCharacters(in: .whitespacesAndNewlines)
      NSLog(
        "Command failed (\(process.terminationStatus)): \(path) \(error ?? "")"
      )
      return false
    }
    return true
  }
}
