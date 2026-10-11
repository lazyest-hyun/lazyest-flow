import ApplicationServices
import Darwin
import Foundation
import LazyestCore

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
  InputDeviceRolePolicy.isTrackpad(identity: "Example Magic Trackpad"),
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
        "rules": [
          {"description":"Unrelated rule","manipulators":[]},
          {"description":"Existing input-method rule: right_command to F18","manipulators":[]}
        ]
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
    resetText.contains("Existing input-method rule: right_command to F18"),
    "Setup-owned global F18 rule was removed by device reset")
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
    ), "Second keyboard mapping was removed while resetting the first")
  let finalReset = try KarabinerConfigEditor.resettingWindowsLayout(
    in: firstReset, vendorID: 2, productID: 20)
  check(
    !KarabinerConfigEditor.isWindowsLayoutApplied(
      in: finalReset,
      vendorID: 2,
      productID: 20
    ), "Second keyboard mapping survived its reset")

  let allReset = try KarabinerConfigEditor.resettingAllWindowsLayouts(in: second)
  let allResetText = String(decoding: allReset, as: UTF8.self)
  check(
    !KarabinerConfigEditor.isWindowsLayoutApplied(
      in: allReset,
      vendorID: 1,
      productID: 10
    ), "First Flow-owned keyboard mapping survived complete reset")
  check(
    !KarabinerConfigEditor.isWindowsLayoutApplied(
      in: allReset,
      vendorID: 2,
      productID: 20
    ), "Second Flow-owned keyboard mapping survived complete reset")
  check(
    allResetText.contains("Existing input-method rule: right_command to F18"),
    "Setup-owned global F18 rule was removed by complete Flow reset")
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
  let applied = try KarabinerConfigEditor.applyingWindowsLayout(
    to: malformedKarabiner, vendorID: 1, productID: 2)
  check(
    KarabinerConfigEditor.isWindowsLayoutApplied(in: applied, vendorID: 1, productID: 2),
    "Device mapping was not applied beside an unrelated malformed complex section")
  check(
    String(decoding: applied, as: UTF8.self).contains("\"sentinel\""),
    "Unrelated malformed complex section was changed")
} catch {
  failures.append("Device-only mapping rejected an unrelated complex section: \(error)")
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
  DockEdgeTriggerPolicy.allowsHotCorner(
    at: CGPoint(x: 1919, y: 1079),
    in: dockFrame,
    edge: .bottom,
    activeCorners: [.bottomRight],
    originAtTop: true
  ),
  "Active Quartz bottom-right Hot Corner was blocked")
check(
  DockEdgeTriggerPolicy.allowsHotCorner(
    at: CGPoint(x: 1919, y: 1),
    in: dockFrame,
    edge: .bottom,
    activeCorners: [.bottomRight],
    originAtTop: false
  ),
  "Active AppKit bottom-right Hot Corner was blocked")
check(
  !DockEdgeTriggerPolicy.allowsHotCorner(
    at: CGPoint(x: 960, y: 1079),
    in: dockFrame,
    edge: .bottom,
    activeCorners: [.bottomRight],
    originAtTop: true
  ),
  "Dock pin allowed a non-corner bottom-edge trigger")
check(
  !DockEdgeTriggerPolicy.allowsHotCorner(
    at: CGPoint(x: 1919, y: 1079),
    in: dockFrame,
    edge: .bottom,
    activeCorners: [],
    originAtTop: true
  ),
  "Dock pin allowed an inactive Hot Corner")
check(
  DockEdgeTriggerPolicy.matchingHotCorner(
    at: CGPoint(x: 1, y: 1079),
    in: dockFrame,
    edge: .bottom,
    activeCorners: [.bottomLeft, .bottomRight],
    originAtTop: true
  ) == .bottomLeft,
  "Dock pin did not identify the active bottom-left Hot Corner")
check(
  DockEdgeTriggerPolicy.matchingHotCorner(
    at: CGPoint(x: 1919, y: 1079),
    in: dockFrame,
    edge: .bottom,
    activeCorners: [.bottomLeft, .bottomRight],
    originAtTop: true
  ) == .bottomRight,
  "Dock pin did not identify the active bottom-right Hot Corner")
check(
  DockEdgeTriggerPolicy.matchingHotCorner(
    at: CGPoint(x: 1918, y: 1079),
    in: dockFrame,
    edge: .bottom,
    activeCorners: [.bottomRight],
    originAtTop: true,
    size: 1
  ) == nil,
  "Dock pin allowed more than the exact Hot Corner pixel")
check(
  DockEdgeTriggerPolicy.missionControlArgument(forHotCornerAction: 2) == "0",
  "Mission Control Hot Corner action was not mapped")
check(
  DockEdgeTriggerPolicy.missionControlArgument(forHotCornerAction: 3) == "2",
  "Application Windows Hot Corner action was not mapped")
check(
  DockEdgeTriggerPolicy.missionControlArgument(forHotCornerAction: 4) == "1",
  "Desktop Hot Corner action was not mapped")
check(
  DockEdgeTriggerPolicy.missionControlArgument(forHotCornerAction: 14) == nil,
  "Unsupported Hot Corner action was mapped")
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
  "Legacy login item would restart the Flow after an intentional quit")
var changedLoginItem = LegacyLoginLaunchPolicy.propertyList
changedLoginItem["ProgramArguments"] = [
  "/bin/sh", "-c", "open /Applications/Lazyest Flow.app",
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
check(
  LidSleepPolicy.resolve(
    keepAwakeEnabled: true,
    inputModePolicyEnabled: true,
    isKoreanInputSource: true
  ) == .requestSleep,
  "Korean input mode did not request sleep on lid close")
check(
  LidSleepPolicy.resolve(
    keepAwakeEnabled: true,
    inputModePolicyEnabled: true,
    isKoreanInputSource: false
  ) == .preventSleep,
  "A input mode did not prevent sleep on lid close")
check(
  LidSleepPolicy.resolve(
    keepAwakeEnabled: true,
    inputModePolicyEnabled: false,
    isKoreanInputSource: true
  ) == .preventSleep,
  "Disabled input mode policy did not preserve keep-awake on lid close")
check(
  LidSleepPolicy.resolve(
    keepAwakeEnabled: false,
    inputModePolicyEnabled: true,
    isKoreanInputSource: true
  ) == .followSystem,
  "Disabled keep-awake did not follow the system lid policy")

check(!ShortcutPolicy.hasGlobalActivationModifier([]), "Modifierless shortcut was accepted")
check(!ShortcutPolicy.hasGlobalActivationModifier(["shift"]), "Shift-only shortcut was accepted")
check(ShortcutPolicy.hasGlobalActivationModifier(["ctrl"]), "Control shortcut was rejected")
check(
  ShortcutPolicy.hasGlobalActivationModifier(["shift", "cmd"]), "Command shortcut was rejected")

check(
  ScreenshotShortcutPolicy.shouldSwap(
    keyCode: 20, flags: [.maskCommand, .maskShift], isRepeat: false),
  "Full-screen screenshot not recognized")
check(
  ScreenshotShortcutPolicy.shouldSwap(
    keyCode: 21, flags: [.maskCommand, .maskShift, .maskControl], isRepeat: false),
  "Control region screenshot not recognized")
check(
  !ScreenshotShortcutPolicy.shouldSwap(
    keyCode: 23, flags: [.maskCommand, .maskShift], isRepeat: false),
  "Screenshot toolbar was intercepted")
check(
  !ScreenshotShortcutPolicy.shouldSwap(
    keyCode: 20, flags: [.maskCommand, .maskShift, .maskAlternate], isRepeat: false),
  "Option shortcut was intercepted")
check(
  !ScreenshotShortcutPolicy.shouldSwap(
    keyCode: 20, flags: [.maskCommand, .maskShift], isRepeat: true), "Key repeat was intercepted")
check(
  ScreenshotShortcutPolicy.forwardedFlags([.maskCommand, .maskShift]).contains(.maskControl),
  "Default screenshot did not become clipboard capture")
check(
  !ScreenshotShortcutPolicy.forwardedFlags([.maskCommand, .maskShift, .maskControl]).contains(
    .maskControl), "Control screenshot did not become file capture")
check(
  ScreenshotShortcutPolicy.releaseKeys(triggerKeyCode: 21).contains(59)
    && ScreenshotShortcutPolicy.releaseKeys(triggerKeyCode: 21).contains(62),
  "Physical Control release is not awaited")

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

failures.append(contentsOf: inputRegressionFailures())
check(
  SleepPreventionPolicy.resolve(
    enabled: true, includeBattery: true, onACPower: false, batteryPercent: nil,
    thermalSafetyRequired: false) == .lowBattery, "Unknown battery level did not pause")
check(
  LidInputSourcePolicy.isKnownKorean(sourceIdentifier: "com.apple.inputmethod.Korean.2SetKorean"),
  "Apple Korean input source not recognized")
check(
  !LidInputSourcePolicy.isKnownKorean(sourceIdentifier: "com.apple.keylayout.ABC"),
  "ABC source was misclassified")
check(
  !LidInputSourcePolicy.isKnownKorean(sourceIdentifier: "org.youknowone.inputmethod.Gureum.han2"),
  "Ambiguous third-party source was guessed")
check(
  !LidInputSourcePolicy.isKnownKorean(sourceIdentifier: nil), "Missing input source was guessed")

// fdesetup(8) documents the isactive output / exit-code pairs. Neither
// an unverified command nor FileVault off can establish automatic-login eligibility.
check(
  AutomaticLoginPolicy.fileVaultState(output: "true\n", exitCode: 0) == .on,
  "FileVault on was not confirmed")
check(
  AutomaticLoginPolicy.fileVaultState(output: "false\n", exitCode: 1) == .off,
  "Documented FileVault off result was not confirmed")
for (output, code) in [
  ("", Int32(0)), ("false", 0), ("true", 1), ("permission denied", 1),
  ("true", 2), ("unknown", 0), ("false\nextra", 1),
] {
  check(
    AutomaticLoginPolicy.fileVaultState(output: output, exitCode: code) == .unknown,
    "Unverified FileVault output was trusted: \(output) / \(code)")
}
check(
  AutomaticLoginPolicy.fileVaultState(output: "true", exitCode: 0, timedOut: true) == .unknown,
  "Timed-out FileVault result was trusted")
check(
  AutomaticLoginPolicy.eligibility(fileVault: .on) == .blockedByFileVault,
  "FileVault on did not block startup automatic login")
check(
  AutomaticLoginPolicy.eligibility(fileVault: .off) == .needsSystemSettingsReview,
  "FileVault off bypassed account / management review")
check(
  AutomaticLoginPolicy.eligibility(fileVault: .unknown) == .unknown,
  "Unknown FileVault state was presented as eligible")

if failures.isEmpty {
  print("LAZYEST_CORE_CHECKS_OK")
} else {
  for failure in failures {
    fputs("CHECK FAILED: \(failure)\n", stderr)
  }
  exit(EXIT_FAILURE)
}
