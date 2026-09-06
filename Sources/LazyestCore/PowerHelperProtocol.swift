import Darwin
import Foundation

public enum LazyestPowerHelper {
  public static let label = "com.lazyest.flow.power-helper"
  public static let agentBundleIdentifier = "com.lazyest.flow"
  public static let plistName = "\(label).plist"
  public static let executableName = "LazyestPowerHelper"
  public static let protocolVersion = "2"
  public static let watchdogTimeout: TimeInterval = 90
  public static let installedAppPath = "/Applications/Lazyest Flow.app"
  public static let installedFlowExecutablePath =
    "\(installedAppPath)/Contents/MacOS/LazyestFlow"
  public static let embeddedHelperPath =
    "\(installedAppPath)/Contents/MacOS/\(executableName)"
  public static let installedExecutablePath =
    "/Library/PrivilegedHelperTools/\(label)"
  public static let installedPlistPath = "/Library/LaunchDaemons/\(label).plist"
  public static let ownedSleepMarkerPath =
    "/var/db/\(label).owns-sleep-disabled"
  public static let clientAppPathEnvironment = "LAZYEST_FLOW_CLIENT_APP_PATH"
  public static let clientCDHashEnvironment = "LAZYEST_FLOW_CLIENT_CDHASH"
  public static let clientUserIDEnvironment = "LAZYEST_FLOW_CLIENT_UID"
}

@objc public protocol LazyestPowerHelperProtocol {
  func setSleepDisabled(
    _ enabled: Bool,
    withReply reply: @escaping (Bool, String?) -> Void
  )
  func getSleepDisabled(withReply reply: @escaping (Bool) -> Void)
  func heartbeat(withReply reply: @escaping (Bool) -> Void)
  func version(withReply reply: @escaping (String) -> Void)
}

/// Serializes ownership changes made by Lazyest Flow and Lazyest Presence helpers.
/// The root-owned file is intentionally retained: unlinking can split lock ownership.
public enum LazyestSystemSleepLock {
  public static let path = "/var/run/com.lazyest.power.lock"

  public static func withLock<T>(_ operation: () throws -> T) throws -> T {
    try acquire(path: path, expectedOwner: 0, timeout: 2, operation)
  }

  #if LAZYEST_LOCK_TESTING
    public static func withTestLock<T>(
      path: String, expectedOwner: uid_t, timeout: TimeInterval = 0.1,
      _ operation: () throws -> T
    ) throws -> T {
      try acquire(path: path, expectedOwner: expectedOwner, timeout: timeout, operation)
    }
  #endif

  private static func acquire<T>(
    path: String, expectedOwner: uid_t, timeout: TimeInterval,
    _ operation: () throws -> T
  ) throws -> T {
    let descriptor = Darwin.open(path, O_CREAT | O_NOFOLLOW | O_RDWR | O_CLOEXEC, mode_t(0o600))
    guard descriptor >= 0 else { throw lockError("Unable to open the system sleep lock.") }
    defer { Darwin.close(descriptor) }
    var info = stat()
    guard fstat(descriptor, &info) == 0,
      info.st_mode & S_IFMT == S_IFREG, info.st_uid == expectedOwner, info.st_nlink == 1,
      info.st_mode & 0o022 == 0
    else { throw lockError("Invalid system sleep lock ownership.") }
    let deadline = ProcessInfo.processInfo.systemUptime + timeout
    while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
      guard errno == EWOULDBLOCK || errno == EAGAIN,
        ProcessInfo.processInfo.systemUptime < deadline
      else { throw lockError("Another app is updating system sleep. Try again.") }
      usleep(20_000)
    }
    defer { flock(descriptor, LOCK_UN) }
    return try operation()
  }

  private static func lockError(_ message: String) -> NSError {
    NSError(
      domain: "com.lazyest.flow.power-lock", code: 1,
      userInfo: [NSLocalizedDescriptionKey: message])
  }
}
