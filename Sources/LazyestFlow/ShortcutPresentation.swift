import Carbon
import Foundation

/// Display only. Registration and persistence always use the original shortcut.
func displayShortcut(_ value: String) -> String {
  guard let shortcut = parseShortcut(value), let name = keyName(for: shortcut.keyCode) else { return value }
  var result = ""
  if shortcut.modifiers & UInt32(controlKey) != 0 { result += "⌃" }
  if shortcut.modifiers & UInt32(optionKey) != 0 { result += "⌥" }
  if shortcut.modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
  if shortcut.modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
  let symbols = ["return": "↩", "enter": "⌅", "tab": "⇥", "space": "Space", "delete": "⌫", "escape": "⎋", "left": "←", "right": "→", "up": "↑", "down": "↓"]
  return result + (symbols[name] ?? name.uppercased())
}
