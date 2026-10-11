import Darwin
import Foundation
import LazyestCore
import SystemConfiguration

/// Production execution accepts only the closed read-only command enum.
/// Mutation plans never reach this reader.
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

  fileprivate static func read(_ command: LoginSecurityReadCommand) -> LoginToolResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: command.executable)
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

  static func freshSnapshot() -> LoginSecuritySnapshot {
    LoginSecuritySnapshotProvider.freshSnapshot(using: SystemLoginSecuritySnapshotSource())
  }

  static func query(completion: @escaping (LoginSecuritySnapshot) -> Void) {
    DispatchQueue.global(qos: .utility).async {
      let snapshot = freshSnapshot()
      DispatchQueue.main.async { completion(snapshot) }
    }
  }
}

/// No real security mutation driver is enabled. This is deliberately separate
/// from the power helper and the allowlisted read-only Process implementation.
final class GatedLoginSecurityRunner: LoginSecurityActionRunner {
  func authenticationTransportVerified(for plan: LoginSecurityCommandPlan) -> Bool { false }
  func currentSnapshot() -> LoginSecuritySnapshot { LoginSecurityStatusReader.freshSnapshot() }
  func authenticate(_ plan: LoginSecurityCommandPlan) -> LoginSecurityAuthenticationResult {
    .denied
  }
  func apply(_ plan: LoginSecurityCommandPlan) -> LoginSecurityApplyResult { .failed }
}

private struct SystemLoginSecuritySnapshotSource: LoginSecuritySnapshotSource {
  func consoleIdentity() -> LoginConsoleIdentity? { LoginSecurityStatusReader.consoleIdentity() }
  func read(_ command: LoginSecurityReadCommand) -> LoginToolResult {
    LoginSecurityStatusReader.read(command)
  }
}
