import AppKit
import Foundation
import LazyestCore

/// Read-only, unprivileged status query. Never accepts account names or passwords.
enum AutomaticLoginSupport {
  static func queryFileVault(completion: @escaping (AutomaticLoginPolicy.FileVaultState) -> Void) {
    DispatchQueue.global(qos: .utility).async {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/fdesetup")
      process.arguments = ["isactive"]
      process.environment = ["LANG": "C", "LC_ALL": "C"]
      process.standardInput = FileHandle.nullDevice
      process.standardError = FileHandle.nullDevice
      let output = Pipe()
      process.standardOutput = output
      let finished = DispatchSemaphore(value: 0)
      process.terminationHandler = { _ in finished.signal() }
      let state: AutomaticLoginPolicy.FileVaultState
      do {
        try process.run()
        if finished.wait(timeout: .now() + 3) == .timedOut {
          // Do not wait for a stalled OS command or let stale output imply eligibility.
          if process.isRunning { process.terminate() }
          state = .unknown
        } else {
          let data = output.fileHandleForReading.readDataToEndOfFile()
          state = AutomaticLoginPolicy.fileVaultState(
            output: String(decoding: data, as: UTF8.self), exitCode: process.terminationStatus)
        }
      } catch {
        state = .unknown
      }
      DispatchQueue.main.async { completion(state) }
    }
  }

  /// Launch the supported settings application. Pane deep links are undocumented
  /// and may silently open the wrong pane; the view supplies the explicit route.
  static func openSystemSettings(completion: @escaping (Bool) -> Void) {
    guard
      let url = NSWorkspace.shared.urlForApplication(
        withBundleIdentifier: "com.apple.systempreferences")
    else {
      completion(false)
      return
    }
    NSWorkspace.shared.openApplication(
      at: url, configuration: NSWorkspace.OpenConfiguration()
    ) { application, error in
      DispatchQueue.main.async { completion(application != nil && error == nil) }
    }
  }
}
