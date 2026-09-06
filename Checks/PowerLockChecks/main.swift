import Darwin
import Foundation

let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
  "lazyest-flow-power-lock-checks-\(UUID().uuidString)", isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
defer { try? FileManager.default.removeItem(at: directory) }
let lockPath = directory.appendingPathComponent("power.lock").path

func check(_ value: @autoclosure () -> Bool, _ message: String) {
  guard value() else { fatalError(message) }
}

func mustReject(_ message: String, _ operation: () throws -> Void) {
  do {
    try operation()
    fatalError(message)
  } catch {}
}

let initial = try LazyestSystemSleepLock.withTestLock(path: lockPath, expectedOwner: getuid()) {
  42
}
check(initial == 42, "The lock did not run its protected operation")
try LazyestSystemSleepLock.withTestLock(path: lockPath, expectedOwner: getuid()) {
  let started = ProcessInfo.processInfo.systemUptime
  mustReject("A second file descriptor acquired an already-held lock") {
    try LazyestSystemSleepLock.withTestLock(path: lockPath, expectedOwner: getuid(), timeout: 0.05)
    {}
  }
  check(ProcessInfo.processInfo.systemUptime - started < 1, "Contention did not time out promptly")
}

enum ExpectedFailure: Error { case thrown }
mustReject("The operation's error was swallowed") {
  try LazyestSystemSleepLock.withTestLock(path: lockPath, expectedOwner: getuid()) {
    throw ExpectedFailure.thrown
  }
}
try LazyestSystemSleepLock.withTestLock(path: lockPath, expectedOwner: getuid()) {}

mustReject("A file owned by the wrong user was accepted") {
  try LazyestSystemSleepLock.withTestLock(path: lockPath, expectedOwner: getuid() &+ 1) {}
}
try FileManager.default.setAttributes([.posixPermissions: 0o666], ofItemAtPath: lockPath)
mustReject("A writable-by-other-users lock file was accepted") {
  try LazyestSystemSleepLock.withTestLock(path: lockPath, expectedOwner: getuid()) {}
}
try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: lockPath)

let symlink = directory.appendingPathComponent("symlink").path
try FileManager.default.createSymbolicLink(atPath: symlink, withDestinationPath: lockPath)
mustReject("A symbolic link was followed") {
  try LazyestSystemSleepLock.withTestLock(path: symlink, expectedOwner: getuid()) {}
}
let hardlink = directory.appendingPathComponent("hardlink").path
try FileManager.default.linkItem(atPath: lockPath, toPath: hardlink)
mustReject("A lock file with multiple links was accepted") {
  try LazyestSystemSleepLock.withTestLock(path: lockPath, expectedOwner: getuid()) {}
}
try FileManager.default.removeItem(atPath: hardlink)
mustReject("A directory was accepted as a lock file") {
  try LazyestSystemSleepLock.withTestLock(path: directory.path, expectedOwner: getuid()) {}
}
try LazyestSystemSleepLock.withTestLock(path: lockPath, expectedOwner: getuid()) {}
print("LAZYEST_POWER_LOCK_CHECKS_OK")
