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
  let parts = value.lowercased().split(separator: "+").map(String.init)
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
  guard !parts.isEmpty else { return nil }
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
  let map: [String: UInt32] = [
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
    "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
    "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
    "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
    "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37,
    "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44,
    "n": 45, "m": 46, ".": 47, "`": 50, "space": 49, "escape": 53,
    "ㅁ": 0, "ㄴ": 1, "ㅇ": 2, "ㄹ": 3, "ㅗ": 4, "ㅎ": 5, "ㅋ": 6, "ㅌ": 7,
    "ㅊ": 8, "ㅍ": 9, "ㅠ": 11, "ㅂ": 12, "ㅈ": 13, "ㄷ": 14, "ㄱ": 15,
    "ㅛ": 16, "ㅅ": 17, "ㅕ": 31, "ㅜ": 32, "ㅔ": 33, "ㅑ": 34, "ㅐ": 35,
    "ㅣ": 37, "ㅓ": 38, "ㅏ": 40, "ㅡ": 45, "ㅢ": 46,
  ]
  return map[key]
}

func keyName(for keyCode: UInt32) -> String? {
  let map: [UInt32: String] = [
    0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x",
    8: "c", 9: "v", 11: "b", 12: "q", 13: "w", 14: "e", 15: "r",
    16: "y", 17: "t", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
    23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
    30: "]", 31: "o", 32: "u", 33: "[", 34: "i", 35: "p", 37: "l",
    38: "j", 39: "'", 40: "k", 41: ";", 42: "\\", 43: ",", 44: "/",
    45: "n", 46: "m", 47: ".", 49: "space", 50: "`", 53: "escape",
  ]
  return map[keyCode]
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
