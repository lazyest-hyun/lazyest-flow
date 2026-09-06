import ApplicationServices
import Foundation
import LazyestCore

func inputRegressionFailures() -> [String] {
  var failures: [String] = []
  func check(_ condition: Bool, _ message: String) {
    if !condition { failures.append(message) }
  }

  if let event = CGEvent(
    scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
    wheel1: 12, wheel2: 0, wheel3: 0
  ) {
    event.setIntegerValueField(.scrollWheelEventScrollPhase, value: 1)
    check(
      !WheelScrollPolicy.applyVerticalReverse(to: event, source: .mouse),
      "Recent mouse input caused a trackpad gesture to reverse")
    event.setIntegerValueField(.scrollWheelEventScrollPhase, value: 0)
    event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 1)
    check(
      !WheelScrollPolicy.applyVerticalReverse(to: event, source: .mouse),
      "Recent mouse input caused trackpad momentum to reverse")
    event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 0)
    event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
    check(
      !WheelScrollPolicy.applyVerticalReverse(to: event),
      "Unidentified continuous input was treated as a physical mouse wheel")
    check(
      WheelScrollPolicy.applyVerticalReverse(to: event, source: .mouse),
      "Identified high-resolution mouse wheel stopped reversing")
  } else {
    failures.append("Unable to create an input-policy test event")
  }

  for (korean, latin) in [
    ("ㅐ", "o"), ("ㅕ", "u"), ("ㅔ", "p"), ("ㅜ", "n"), ("ㅡ", "m"),
  ] {
    check(
      ShortcutPolicy.keyCode(for: korean) == ShortcutPolicy.keyCode(for: latin),
      "Korean shortcut \(korean) does not match the physical \(latin) key")
  }
  check(ShortcutPolicy.keyCode(for: "ㅢ") == nil, "A composed vowel was treated as one key")
  for key in ["a", "p", "m", "1", "space", "escape"] {
    guard let code = ShortcutPolicy.keyCode(for: key) else {
      failures.append("Shortcut key \(key) disappeared")
      continue
    }
    check(ShortcutPolicy.keyName(for: code) == key, "Shortcut key \(key) did not round-trip")
  }

  let fixture = Data(
    """
    {"profiles":[{"name":"Default","selected":true,"devices":[]}]}
    """.utf8)
  do {
    let first = try KarabinerConfigEditor.applyingWindowsLayout(
      to: fixture, vendorID: 1, productID: 10)
    let both = try KarabinerConfigEditor.applyingWindowsLayout(
      to: first, vendorID: 2, productID: 20)
    let scopedReset = try KarabinerConfigEditor.resettingAllWindowsLayouts(
      in: both, devices: [(vendorID: 1, productID: 10)])
    check(
      !KarabinerConfigEditor.isWindowsLayoutApplied(in: scopedReset, vendorID: 1, productID: 10),
      "Tracked keyboard survived Flow's complete reset")
    check(
      KarabinerConfigEditor.isWindowsLayoutApplied(in: scopedReset, vendorID: 2, productID: 20),
      "Flow's complete reset removed an untracked keyboard's matching layout")

    // Simulate the user customizing one modifier after enabling the preset.
    var root = try JSONSerialization.jsonObject(with: first) as! [String: Any]
    var profiles = root["profiles"] as! [[String: Any]]
    var devices = profiles[0]["devices"] as! [[String: Any]]
    var modifications = devices[0]["simple_modifications"] as! [[String: Any]]
    modifications[0] = [
      "from": ["key_code": "left_option"],
      "to": [["key_code": "escape"]],
    ]
    devices[0]["simple_modifications"] = modifications
    profiles[0]["devices"] = devices
    root["profiles"] = profiles
    let customized = try JSONSerialization.data(withJSONObject: root)
    let reset = try KarabinerConfigEditor.resettingWindowsLayout(
      in: customized, vendorID: 1, productID: 10)
    check(
      String(decoding: reset, as: UTF8.self).contains("escape"),
      "Reset deleted a modifier mapping the user had customized")
    check(
      !String(decoding: reset, as: UTF8.self).contains("right_option"),
      "Reset left an unchanged Flow modifier mapping behind")
    do {
      _ = try KarabinerConfigEditor.applyingWindowsLayout(
        to: customized, vendorID: 1, productID: 10)
      failures.append("Applying the preset silently overwrote a custom modifier mapping")
    } catch KarabinerConfigEditorError.conflictingModifierMapping {
      // The user keeps their custom mapping and can resolve it in Karabiner.
    }

    modifications[0] = [
      "from": ["key_code": "left_option"],
      "to": [["key_code": "left_command"], ["key_code": "escape"]],
    ]
    devices[0]["simple_modifications"] = modifications
    profiles[0]["devices"] = devices
    root["profiles"] = profiles
    let multiAction = try JSONSerialization.data(withJSONObject: root)
    check(
      !KarabinerConfigEditor.isWindowsLayoutApplied(in: multiAction, vendorID: 1, productID: 10),
      "A multi-action modifier was reported as Flow's exact layout")
  } catch {
    failures.append("Input regression fixture failed: \(error)")
  }
  return failures
}
