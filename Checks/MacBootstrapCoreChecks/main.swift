import ApplicationServices
import Darwin
import Foundation
import MacBootstrapCore

private var failures: [String] = []

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
  if !condition() {
    failures.append(message)
  }
}

private func makeScrollEvent(units: CGScrollEventUnit, value: Int32) -> CGEvent {
  guard
    let event = CGEvent(
      scrollWheelEvent2Source: nil,
      units: units,
      wheelCount: 1,
      wheel1: value,
      wheel2: 0,
      wheel3: 0
    )
  else {
    fatalError("Unable to create scroll event")
  }
  return event
}

private let wheelEvent = makeScrollEvent(units: .line, value: 3)
check(
  WheelScrollPolicy.applyVerticalReverse(to: wheelEvent),
  "Conventional wheel event was not reversed")
check(
  wheelEvent.getIntegerValueField(.scrollWheelEventDeltaAxis1) == -3, "Wheel delta was not reversed"
)

private let controlWheelEvent = makeScrollEvent(units: .line, value: 3)
controlWheelEvent.flags = [.maskControl]
check(
  !WheelScrollPolicy.applyVerticalReverse(to: controlWheelEvent),
  "Control-wheel zoom gesture was modified")
check(
  controlWheelEvent.getIntegerValueField(.scrollWheelEventDeltaAxis1) == 3,
  "Control-wheel delta changed")

private let trackpadEvent = makeScrollEvent(units: .pixel, value: 12)
trackpadEvent.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
trackpadEvent.setIntegerValueField(.scrollWheelEventScrollPhase, value: 1)
private let trackpadValue = trackpadEvent.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
check(!WheelScrollPolicy.applyVerticalReverse(to: trackpadEvent), "Trackpad event was modified")
check(
  trackpadEvent.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) == trackpadValue,
  "Trackpad delta changed")

private let highResolutionMouse = makeScrollEvent(units: .pixel, value: 12)
highResolutionMouse.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
check(
  WheelScrollPolicy.applyVerticalReverse(to: highResolutionMouse, source: .mouse),
  "High-resolution mouse was not reversed")

check(
  InputDeviceRolePolicy.isTrackpad(identity: "Estaid's Magic Trackpad"),
  "Magic Trackpad was not classified")
check(
  !InputDeviceRolePolicy.isTrackpad(identity: "Logitech USB Receiver"),
  "Mouse receiver was classified as a trackpad")
check(
  InputDeviceRolePolicy.confirmsKeyboard(
    primaryUsagePage: 1,
    primaryUsage: 6,
    elementUsagePage: 7,
    isBuiltIn: false,
    isVirtual: false
  ), "External keyboard was not confirmed")
check(
  !InputDeviceRolePolicy.confirmsKeyboard(
    primaryUsagePage: 1,
    primaryUsage: 2,
    elementUsagePage: 7,
    isBuiltIn: false,
    isVirtual: false
  ), "Mouse macro input was classified as a keyboard")

private let karabinerFixture = """
  {
    "profiles": [{
      "name": "Default profile",
      "selected": true,
      "simple_modifications": [],
      "complex_modifications": {
        "rules": [{"description":"Unrelated rule","manipulators":[]}]
      },
      "devices": []
    }]
  }
  """.data(using: .utf8)!

do {
  let applied = try KarabinerConfigEditor.applyingWindowsLayout(
    to: karabinerFixture,
    vendorID: 1133,
    productID: 50503
  )
  check(
    KarabinerConfigEditor.isWindowsLayoutApplied(
      in: applied,
      vendorID: 1133,
      productID: 50503
    ), "Karabiner layout was not applied")

  let reset = try KarabinerConfigEditor.resettingWindowsLayout(
    in: applied,
    vendorID: 1133,
    productID: 50503
  )
  let resetText = String(decoding: reset, as: UTF8.self)
  check(
    !KarabinerConfigEditor.isWindowsLayoutApplied(
      in: reset,
      vendorID: 1133,
      productID: 50503
    ), "Karabiner layout was not reset")
  check(
    !resetText.contains(KarabinerConfigEditor.ownedRuleDescription),
    "Owned global F18 rule survived final reset")
  check(resetText.contains("Unrelated rule"), "Unrelated Karabiner rule was removed")

  let first = try KarabinerConfigEditor.applyingWindowsLayout(
    to: karabinerFixture, vendorID: 1, productID: 10)
  let second = try KarabinerConfigEditor.applyingWindowsLayout(
    to: first, vendorID: 2, productID: 20)
  let firstReset = try KarabinerConfigEditor.resettingWindowsLayout(
    in: second, vendorID: 1, productID: 10)
  check(
    KarabinerConfigEditor.isWindowsLayoutApplied(
      in: firstReset,
      vendorID: 2,
      productID: 20
    ), "Global F18 rule was removed while another mapped keyboard remained")
  let finalReset = try KarabinerConfigEditor.resettingWindowsLayout(
    in: firstReset, vendorID: 2, productID: 20)
  check(
    !String(decoding: finalReset, as: UTF8.self).contains(
      KarabinerConfigEditor.ownedRuleDescription),
    "Global F18 rule survived after the last mapped keyboard was reset")

  let allReset = try KarabinerConfigEditor.resettingAllWindowsLayouts(in: second)
  let allResetText = String(decoding: allReset, as: UTF8.self)
  check(
    !KarabinerConfigEditor.isWindowsLayoutApplied(
      in: allReset,
      vendorID: 1,
      productID: 10
    ), "First Agent-owned keyboard mapping survived complete reset")
  check(
    !KarabinerConfigEditor.isWindowsLayoutApplied(
      in: allReset,
      vendorID: 2,
      productID: 20
    ), "Second Agent-owned keyboard mapping survived complete reset")
  check(
    !allResetText.contains(KarabinerConfigEditor.ownedRuleDescription),
    "Agent-owned global F18 rule survived complete reset")
  check(
    allResetText.contains("Unrelated rule"),
    "Unrelated Karabiner rule was removed by complete reset"
  )
} catch {
  failures.append("Karabiner round-trip failed: \(error)")
}

private let malformedKarabiner = """
  {"profiles":[{"selected":true,"complex_modifications":{"rules":{"sentinel":"keep"}}}]}
  """.data(using: .utf8)!
do {
  _ = try KarabinerConfigEditor.applyingWindowsLayout(
    to: malformedKarabiner, vendorID: 1, productID: 2)
  failures.append("Malformed Karabiner nested section was accepted")
} catch {
  // Expected: malformed nested sections must fail closed before writing.
}

private let dockFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
check(
  DockEdgeTriggerPolicy.triggerZone(in: dockFrame, edge: .bottom, thickness: 10)
    .contains(CGPoint(x: 960, y: 1079)), "Dock bottom trigger zone is incorrect")
check(
  DockEdgeTriggerPolicy.approachPoint(in: dockFrame, edge: .bottom) == CGPoint(x: 960, y: 1030),
  "Dock bottom approach point is incorrect")
check(
  DockEdgeTriggerPolicy.pressurePoint(in: dockFrame, edge: .left) == CGPoint(x: -20, y: 540),
  "Dock left pressure point is incorrect")
check(
  DockEdgeTriggerPolicy.pressurePoint(in: dockFrame, edge: .right) == CGPoint(x: 1940, y: 540),
  "Dock right pressure point is incorrect")

check(
  RuntimeFeatureStatePolicy.resolve(requested: false, active: false) == .off,
  "Inactive feature did not resolve to off")
check(
  RuntimeFeatureStatePolicy.resolve(requested: true, active: true) == .active,
  "Active feature did not resolve to active")
check(
  RuntimeFeatureStatePolicy.resolve(requested: true, active: false) == .unavailable,
  "Failed feature was not exposed")
check(
  RuntimeFeatureStatePolicy.resolve(requested: false, active: true) == .unavailable,
  "Residual runtime activity was hidden")

check(
  LegacyLoginLaunchPolicy.isManagedPropertyList(LegacyLoginLaunchPolicy.propertyList),
  "Generated legacy login item property list was rejected")
check(
  LegacyLoginLaunchPolicy.propertyList["KeepAlive"] == nil,
  "Legacy login item would restart the Agent after an intentional quit")
var changedLoginItem = LegacyLoginLaunchPolicy.propertyList
changedLoginItem["ProgramArguments"] = [
  "/bin/sh", "-c", "open /Applications/MacBootstrapAgent.app",
]
check(
  !LegacyLoginLaunchPolicy.isManagedPropertyList(changedLoginItem),
  "A shell-based legacy login item was accepted")
var persistentLoginItem = LegacyLoginLaunchPolicy.propertyList
persistentLoginItem["KeepAlive"] = true
check(
  !LegacyLoginLaunchPolicy.isManagedPropertyList(persistentLoginItem),
  "A persistent legacy login item was accepted")

check(
  SleepPreventionPolicy.resolve(
    enabled: false,
    includeBattery: true,
    onACPower: false,
    batteryPercent: 80,
    thermalSafetyRequired: false
  ) == .disabled, "Disabled sleep prevention became active")
check(
  SleepPreventionPolicy.resolve(
    enabled: true,
    includeBattery: false,
    onACPower: false,
    batteryPercent: 80,
    thermalSafetyRequired: false
  ) == .waitingForPower, "Power-only mode remained active on battery")
check(
  SleepPreventionPolicy.resolve(
    enabled: true,
    includeBattery: true,
    onACPower: false,
    batteryPercent: 20,
    thermalSafetyRequired: false
  ) == .lowBattery, "Low-battery cutoff was not applied")
check(
  SleepPreventionPolicy.resolve(
    enabled: true,
    includeBattery: true,
    onACPower: true,
    batteryPercent: 10,
    thermalSafetyRequired: false
  ) == .active, "AC power was incorrectly blocked by battery level")
check(
  SleepPreventionPolicy.resolve(
    enabled: true,
    includeBattery: true,
    onACPower: true,
    batteryPercent: 80,
    thermalSafetyRequired: true
  ) == .thermalSafety, "Thermal safety did not pause sleep prevention")

check(
  !LidStatePolicy.isClosed(clamshellMessageArgument: 0),
  "An open clamshell message was decoded as closed")
check(
  LidStatePolicy.isClosed(clamshellMessageArgument: 1),
  "A closed clamshell message was decoded as open")
check(
  !LidStatePolicy.isClosed(clamshellMessageArgument: 2),
  "The clamshell sleep-policy bit was decoded as the physical lid state")
check(
  LidStatePolicy.isClosed(clamshellMessageArgument: 3),
  "A closed clamshell message with the sleep-policy bit was decoded as open")

check(!ShortcutPolicy.hasGlobalActivationModifier([]), "Modifierless shortcut was accepted")
check(!ShortcutPolicy.hasGlobalActivationModifier(["shift"]), "Shift-only shortcut was accepted")
check(ShortcutPolicy.hasGlobalActivationModifier(["ctrl"]), "Control shortcut was rejected")
check(
  ShortcutPolicy.hasGlobalActivationModifier(["shift", "cmd"]), "Command shortcut was rejected")

check(
  ScreenshotFilePolicy.acceptsEncodedByteCount(1024), "Normal screenshot byte count was rejected")
check(!ScreenshotFilePolicy.acceptsEncodedByteCount(0), "Empty screenshot was accepted")
check(
  !ScreenshotFilePolicy.acceptsEncodedByteCount(ScreenshotFilePolicy.maxEncodedBytes + 1),
  "Oversized screenshot was accepted")
check(
  ScreenshotFilePolicy.acceptsImage(width: 5120, height: 2880, frameCount: 1),
  "Normal screenshot dimensions were rejected")
check(
  ScreenshotFilePolicy.shouldCreatePNGCompatibilityImage(width: 5120, height: 2880),
  "Normal screenshot was denied PNG compatibility conversion")
check(
  ScreenshotFilePolicy.acceptsImage(width: 8000, height: 4000, frameCount: 1),
  "Large native screenshot was rejected")
check(
  !ScreenshotFilePolicy.shouldCreatePNGCompatibilityImage(width: 8000, height: 4000),
  "Large screenshot was allowed to allocate a PNG compatibility image")
check(
  !ScreenshotFilePolicy.acceptsImage(width: 100_000, height: 100_000, frameCount: 1),
  "Oversized screenshot dimensions were accepted")
check(
  !ScreenshotFilePolicy.acceptsImage(width: 100, height: 100, frameCount: 2),
  "Multi-frame screenshot was accepted")

if failures.isEmpty {
  print("MAC_BOOTSTRAP_CORE_CHECKS_OK")
} else {
  for failure in failures {
    fputs("CHECK FAILED: \(failure)\n", stderr)
  }
  exit(EXIT_FAILURE)
}
