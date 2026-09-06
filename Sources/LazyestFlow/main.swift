import AppKit
import Darwin
import Foundation

if let previewIndex = CommandLine.arguments.firstIndex(of: "--render-previews") {
  guard CommandLine.arguments.indices.contains(previewIndex + 1) else {
    fputs("Usage: LazyestFlow --render-previews OUTPUT_DIRECTORY [ko|en]\n", stderr)
    exit(2)
  }
  let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  do {
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }
    flowPreviewLanguage = CommandLine.arguments.last == "en" ? .english : .korean
    _ = NSApplication.shared
    let preview = SettingsWindowController(
      config: Config(
        hotkeyPath: temporary.appendingPathComponent("hotkeys.conf").path,
        bootstrapPath: temporary.appendingPathComponent("bootstrap.conf").path),
      previewMode: true,
      dockPinStatusProvider: { .off },
      screenshotStatusProvider: { true },
      keepAwakeStatusProvider: {
        .active(PowerSnapshot(onACPower: true, batteryPercent: nil, charging: false))
      })
    try preview.renderPreviews(to: URL(fileURLWithPath: CommandLine.arguments[previewIndex + 1]))
    print("LAZYEST_FLOW_PREVIEWS_OK")
    exit(0)
  } catch {
    fputs("Preview rendering failed: \(error.localizedDescription)\n", stderr)
    exit(1)
  }
}

if CommandLine.arguments.contains("--register-power-helper") {
  exit(PowerHelperMaintenance.register())
}

if CommandLine.arguments.contains("--install-power-helper-as-root") {
  exit(PowerHelperMaintenance.installAsRoot())
}

if CommandLine.arguments.contains("--remove-power-helper-as-root") {
  exit(PowerHelperMaintenance.removeAsRoot())
}

if CommandLine.arguments.contains("--unregister-power-helper") {
  exit(PowerHelperMaintenance.uninstall())
}

if CommandLine.arguments.contains("--disable-power-helper") {
  exit(PowerHelperMaintenance.disable())
}

if CommandLine.arguments.contains("--power-helper-is-registered") {
  exit(PowerHelperMaintenance.isRegistered())
}

if CommandLine.arguments.contains("--enable-login-launch") {
  exit(LoginLaunchMaintenance.setEnabled(true))
}

if CommandLine.arguments.contains("--refresh-login-launch") {
  exit(LoginLaunchMaintenance.setEnabled(true, refreshRegistration: true))
}

if CommandLine.arguments.contains("--disable-login-launch") {
  exit(LoginLaunchMaintenance.setEnabled(false))
}

if CommandLine.arguments.contains("--login-launch-is-enabled") {
  exit(LoginLaunchMaintenance.isEnabled())
}

if CommandLine.arguments.contains("--login-launch-status") {
  print(LoginLaunchMaintenance.statusText())
  exit(0)
}

let supportedRuntimeArguments: Set<String> = ["--login-launch"]
if let unsupported = CommandLine.arguments.dropFirst().first(where: {
  $0.hasPrefix("--") && !supportedRuntimeArguments.contains($0)
}) {
  fputs("Unknown option: \(unsupported)\n", stderr)
  exit(2)
}

// Keep one runtime instance even when a user starts a second local build.
// Maintenance and offscreen preview commands above deliberately do not take this lock.
let runtimeLockURL = FileManager.default.temporaryDirectory
  .appendingPathComponent("com.lazyest.flow.\(getuid()).runtime.lock")
let runtimeLock = open(runtimeLockURL.path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
guard runtimeLock >= 0 else {
  fputs("Unable to create the Flow runtime lock.\n", stderr)
  exit(1)
}
guard flock(runtimeLock, LOCK_EX | LOCK_NB) == 0 else {
  guard errno == EWOULDBLOCK else {
    fputs("Unable to acquire the Flow runtime lock.\n", stderr)
    exit(1)
  }
  NSRunningApplication.runningApplications(withBundleIdentifier: "com.lazyest.flow")
    .first(where: { $0.processIdentifier != getpid() })?
    .activate(options: [.activateIgnoringOtherApps])
  exit(0)
}

let hotkeyPath = applicationSupportPath("hotkeys.conf")
let bootstrapPath = applicationSupportPath("bootstrap.conf")
let config = Config(hotkeyPath: hotkeyPath, bootstrapPath: bootstrapPath)
let launchedAtLogin = CommandLine.arguments.contains("--login-launch")
Flow(config: config, launchedAtLogin: launchedAtLogin).run()
