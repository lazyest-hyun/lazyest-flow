import Foundation

enum ConfigError: LocalizedError {
  case invalidHotkeyField

  var errorDescription: String? {
    switch self {
    case .invalidHotkeyField:
      return "Hotkey fields cannot contain line breaks or the pipe character."
    }
  }
}

struct AppBinding {
  var shortcut: String
  var bundleID: String
  var label: String
  var isEnabled: Bool
}

enum HotkeyAction {
  case toggleApp(AppBinding)
}

struct ParsedShortcut {
  let keyCode: UInt32
  let modifiers: UInt32
}

final class Config {
  let hotkeyPath: String
  let bootstrapPath: String
  private(set) var appHotkeysEnabled: Bool
  private(set) var mouseScrollReverseEnabled: Bool
  private(set) var screenshotDir: String
  private(set) var screenshotClipboardWatch: Bool
  private(set) var keepAwakeEnabled: Bool
  private(set) var keepAwakeOnBattery: Bool
  private(set) var lockOnLidClose: Bool
  private(set) var dockPinEnabled: Bool
  private(set) var dockPinDisplayID: UInt32?

  init(hotkeyPath: String, bootstrapPath: String) {
    self.hotkeyPath = hotkeyPath
    self.bootstrapPath = bootstrapPath
    self.appHotkeysEnabled = false
    self.mouseScrollReverseEnabled = false
    self.screenshotDir = currentMacOSScreenshotDir()
    self.screenshotClipboardWatch = false
    self.keepAwakeEnabled = false
    self.keepAwakeOnBattery = true
    self.lockOnLidClose = false
    self.dockPinEnabled = false
    self.dockPinDisplayID = currentDisplayID()
    ensureConfigFiles()
    loadBootstrap()
    syncScreenshotDirFromSystem()
  }

  func loadBindings() throws -> [AppBinding] {
    let content = try String(contentsOfFile: hotkeyPath, encoding: .utf8)
    return content.split(separator: "\n").compactMap { rawLine in
      let line = rawLine.trimmingCharacters(in: .whitespaces)
      guard !line.isEmpty, !line.hasPrefix("#") else { return nil }
      let parts = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
      guard (4...5).contains(parts.count), parts[0] == "toggle-app" else { return nil }
      return AppBinding(
        shortcut: parts[1].trimmingCharacters(in: .whitespaces),
        bundleID: parts[2].trimmingCharacters(in: .whitespaces),
        label: parts[3].trimmingCharacters(in: .whitespaces),
        isEnabled: parts.count < 5 || parts[4] == "1" || parts[4].lowercased() == "true"
      )
    }
  }

  func saveBindings(_ bindings: [AppBinding]) throws {
    try saveHotkeys(appBindings: bindings)
  }

  func saveHotkeys(appBindings: [AppBinding]) throws {
    guard
      appBindings.allSatisfy({ binding in
        [binding.shortcut, binding.bundleID, binding.label].allSatisfy(isValidHotkeyField)
      })
    else {
      throw ConfigError.invalidHotkeyField
    }
    let header = """
      # MacBootstrapAgent app hotkeys.
      # Format: toggle-app|shortcut|bundle-id|label|enabled
      # Add, remove, or edit rows from the Agent UI.

      """
    let appBody = appBindings.map {
      "toggle-app|\($0.shortcut)|\($0.bundleID)|\($0.label)|\($0.isEnabled ? "1" : "0")"
    }
    let body = appBody.joined(separator: "\n")
    try (header + body + (body.isEmpty ? "" : "\n")).write(
      toFile: hotkeyPath, atomically: true, encoding: .utf8)
  }

  func saveBootstrap(
    appHotkeysEnabled: Bool,
    mouseScrollReverseEnabled: Bool,
    screenshotDir: String,
    screenshotClipboardWatch: Bool,
    keepAwakeEnabled: Bool,
    keepAwakeOnBattery: Bool,
    lockOnLidClose: Bool,
    dockPinEnabled: Bool,
    dockPinDisplayID: UInt32?
  ) throws {
    self.appHotkeysEnabled = appHotkeysEnabled
    self.mouseScrollReverseEnabled = mouseScrollReverseEnabled
    self.screenshotDir = resolveScreenshotDir(screenshotDir)
    self.screenshotClipboardWatch = screenshotClipboardWatch
    self.keepAwakeEnabled = keepAwakeEnabled
    self.keepAwakeOnBattery = keepAwakeOnBattery
    self.lockOnLidClose = lockOnLidClose
    self.dockPinEnabled = dockPinEnabled
    self.dockPinDisplayID = dockPinDisplayID
    let encodedScreenshotDir = try encodeConfigString(screenshotDir)
    let content = """
      APP_HOTKEYS_ENABLED=\(appHotkeysEnabled ? "1" : "0")
      MOUSE_SCROLL_REVERSE_ENABLED=\(mouseScrollReverseEnabled ? "1" : "0")
      SCREENSHOT_DIR=\(encodedScreenshotDir)
      SCREENSHOT_CLIPBOARD_WATCH=\(screenshotClipboardWatch ? "1" : "0")
      KEEP_AWAKE_ENABLED=\(keepAwakeEnabled ? "1" : "0")
      KEEP_AWAKE_ON_BATTERY=\(keepAwakeOnBattery ? "1" : "0")
      LOCK_ON_LID_CLOSE=\(lockOnLidClose ? "1" : "0")
      DOCK_ANCHOR_ENABLED=\(dockPinEnabled ? "1" : "0")
      DOCK_ANCHOR_DISPLAY_ID=\(dockPinDisplayID.map(String.init) ?? "auto")
      """
    try content.write(toFile: bootstrapPath, atomically: true, encoding: .utf8)
  }

  func setKeepAwakeEnabled(_ enabled: Bool) throws {
    try updateRuntimeSettings(keepAwakeEnabled: enabled)
  }

  func setKeepAwakeOnBattery(_ enabled: Bool) throws {
    try updateRuntimeSettings(keepAwakeOnBattery: enabled)
  }

  func setLockOnLidClose(_ enabled: Bool) throws {
    try updateRuntimeSettings(lockOnLidClose: enabled)
  }

  func setAppHotkeysEnabled(_ enabled: Bool) throws {
    try updateRuntimeSettings(appHotkeysEnabled: enabled)
  }

  func setScreenshotClipboardWatch(_ enabled: Bool) throws {
    try updateRuntimeSettings(screenshotClipboardWatch: enabled)
  }

  func setDockPinEnabled(_ enabled: Bool) throws {
    try updateRuntimeSettings(dockPinEnabled: enabled)
  }

  private func updateRuntimeSettings(
    appHotkeysEnabled: Bool? = nil,
    screenshotClipboardWatch: Bool? = nil,
    keepAwakeEnabled: Bool? = nil,
    keepAwakeOnBattery: Bool? = nil,
    lockOnLidClose: Bool? = nil,
    dockPinEnabled: Bool? = nil
  ) throws {
    try saveBootstrap(
      appHotkeysEnabled: appHotkeysEnabled ?? self.appHotkeysEnabled,
      mouseScrollReverseEnabled: mouseScrollReverseEnabled,
      screenshotDir: screenshotDir,
      screenshotClipboardWatch: screenshotClipboardWatch ?? self.screenshotClipboardWatch,
      keepAwakeEnabled: keepAwakeEnabled ?? self.keepAwakeEnabled,
      keepAwakeOnBattery: keepAwakeOnBattery ?? self.keepAwakeOnBattery,
      lockOnLidClose: lockOnLidClose ?? self.lockOnLidClose,
      dockPinEnabled: dockPinEnabled ?? self.dockPinEnabled,
      dockPinDisplayID: dockPinDisplayID
    )
  }

  func reloadBootstrap() {
    appHotkeysEnabled = false
    mouseScrollReverseEnabled = false
    screenshotDir = currentMacOSScreenshotDir()
    screenshotClipboardWatch = false
    keepAwakeEnabled = false
    keepAwakeOnBattery = true
    lockOnLidClose = false
    dockPinEnabled = false
    dockPinDisplayID = currentDisplayID()
    loadBootstrap()
    syncScreenshotDirFromSystem()
  }

  func syncScreenshotDirFromSystem() {
    screenshotDir = currentMacOSScreenshotDir()
  }

  private func ensureConfigFiles() {
    let dir = URL(fileURLWithPath: hotkeyPath).deletingLastPathComponent().path
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    if !FileManager.default.fileExists(atPath: hotkeyPath) {
      try? defaultHotkeys().write(toFile: hotkeyPath, atomically: true, encoding: .utf8)
    }
    if !FileManager.default.fileExists(atPath: bootstrapPath) {
      try? defaultBootstrap().write(toFile: bootstrapPath, atomically: true, encoding: .utf8)
    }
  }

  private func loadBootstrap() {
    guard let content = try? String(contentsOfFile: bootstrapPath, encoding: .utf8) else { return }
    for rawLine in content.split(separator: "\n") {
      let line = rawLine.trimmingCharacters(in: .whitespaces)
      if line.hasPrefix("APP_HOTKEYS_ENABLED="), let value = shellValue(line) {
        appHotkeysEnabled = value == "1" || value.lowercased() == "true"
      } else if line.hasPrefix("MOUSE_SCROLL_REVERSE_ENABLED="), let value = shellValue(line) {
        mouseScrollReverseEnabled = value == "1" || value.lowercased() == "true"
      } else if line.hasPrefix("SCREENSHOT_DIR="), let value = shellValue(line) {
        screenshotDir = resolveScreenshotDir(value)
      } else if line.hasPrefix("SCREENSHOT_CLIPBOARD_WATCH="), let value = shellValue(line) {
        screenshotClipboardWatch = value == "1" || value.lowercased() == "true"
      } else if line.hasPrefix("KEEP_AWAKE_ENABLED="), let value = shellValue(line) {
        keepAwakeEnabled = value == "1" || value.lowercased() == "true"
      } else if line.hasPrefix("KEEP_AWAKE_ON_BATTERY="), let value = shellValue(line) {
        keepAwakeOnBattery = value == "1" || value.lowercased() == "true"
      } else if line.hasPrefix("LOCK_ON_LID_CLOSE="), let value = shellValue(line) {
        lockOnLidClose = value == "1" || value.lowercased() == "true"
      } else if line.hasPrefix("DOCK_ANCHOR_ENABLED="), let value = shellValue(line) {
        dockPinEnabled = value == "1" || value.lowercased() == "true"
      } else if line.hasPrefix("DOCK_ANCHOR_DISPLAY_ID="), let value = shellValue(line) {
        dockPinDisplayID = UInt32(value)
      }
    }
  }

  private func shellValue(_ line: String) -> String? {
    guard let equals = line.firstIndex(of: "=") else { return nil }
    let raw = String(line[line.index(after: equals)...])
    let value = decodeConfigString(raw)
    if value == "$HOME" {
      return NSHomeDirectory()
    }
    if value.hasPrefix("$HOME/") {
      return NSHomeDirectory() + String(value.dropFirst("$HOME".count))
    }
    return value
  }

  private func resolveScreenshotDir(_ value: String) -> String {
    if value.lowercased() == "auto" || value.isEmpty {
      return currentMacOSScreenshotDir()
    }
    return NSString(string: value).expandingTildeInPath
  }

  private func encodeConfigString(_ value: String) throws -> String {
    let data = try JSONEncoder().encode(value)
    guard let encoded = String(data: data, encoding: .utf8) else {
      throw CocoaError(.fileWriteInapplicableStringEncoding)
    }
    return encoded
  }

  private func decodeConfigString(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespaces)
    if let data = trimmed.data(using: .utf8),
      let decoded = try? JSONDecoder().decode(String.self, from: data)
    {
      return decoded
    }
    return trimmed
  }

  private func isValidHotkeyField(_ value: String) -> Bool {
    !value.contains("|") && !value.contains("\n") && !value.contains("\r")
  }
}
