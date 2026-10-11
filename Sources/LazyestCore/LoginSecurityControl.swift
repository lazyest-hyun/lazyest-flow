import Foundation

public enum LoginSecurityAction: Equatable {
  case startupOff
  case startupCurrentUser
  case wake(WakePasswordDelay)
}

/// A closed list prevents arbitrary sysadminctl arguments or numeric coercion.
public enum WakePasswordDelay: String, CaseIterable {
  case immediate = "immediate"
  case fiveSeconds = "5"
  case oneMinute = "60"
  case fiveMinutes = "300"
  case off = "off"
}

public struct LoginConsoleIdentity: Equatable {
  public let userName: String
  public let uid: UInt32

  public init?(userName: String, uid: UInt32) {
    guard uid > 0, !["loginwindow", "_mbsetupuser"].contains(userName),
      userName.range(of: "^[a-z_][a-z0-9_.-]{0,63}$", options: .regularExpression) != nil
    else { return nil }
    self.userName = userName
    self.uid = uid
  }
}

public struct LoginToolCapabilities: Equatable {
  public let startup: Bool
  public let wake: Bool
  public let startupPasswordPrompt: Bool
  public let wakePasswordPrompt: Bool

  public static let unknown = LoginToolCapabilities(
    startup: false, wake: false, startupPasswordPrompt: false, wakePasswordPrompt: false)

  public static func detect(help: String, exitCode: Int32, timedOut: Bool = false)
    -> LoginToolCapabilities
  {
    guard exitCode == 0, !timedOut, help.utf8.count <= 32_768,
      help.contains("Usage: sysadminctl"),
      !help.contains("### Error"), !help.contains("Error:")
    else { return .unknown }
    let startup = help.contains(
      "-autologin set -userName <user name> [-password <user password>] || off || status (interactive || -adminUser <administrator user name> -adminPassword <administrator password>)"
    )
    let wake = help.contains(
      "-screenLock <status || immediate || off || seconds> -password <password>")
    let prompt = help.contains("Pass '-' instead of password in commands above to request prompt.")
    return LoginToolCapabilities(
      startup: startup, wake: wake,
      startupPasswordPrompt: startup && prompt, wakePasswordPrompt: wake && prompt)
  }
}

public enum StartupLoginObservation: Equatable {
  case off
  case user(String)
  case blockedByFileVault
  case unknown
}

public enum WakeLoginObservation: Equatable {
  case off
  case seconds(Int)
  case unknown
}

public struct LoginToolResult: Equatable {
  public let exitCode: Int32
  public let stdout: String
  public let stderr: String
  public let timedOut: Bool

  public init(exitCode: Int32, stdout: String = "", stderr: String = "", timedOut: Bool = false) {
    self.exitCode = exitCode
    self.stdout = stdout
    self.stderr = stderr
    self.timedOut = timedOut
  }
}

public enum LoginToolStatusParser {
  // sysadminctl writes status to stderr with an NSLog prefix. An error anywhere
  // invalidates the entire observation, even if exit status is 0 and OFF follows.
  private static func message(_ result: LoginToolResult) -> String? {
    guard result.exitCode == 0, !result.timedOut,
      result.stdout.utf8.count + result.stderr.utf8.count <= 32_768
    else { return nil }
    let lines = (result.stdout + "\n" + result.stderr).split(separator: "\n").map {
      String($0).replacingOccurrences(
        of: "^\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}\\.\\d+ sysadminctl\\[\\d+:\\d+\\] ",
        with: "", options: .regularExpression)
    }.filter { !$0.isEmpty }
    guard lines.count == 1 else { return nil }
    return lines[0]
  }

  public static func startup(_ result: LoginToolResult) -> StartupLoginObservation {
    guard let text = message(result) else { return .unknown }
    if text == "Automatic login is OFF." { return .off }
    if text == "Automatic login is disabled because FileVault is enabled." {
      return .blockedByFileVault
    }
    let prefix = "Automatic login user: "
    guard text.hasPrefix(prefix),
      let user = LoginConsoleIdentity(userName: String(text.dropFirst(prefix.count)), uid: 1)
    else { return .unknown }
    return .user(user.userName)
  }

  public static func wake(_ result: LoginToolResult) -> WakeLoginObservation {
    guard let text = message(result) else { return .unknown }
    if text == "screenLock is off" { return .off }
    if text == "screenLock delay is immediate" { return .seconds(0) }
    let prefix = "screenLock delay is "
    let suffix = " seconds"
    guard text.hasPrefix(prefix), text.hasSuffix(suffix) else { return .unknown }
    let value = String(text.dropFirst(prefix.count).dropLast(suffix.count))
    guard value.range(of: "^[0-9]{1,8}$", options: .regularExpression) != nil,
      let seconds = Int(value)
    else { return .unknown }
    return .seconds(seconds)
  }
}

public struct LoginSecuritySnapshot: Equatable {
  public let identity: LoginConsoleIdentity?
  public let capabilities: LoginToolCapabilities
  public let fileVault: AutomaticLoginPolicy.FileVaultState
  public let startup: StartupLoginObservation
  public let wake: WakeLoginObservation

  public init(
    identity: LoginConsoleIdentity?, capabilities: LoginToolCapabilities,
    fileVault: AutomaticLoginPolicy.FileVaultState, startup: StartupLoginObservation,
    wake: WakeLoginObservation
  ) {
    self.identity = identity
    self.capabilities = capabilities
    self.fileVault = fileVault
    self.startup = startup
    self.wake = wake
  }
}

/// The acting console identity is separate from the account affected by the
/// machine-wide startup-off command, which has no username argument.
public enum LoginSecurityAffectedAccount: Equatable {
  case machineAutomaticLogin(StartupLoginObservation)
  case account(String)
}

public struct LoginSecurityConfirmationScope: Equatable {
  public let actingUser: LoginConsoleIdentity
  public let affected: LoginSecurityAffectedAccount

  public init(
    action: LoginSecurityAction, snapshot: LoginSecuritySnapshot, actor: LoginConsoleIdentity
  ) {
    actingUser = actor
    switch action {
    case .startupOff: affected = .machineAutomaticLogin(snapshot.startup)
    case .startupCurrentUser, .wake: affected = .account(actor.userName)
    }
  }
}

/// Closed, read-only commands shared by the fresh provider and OS adapter.
public enum LoginSecurityReadCommand: CaseIterable {
  case help
  case startupStatus
  case wakeStatus
  case fileVaultStatus

  public var executable: String {
    self == .fileVaultStatus ? "/usr/bin/fdesetup" : "/usr/sbin/sysadminctl"
  }

  public var arguments: [String] {
    switch self {
    case .help: return ["-help"]
    case .startupStatus: return ["-autologin", "status"]
    case .wakeStatus: return ["-screenLock", "status"]
    case .fileVaultStatus: return ["isactive"]
    }
  }
}

public protocol LoginSecuritySnapshotSource {
  func consoleIdentity() -> LoginConsoleIdentity?
  func read(_ command: LoginSecurityReadCommand) -> LoginToolResult
}

public enum LoginSecuritySnapshotProvider {
  /// Never reuses a UI snapshot. Each invocation performs new OS reads and
  /// validates the console identity at both ends of the observation interval.
  public static func freshSnapshot(using source: LoginSecuritySnapshotSource)
    -> LoginSecuritySnapshot
  {
    let originalIdentity = source.consoleIdentity()
    let help = source.read(.help)
    let capabilities = LoginToolCapabilities.detect(
      help: help.stdout + help.stderr,
      exitCode: help.exitCode, timedOut: help.timedOut)
    let vault = source.read(.fileVaultStatus)
    let fileVault =
      vault.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? AutomaticLoginPolicy.fileVaultState(
        output: vault.stdout, exitCode: vault.exitCode, timedOut: vault.timedOut)
      : .unknown
    let startup =
      capabilities.startup ? LoginToolStatusParser.startup(source.read(.startupStatus)) : .unknown
    let wake = capabilities.wake ? LoginToolStatusParser.wake(source.read(.wakeStatus)) : .unknown
    let identity = source.consoleIdentity()
    return LoginSecuritySnapshot(
      identity: identity == originalIdentity ? identity : nil,
      capabilities: capabilities, fileVault: fileVault, startup: startup, wake: wake)
  }
}

public struct LoginSecurityCommandPlan: Equatable {
  public let action: LoginSecurityAction
  public let identity: LoginConsoleIdentity
  public let executable = "/usr/sbin/sysadminctl"
  public let arguments: [String]

  private init(action: LoginSecurityAction, identity: LoginConsoleIdentity, arguments: [String]) {
    self.action = action
    self.identity = identity
    self.arguments = arguments
  }

  public static func make(action: LoginSecurityAction, snapshot: LoginSecuritySnapshot)
    -> LoginSecurityCommandPlan?
  {
    guard let identity = snapshot.identity else { return nil }
    switch action {
    case .startupOff:
      guard snapshot.capabilities.startup else { return nil }
      return Self(
        action: action, identity: identity, arguments: ["interactive", "-autologin", "off"])
    case .startupCurrentUser:
      guard snapshot.capabilities.startupPasswordPrompt, snapshot.fileVault == .off,
        snapshot.startup != .blockedByFileVault
      else { return nil }
      return Self(
        action: action, identity: identity,
        arguments: [
          "interactive", "-autologin", "set", "-userName", identity.userName, "-password", "-",
        ])
    case .wake(let delay):
      guard snapshot.capabilities.wakePasswordPrompt else { return nil }
      return Self(
        action: action, identity: identity,
        arguments: ["interactive", "-screenLock", delay.rawValue, "-password", "-"])
    }
  }

  public func matches(_ observed: LoginSecuritySnapshot) -> Bool {
    guard observed.identity == identity else { return false }
    switch action {
    case .startupOff: return observed.startup == .off
    case .startupCurrentUser:
      return observed.fileVault == .off && observed.startup == .user(identity.userName)
    case .wake(.off): return observed.wake == .off
    case .wake(let delay):
      let seconds = delay == .immediate ? 0 : Int(delay.rawValue)
      return seconds.map { observed.wake == .seconds($0) } ?? false
    }
  }
}

public enum LoginSecurityFailure: Equatable {
  case unsupported
  case authenticationTransportUnverified
  case contextChanged
  case denied
  case commandFailed
  case outcomeUnknown
  case readbackMismatch
}

public enum LoginSecurityPhase: Equatable {
  case idle
  case awaitingConfirmation
  case authenticating
  case applying
  case verifying
  case applied
  case cancelled
  case failed(LoginSecurityFailure)
}

public enum LoginSecurityAuthenticationResult {
  case authorized
  case cancelled
  case denied
}

public enum LoginSecurityApplyResult {
  case finished
  case failed
  case timedOut
}

/// The production driver is gated. A runner never accepts executable paths,
/// arbitrary shell text, or passwords; only a validated, session-bound plan.
public protocol LoginSecurityActionRunner {
  func authenticationTransportVerified(for plan: LoginSecurityCommandPlan) -> Bool
  func currentSnapshot() -> LoginSecuritySnapshot
  func authenticate(_ plan: LoginSecurityCommandPlan) -> LoginSecurityAuthenticationResult
  func apply(_ plan: LoginSecurityCommandPlan) -> LoginSecurityApplyResult
}

public struct LoginSecurityChangeSession {
  public private(set) var phase: LoginSecurityPhase = .idle
  public private(set) var plan: LoginSecurityCommandPlan?
  public private(set) var lastObservation: LoginSecuritySnapshot?
  private var original: LoginSecuritySnapshot?

  public init() {}

  public mutating func choose(_ action: LoginSecurityAction, snapshot: LoginSecuritySnapshot) {
    guard ![.authenticating, .applying, .verifying].contains(phase) else { return }
    plan = LoginSecurityCommandPlan.make(action: action, snapshot: snapshot)
    original = snapshot
    lastObservation = snapshot
    phase = plan == nil ? .failed(.unsupported) : .awaitingConfirmation
  }

  public mutating func cancel() {
    // Once a command is running, cancellation cannot promise that no write occurred.
    guard phase == .awaitingConfirmation else { return }
    phase = .cancelled
    plan = nil
    original = nil
  }

  public mutating func confirm(
    using runner: LoginSecurityActionRunner,
    onPhase: (LoginSecurityPhase) -> Void = { _ in }
  ) {
    guard phase == .awaitingConfirmation, let plan, let original else { return }
    func contextMatches(_ current: LoginSecuritySnapshot) -> Bool { current == original }
    let beforeAuthentication = runner.currentSnapshot()
    lastObservation = beforeAuthentication
    guard contextMatches(beforeAuthentication) else {
      phase = .failed(.contextChanged)
      onPhase(phase)
      return
    }
    guard runner.authenticationTransportVerified(for: plan) else {
      phase = .failed(.authenticationTransportUnverified)
      onPhase(phase)
      return
    }
    phase = .authenticating
    onPhase(phase)
    switch runner.authenticate(plan) {
    case .cancelled: phase = .cancelled
    case .denied: phase = .failed(.denied)
    case .authorized:
      let beforeApply = runner.currentSnapshot()
      lastObservation = beforeApply
      guard contextMatches(beforeApply) else {
        phase = .failed(.contextChanged)
        onPhase(phase)
        return
      }
      phase = .applying
      onPhase(phase)
      switch runner.apply(plan) {
      case .failed:
        phase = .verifying
        onPhase(phase)
        lastObservation = runner.currentSnapshot()
        phase = .failed(.commandFailed)
      case .timedOut:
        phase = .verifying
        onPhase(phase)
        lastObservation = runner.currentSnapshot()
        phase = .failed(.outcomeUnknown)
      case .finished:
        phase = .verifying
        onPhase(phase)
        let observed = runner.currentSnapshot()
        lastObservation = observed
        phase = plan.matches(observed) ? .applied : .failed(.readbackMismatch)
      }
    }
    onPhase(phase)
  }
}
