import AppKit
import Foundation

struct FlowRemovalOptions {
  let removeSettings: Bool
  let resetDockTiming: Bool
  let resetScreenshotLocation: Bool
  let resetKeyboardMappings: Bool
}

enum FlowRemovalCoordinator {
  static func remove(
    options: FlowRemovalOptions,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    do {
      try LoginLaunchManager.shared.setEnabled(false)
    } catch {
      completion(.failure(error))
      return
    }

    let finish: () -> Void = {
      do {
        if options.resetKeyboardMappings {
          try KeyboardMappingController.shared.resetAll()
        }
        if options.resetScreenshotLocation, !resetMacOSScreenshotLocation() {
          throw RemovalError.screenshotLocationResetFailed
        }
        if options.resetDockTiming {
          try DockAutoHideTiming.setFastEnabled(false)
        }
        try scheduleRemovalAfterTermination(removeSettings: options.removeSettings)
        completion(.success(()))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
          NSApp.terminate(nil)
        }
      } catch {
        completion(.failure(error))
      }
    }

    guard PowerHelperInstaller.isInstalled else {
      finish()
      return
    }
    PowerHelperInstaller.requestRemoval { success, message in
      if success {
        finish()
      } else {
        completion(.failure(RemovalError.helperRemovalFailed(message)))
      }
    }
  }

  private static func scheduleRemovalAfterTermination(removeSettings: Bool) throws {
    let appURL = URL(fileURLWithPath: "/Applications/Lazyest Flow.app").standardizedFileURL
    guard Bundle.main.bundleURL.standardizedFileURL == appURL else {
      throw RemovalError.unexpectedApplicationPath(Bundle.main.bundleURL.path)
    }
    let supportURL = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Lazyest Flow", isDirectory: true)
    var paths = [appURL.path]
    if removeSettings {
      paths.append(supportURL.path)
    }
    let command = "sleep 1; /bin/rm -rf \(paths.map(shellQuote).joined(separator: " "))"
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", command]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
  }

  private static func shellQuote(_ value: String) -> String {
    "'\(value.replacingOccurrences(of: "'", with: "'\\\"'\\\"'"))'"
  }

  private enum RemovalError: LocalizedError {
    case helperRemovalFailed(String?)
    case unexpectedApplicationPath(String)
    case screenshotLocationResetFailed

    var errorDescription: String? {
      switch self {
      case .helperRemovalFailed(let message):
        return message?.isEmpty == false ? message : "Failed to remove the power helper."
      case .unexpectedApplicationPath(let path):
        return "Refusing to remove an application outside /Applications: \(path)"
      case .screenshotLocationResetFailed:
        return "Failed to reset the macOS screenshot location."
      }
    }
  }
}
