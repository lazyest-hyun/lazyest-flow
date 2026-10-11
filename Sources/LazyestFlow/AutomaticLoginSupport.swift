import AppKit
import Foundation

/// Supported settings application navigation; never accepts account names or passwords.
enum AutomaticLoginSupport {
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
