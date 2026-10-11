import Darwin
import Foundation
import LazyestCore
import SystemConfiguration

/// Only these three read-only sysadminctl forms can reach Process in production.
/// Mutation plans are never executed by this reader.
private enum LoginSecurityReadCommand: CaseIterable {
  case help
  case startupStatus
  case wakeStatus

  var arguments: [String] {
    switch self {
    case .help: return ["-help"]
    case .startupStatus: return ["-autologin", "status"]
    case .wakeStatus: return ["-screenLock", "status"]
    }
  }
}

private final class BoundedLoginToolOutput {
  private let lock = NSLock()
  private var bytes = Data()
  private var exceeded = false

  func read(_ handle: FileHandle) {
    while let chunk = try? handle.read(upToCount: 4096), !chunk.isEmpty {
      lock.lock()
      if bytes.count + chunk.count > 32_768 {
        exceeded = true
      } else if !exceeded {
        bytes.append(chunk)
      }
      lock.unlock()
      // Continue draining without retaining excess bytes so a child cannot
      // deadlock on a full pipe. The command still has a fixed time limit.
    }
  }

  func result() -> (String, Bool) {
    lock.lock()
    defer { lock.unlock() }
    return (String(decoding: bytes, as: UTF8.self), exceeded)
  }
}

enum LoginSecurityStatusReader {
  static func consoleIdentity() -> LoginConsoleIdentity? {
    var uid: uid_t = 0
    var gid: gid_t = 0
    guard let name = SCDynamicStoreCopyConsoleUser(nil, &uid, &gid) as String?,
      uid == getuid(), getuid() == geteuid()
    else { return nil }
    return LoginConsoleIdentity(userName: name, uid: uid)
  }

  private static func read(_ command: LoginSecurityReadCommand) -> LoginToolResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/sysadminctl")
    process.arguments = command.arguments
    process.environment = ["LANG": "C", "LC_ALL": "C"]
    process.standardInput = FileHandle.nullDevice
    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr
    let finished = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in finished.signal() }
    let readers = DispatchGroup()
    let out = BoundedLoginToolOutput()
    let err = BoundedLoginToolOutput()
    do {
      try process.run()
      DispatchQueue.global(qos: .utility).async(group: readers) {
        out.read(stdout.fileHandleForReading)
      }
      DispatchQueue.global(qos: .utility).async(group: readers) {
        err.read(stderr.fileHandleForReading)
      }
      guard finished.wait(timeout: .now() + 3) == .success else {
        if process.isRunning { process.terminate() }
        return LoginToolResult(exitCode: -1, timedOut: true)
      }
      guard readers.wait(timeout: .now() + 0.25) == .success else {
        return LoginToolResult(exitCode: -1, timedOut: true)
      }
      let output = out.result()
      let error = err.result()
      guard !output.1, !error.1 else { return LoginToolResult(exitCode: -1) }
      return LoginToolResult(
        exitCode: process.terminationStatus, stdout: output.0, stderr: error.0)
    } catch {
      return LoginToolResult(exitCode: -1)
    }
  }

  static func query(
    fileVault: AutomaticLoginPolicy.FileVaultState,
    completion: @escaping (LoginSecuritySnapshot) -> Void
  ) {
    let originalIdentity = consoleIdentity()
    DispatchQueue.global(qos: .utility).async {
      let help = read(.help)
      let capabilities = LoginToolCapabilities.detect(
        help: help.stdout + help.stderr, exitCode: help.exitCode, timedOut: help.timedOut)
      let startup =
        capabilities.startup ? LoginToolStatusParser.startup(read(.startupStatus)) : .unknown
      let wake = capabilities.wake ? LoginToolStatusParser.wake(read(.wakeStatus)) : .unknown
      DispatchQueue.main.async {
        let identity = consoleIdentity()
        completion(
          LoginSecuritySnapshot(
            identity: identity == originalIdentity ? identity : nil,
            capabilities: capabilities, fileVault: fileVault, startup: startup, wake: wake))
      }
    }
  }
}

/// No real security mutation driver is enabled. This is deliberately separate
/// from the power helper and the allowlisted read-only Process implementation.
final class GatedLoginSecurityRunner: LoginSecurityActionRunner {
  func authenticationTransportVerified(for plan: LoginSecurityCommandPlan) -> Bool { false }
  private let snapshotProvider: () -> LoginSecuritySnapshot

  init(snapshotProvider: @escaping () -> LoginSecuritySnapshot) {
    self.snapshotProvider = snapshotProvider
  }

  func currentSnapshot() -> LoginSecuritySnapshot { snapshotProvider() }
  func authenticate(_ plan: LoginSecurityCommandPlan) -> LoginSecurityAuthenticationResult {
    .denied
  }
  func apply(_ plan: LoginSecurityCommandPlan) -> LoginSecurityApplyResult { .failed }
}
