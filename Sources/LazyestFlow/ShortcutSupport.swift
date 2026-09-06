import AppKit
import Carbon
import Foundation
import LazyestCore

func stableHotkeyID(for shortcut: ParsedShortcut) -> UInt32 {
  var modifierBits: UInt32 = 0
  if shortcut.modifiers & UInt32(controlKey) != 0 { modifierBits |= 1 << 0 }
  if shortcut.modifiers & UInt32(optionKey) != 0 { modifierBits |= 1 << 1 }
  if shortcut.modifiers & UInt32(shiftKey) != 0 { modifierBits |= 1 << 2 }
  if shortcut.modifiers & UInt32(cmdKey) != 0 { modifierBits |= 1 << 3 }
  return (shortcut.keyCode & 0xFF) | (modifierBits << 8)
}

func parseShortcut(_ value: String) -> ParsedShortcut? {
  let parts = value.lowercased().split(separator: "+", omittingEmptySubsequences: false)
    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
  guard parts.allSatisfy({ !$0.isEmpty }) else { return nil }
  guard let key = parts.last else { return nil }
  let modifierNames = Array(parts.dropLast())
  guard ShortcutPolicy.hasGlobalActivationModifier(modifierNames) else { return nil }
  var modifiers: UInt32 = 0
  for modifier in modifierNames {
    switch modifier {
    case "ctrl", "control": modifiers |= UInt32(controlKey)
    case "opt", "option", "alt": modifiers |= UInt32(optionKey)
    case "cmd", "command": modifiers |= UInt32(cmdKey)
    case "shift": modifiers |= UInt32(shiftKey)
    default: return nil
    }
  }
  guard let keyCode = keyCode(for: key) else { return nil }
  return ParsedShortcut(keyCode: keyCode, modifiers: modifiers)
}

func shortcutString(from event: NSEvent) -> String? {
  guard let key = keyName(for: UInt32(event.keyCode)) else { return nil }
  var parts = modifierParts(from: event)
  guard ShortcutPolicy.hasGlobalActivationModifier(parts) else { return nil }
  parts.append(key)
  return parts.joined(separator: "+")
}

func modifierString(from event: NSEvent) -> String? {
  let parts = modifierParts(from: event)
  return parts.isEmpty ? nil : parts.joined(separator: "+")
}

func modifierParts(from event: NSEvent) -> [String] {
  let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
  var parts: [String] = []
  if flags.contains(.control) { parts.append("ctrl") }
  if flags.contains(.option) { parts.append("opt") }
  if flags.contains(.shift) { parts.append("shift") }
  if flags.contains(.command) { parts.append("cmd") }
  return parts
}

func keyCode(for key: String) -> UInt32? {
  ShortcutPolicy.keyCode(for: key)
}

func keyName(for keyCode: UInt32) -> String? {
  ShortcutPolicy.keyName(for: keyCode)
}

func applicationSupportPath(_ fileName: String) -> String {
  let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("Lazyest Flow", isDirectory: true)
  return base.appendingPathComponent(fileName).path
}

func defaultHotkeys() -> String {
  """
  # Lazyest Flow app hotkeys.
  # Format: toggle-app|shortcut|bundle-id|label|enabled
  # Add, remove, or edit rows from the Flow UI.
  """
}

func defaultBootstrap() -> String {
  """
  APP_HOTKEYS_ENABLED=0
  MOUSE_SCROLL_REVERSE_ENABLED=0
  SCREENSHOT_DIR="auto"
  SCREENSHOT_CLIPBOARD_WATCH=0
  KEEP_AWAKE_ENABLED=0
  KEEP_AWAKE_ON_BATTERY=1
  LOCK_ON_LID_CLOSE=0
  SLEEP_ON_KOREAN_LID_CLOSE=0
  DOCK_ANCHOR_ENABLED=0
  DOCK_ANCHOR_DISPLAY_ID=auto
  """
}

func currentMacOSScreenshotDir() -> String {
  let process = Process()
  let pipe = Pipe()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
  process.arguments = ["read", "com.apple.screencapture", "location"]
  process.standardOutput = pipe
  process.standardError = Pipe()
  do {
    try process.run()
    process.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let value =
      String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if process.terminationStatus == 0, !value.isEmpty {
      return NSString(string: value).expandingTildeInPath
    }
  } catch {
    return NSHomeDirectory() + "/Desktop"
  }
  return NSHomeDirectory() + "/Desktop"
}

func setMacOSScreenshotLocation(_ path: String) -> Bool {
  do {
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
  } catch {
    return false
  }

  let defaults = Process()
  defaults.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
  defaults.arguments = ["write", "com.apple.screencapture", "location", "-string", path]
  defaults.standardOutput = Pipe()
  defaults.standardError = Pipe()
  do {
    try defaults.run()
    defaults.waitUntilExit()
  } catch {
    return false
  }
  guard defaults.terminationStatus == 0 else { return false }

  for processName in ["SystemUIServer", "screencaptureui"] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
    process.arguments = [processName]
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    try? process.run()
    process.waitUntilExit()
  }
  return true
}

func resetMacOSScreenshotLocation() -> Bool {
  let defaults = Process()
  defaults.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
  defaults.arguments = ["delete", "com.apple.screencapture", "location"]
  defaults.standardOutput = Pipe()
  defaults.standardError = Pipe()
  do {
    try defaults.run()
    defaults.waitUntilExit()
  } catch {
    return false
  }
  guard defaults.terminationStatus == 0 || defaults.terminationStatus == 1 else { return false }

  for processName in ["SystemUIServer", "screencaptureui"] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
    process.arguments = [processName]
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    try? process.run()
    process.waitUntilExit()
  }
  return true
}
