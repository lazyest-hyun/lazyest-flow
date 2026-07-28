import AppKit
import ApplicationServices
import CoreServices
import Darwin
import Foundation
import IOKit.pwr_mgt
import ImageIO
import LazyestCore

final class DockPinController {
  private struct DisplayInfo {
    let id: UInt32
    let frame: CGRect
  }

  private struct BlockedDisplayRegion {
    let displayID: UInt32
    let frame: CGRect
    let triggerZone: CGRect
  }

  private struct HotCornerBinding {
    let action: Int
    let requiredModifiers: CGEventFlags
  }

  private final class RelocationToken {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
      lock.lock()
      defer { lock.unlock() }
      return cancelled
    }

    func cancel() {
      lock.lock()
      cancelled = true
      lock.unlock()
    }
  }

  private let config: Config
  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var observers: [NSObjectProtocol] = []
  private var availableDisplays: [DisplayInfo] = []
  private var blockedDisplayRegions: [BlockedDisplayRegion] = []
  private var cachedTargetDisplayID: UInt32?
  private var cachedTargetQuartzFrame: CGRect?
  private var cachedDockEdge: DockEdge = .bottom
  private var hotCornerBindings: [ScreenCorner: HotCornerBinding] = [:]
  private var isMonitoring = false
  private var dockIsOnTarget = false
  private(set) var status: DockPinStatus = .off
  private var cachedDockOrientation = "bottom"
  private var permissionTimer: Timer?
  private var hasLoadedInitialState = false
  private var wasEnabled = false
  private var lastConfiguredTargetDisplayID: UInt32?
  private var pendingRelocation = false
  private var isRelocating = false
  private var relocationToken: RelocationToken?
  private var blockStatusVisible = false
  private var lastBlockedMovementUptime: TimeInterval = 0
  private var blockStatusResetWork: DispatchWorkItem?
  private var hotCornerActionLatched = false
  private let syntheticEventMarker: Int64 = 0xD0C4_A5C4
  private let dockTriggerSize: CGFloat = 10
  private let hotCornerZoneSize: CGFloat = 1
  private let hotCornerModifierMask: CGEventFlags = [
    .maskShift, .maskControl, .maskAlternate, .maskCommand,
  ]

  init(config: Config) {
    self.config = config
  }

  var isActive: Bool {
    isMonitoring && eventTap.map(CFMachPortIsValid) == true && dockIsOnTarget
  }

  func reload() {
    config.reloadBootstrap()
    let enabled = config.dockPinEnabled
    let targetChanged =
      hasLoadedInitialState
      && lastConfiguredTargetDisplayID != config.dockPinDisplayID
    if enabled, (hasLoadedInitialState && !wasEnabled) || targetChanged {
      pendingRelocation = true
    }
    lastConfiguredTargetDisplayID = config.dockPinDisplayID
    hasLoadedInitialState = true
    wasEnabled = enabled

    if enabled {
      refreshDisplays()
      cachedDockOrientation = dockOrientation()
      rebuildBlockedDisplayRegions()
      if !isMonitoring {
        startMonitoring()
      }
      if pendingRelocation, isMonitoring {
        pendingRelocation = false
        relocateDockToTarget()
      } else {
        refreshDockPlacementState()
      }
    } else {
      pendingRelocation = false
      stop()
      postStatus(.off)
    }
  }

  func stop(keepPermissionMonitoring: Bool = false) {
    let wasRelocating = isRelocating
    relocationToken?.cancel()
    relocationToken = nil
    isMonitoring = false
    isRelocating = false
    dockIsOnTarget = false
    if wasRelocating {
      NSCursor.unhide()
    }
    blockStatusVisible = false
    lastBlockedMovementUptime = 0
    hotCornerActionLatched = false
    blockStatusResetWork?.cancel()
    blockStatusResetWork = nil
    if let eventTap {
      CGEvent.tapEnable(tap: eventTap, enable: false)
      CFMachPortInvalidate(eventTap)
      self.eventTap = nil
    }
    if let runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
      self.runLoopSource = nil
    }
    for observer in observers {
      NotificationCenter.default.removeObserver(observer)
    }
    observers.removeAll()
    if !keepPermissionMonitoring {
      permissionTimer?.invalidate()
      permissionTimer = nil
    }
  }

  private func startMonitoring() {
    guard !isMonitoring else { return }
    guard AXIsProcessTrusted() else {
      let options =
        [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
      AXIsProcessTrustedWithOptions(options)
      NSLog("Dock pin needs Accessibility permission")
      postStatus(.needsPermission)
      startPermissionMonitoring()
      return
    }
    refreshDisplays()
    guard targetDisplayID() != nil else {
      NSLog("Dock pin has no valid target display")
      postStatus(.failed)
      return
    }
    cachedDockOrientation = dockOrientation()
    rebuildBlockedDisplayRegions()
    let eventTypes: [CGEventType] = [
      .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
    ]
    let eventMask = eventTypes.reduce(CGEventMask(0)) { mask, type in
      mask | CGEventMask(1 << type.rawValue)
    }
    let callback: CGEventTapCallBack = { _, type, event, context in
      guard let context else { return Unmanaged.passUnretained(event) }
      let controller = Unmanaged<DockPinController>.fromOpaque(context).takeUnretainedValue()
      if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let eventTap = controller.eventTap, controller.isMonitoring {
          CGEvent.tapEnable(tap: eventTap, enable: true)
        }
        NSLog("Dock pin event tap recovered after disable event \(type.rawValue)")
        controller.postCurrentStatus()
        return Unmanaged.passUnretained(event)
      }
      return controller.handleMouseEvent(type: type, event: event)
    }
    eventTap = createEventTap(eventMask: eventMask, callback: callback)
    guard let eventTap else {
      NSLog("Failed to create Dock pin event tap")
      postStatus(.failed)
      startPermissionMonitoring()
      return
    }

    runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
    guard let runLoopSource else {
      self.eventTap = nil
      postStatus(.failed)
      return
    }
    CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    isMonitoring = true
    CGEvent.tapEnable(tap: eventTap, enable: true)
    refreshDockPlacementState()
    addLifecycleObservers()
    startPermissionMonitoring()
    NSLog("Dock pin event tap active")
    postCurrentStatus()
  }

  private func createEventTap(
    eventMask: CGEventMask,
    callback: @escaping CGEventTapCallBack
  ) -> CFMachPort? {
    CGEvent.tapCreate(
      tap: .cgSessionEventTap,
      place: .headInsertEventTap,
      options: .defaultTap,
      eventsOfInterest: eventMask,
      callback: callback,
      userInfo: Unmanaged.passUnretained(self).toOpaque()
    )
  }

  private func startPermissionMonitoring() {
    permissionTimer?.invalidate()
    permissionTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
      self?.verifyPermissionsAndTapValidity()
    }
  }

  private func verifyPermissionsAndTapValidity() {
    guard config.dockPinEnabled else { return }
    refreshHotCornerBindings()
    let currentOrientation = dockOrientation()
    if currentOrientation != cachedDockOrientation {
      cachedDockOrientation = currentOrientation
      rebuildBlockedDisplayRegions()
    }
    guard AXIsProcessTrusted() else {
      stop(keepPermissionMonitoring: true)
      postStatus(.needsPermission)
      return
    }
    if !isMonitoring || eventTap == nil {
      startMonitoring()
      return
    }
    if let eventTap, !CFMachPortIsValid(eventTap) {
      stop(keepPermissionMonitoring: true)
      startMonitoring()
      return
    }
    if !isRelocating, let targetID = targetDisplayID(), let currentID = currentDockDisplayID() {
      if currentID != targetID {
        dockIsOnTarget = false
        postStatus(.moveFailed)
      } else if !dockIsOnTarget {
        dockIsOnTarget = true
        postCurrentStatus()
      }
    }
  }

  private func refreshDockPlacementState() {
    guard let targetID = targetDisplayID(), let currentID = currentDockDisplayID() else {
      dockIsOnTarget = false
      return
    }
    dockIsOnTarget = currentID == targetID
  }

  private func postCurrentStatus() {
    postStatus(dockIsOnTarget ? .active : .moveFailed)
  }

  private func postStatus(_ value: DockPinStatus) {
    status = value
    NotificationCenter.default.post(name: dockPinStatusNotification, object: value)
  }

  private func addLifecycleObservers() {
    let displayObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      guard let self else { return }
      self.config.reloadBootstrap()
      self.refreshDisplays()
      self.cachedDockOrientation = self.dockOrientation()
      self.rebuildBlockedDisplayRegions()
      self.refreshDockPlacementState()
      if self.targetDisplayID() == nil {
        self.postStatus(.failed)
      } else {
        self.postCurrentStatus()
      }
    }
    observers = [displayObserver]
  }

  private func handleMouseEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
    guard
      type == .mouseMoved || type == .leftMouseDragged || type == .rightMouseDragged
        || type == .otherMouseDragged
    else {
      return Unmanaged.passUnretained(event)
    }
    if isRelocating {
      return event.getIntegerValueField(.eventSourceUserData) == syntheticEventMarker
        ? Unmanaged.passUnretained(event)
        : nil
    }
    guard isMonitoring else { return Unmanaged.passUnretained(event) }
    guard shouldBlockDockTrigger(at: event.location, flags: event.flags) else {
      return Unmanaged.passUnretained(event)
    }
    return nil
  }

  private func shouldBlockDockTrigger(at location: CGPoint, flags: CGEventFlags) -> Bool {
    guard let targetID = cachedTargetDisplayID else { return false }
    if cachedTargetQuartzFrame?.contains(location) == true {
      hotCornerActionLatched = false
      return false
    }
    for region in blockedDisplayRegions {
      if region.triggerZone.contains(location) {
        let corner = DockEdgeTriggerPolicy.matchingHotCorner(
          at: location,
          in: region.frame,
          edge: cachedDockEdge,
          activeCorners: Set(hotCornerBindings.keys),
          originAtTop: true,
          size: hotCornerZoneSize
        )
        if let corner, let binding = hotCornerBindings[corner],
          hotCornerModifiersMatch(binding.requiredModifiers, eventFlags: flags)
        {
          if !hotCornerActionLatched {
            hotCornerActionLatched = true
            triggerNativeHotCornerAction(binding.action)
          }
          return true
        }
        reportBlockedMovement(
          displayID: region.displayID,
          targetID: targetID,
          edge: cachedDockEdge,
          location: location
        )
        return true
      }
    }
    hotCornerActionLatched = false
    return false
  }

  private func hotCornerModifiersMatch(
    _ requiredModifiers: CGEventFlags,
    eventFlags: CGEventFlags
  ) -> Bool {
    eventFlags.intersection(hotCornerModifierMask)
      == requiredModifiers.intersection(hotCornerModifierMask)
  }

  private func triggerNativeHotCornerAction(_ action: Int) {
    guard
      let argument = DockEdgeTriggerPolicy.missionControlArgument(forHotCornerAction: action)
    else {
      NSLog("Dock pin blocked unsupported Hot Corner action \(action)")
      return
    }

    let applicationURL = URL(fileURLWithPath: "/System/Applications/Mission Control.app")
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.arguments = [argument]
    NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration) {
      _, error in
      if let error {
        NSLog("Dock pin failed to invoke Hot Corner action \(action): \(error)")
      }
    }
  }

  private func reportBlockedMovement(
    displayID: UInt32,
    targetID: UInt32,
    edge: DockEdge,
    location: CGPoint
  ) {
    lastBlockedMovementUptime = ProcessInfo.processInfo.systemUptime
    guard !blockStatusVisible else { return }

    blockStatusVisible = true
    NSLog(
      "Dock pin blocked trigger display=\(displayID) target=\(targetID) "
        + "edge=\(edge.rawValue) location=(\(location.x),\(location.y))"
    )
    postStatus(.blocked)
    scheduleBlockedStatusReset(after: 1.0)
  }

  private func scheduleBlockedStatusReset(after delay: TimeInterval) {
    blockStatusResetWork?.cancel()
    let work = DispatchWorkItem { [weak self] in
      guard let self, self.isMonitoring, self.config.dockPinEnabled else { return }
      let elapsed = ProcessInfo.processInfo.systemUptime - self.lastBlockedMovementUptime
      if elapsed < 1.0 {
        self.scheduleBlockedStatusReset(after: 1.0 - elapsed)
        return
      }
      self.blockStatusResetWork = nil
      self.blockStatusVisible = false
      self.postCurrentStatus()
    }
    blockStatusResetWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + max(0.05, delay), execute: work)
  }

  private func rebuildBlockedDisplayRegions() {
    refreshHotCornerBindings()
    cachedTargetDisplayID = targetDisplayID()
    cachedDockEdge = DockEdge(rawValue: cachedDockOrientation) ?? .bottom
    guard let targetID = cachedTargetDisplayID,
      let targetDisplay = availableDisplays.first(where: { $0.id == targetID })
    else {
      cachedTargetQuartzFrame = nil
      blockedDisplayRegions = []
      return
    }
    cachedTargetQuartzFrame = targetDisplay.frame
    blockedDisplayRegions = availableDisplays.compactMap { display in
      guard display.id != targetID else { return nil }
      return BlockedDisplayRegion(
        displayID: display.id,
        frame: display.frame,
        triggerZone: DockEdgeTriggerPolicy.triggerZone(
          in: display.frame,
          edge: cachedDockEdge,
          thickness: dockTriggerSize
        )
      )
    }
  }

  private func refreshHotCornerBindings() {
    let domain = "com.apple.dock" as CFString
    let keys: [(String, String, ScreenCorner)] = [
      ("wvous-tl-corner", "wvous-tl-modifier", .topLeft),
      ("wvous-tr-corner", "wvous-tr-modifier", .topRight),
      ("wvous-bl-corner", "wvous-bl-modifier", .bottomLeft),
      ("wvous-br-corner", "wvous-br-modifier", .bottomRight),
    ]
    hotCornerBindings = Dictionary(
      uniqueKeysWithValues: keys.compactMap { actionKey, modifierKey, corner in
        guard
          let action = CFPreferencesCopyAppValue(actionKey as CFString, domain) as? NSNumber,
          action.intValue >= 2
        else { return nil }
        let modifier =
          CFPreferencesCopyAppValue(modifierKey as CFString, domain) as? NSNumber
        return (
          corner,
          HotCornerBinding(
            action: action.intValue,
            requiredModifiers: CGEventFlags(rawValue: modifier?.uint64Value ?? 0)
          )
        )
      }
    )
  }

  private func relocateDockToTarget() {
    guard !isRelocating,
      availableDisplays.count > 1,
      let targetID = targetDisplayID(),
      let targetDisplay = availableDisplays.first(where: { $0.id == targetID })
    else {
      return
    }
    let frame = targetDisplay.frame
    guard frame.width > 0, frame.height > 0 else {
      postStatus(.failed)
      return
    }

    let edge = DockEdge(rawValue: cachedDockOrientation) ?? .bottom
    let approach = DockEdgeTriggerPolicy.approachPoint(in: frame, edge: edge)
    let trigger = DockEdgeTriggerPolicy.triggerPoint(in: frame, edge: edge)
    let original = CGEvent(source: nil)?.location ?? .zero
    let eventSource = CGEventSource(stateID: .hidSystemState)
    let token = RelocationToken()

    isRelocating = true
    dockIsOnTarget = false
    relocationToken = token
    postStatus(.relocating)
    NSCursor.hide()

    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self else {
        CGWarpMouseCursorPosition(original)
        if !token.isCancelled {
          DispatchQueue.main.async { NSCursor.unhide() }
        }
        return
      }

      guard !token.isCancelled else { return }
      CGWarpMouseCursorPosition(approach)
      Thread.sleep(forTimeInterval: 0.03)
      for step in 0..<8 {
        guard !token.isCancelled else { break }
        let progress = CGFloat(step) / 7.0
        let point = CGPoint(
          x: approach.x + (trigger.x - approach.x) * progress,
          y: approach.y + (trigger.y - approach.y) * progress
        )
        self.postDockMove(point, source: eventSource, token: token)
        Thread.sleep(forTimeInterval: 0.015)
      }
      if !token.isCancelled {
        for _ in 0..<8 {
          guard !token.isCancelled else { break }
          self.postDockMove(trigger, source: eventSource, token: token)
          Thread.sleep(forTimeInterval: 0.025)
        }
      }
      CGWarpMouseCursorPosition(original)

      DispatchQueue.main.async {
        if !token.isCancelled {
          NSCursor.unhide()
        }
        guard self.relocationToken === token else { return }
        self.relocationToken = nil
        self.isRelocating = false
        if !token.isCancelled {
          self.verifyRelocation(targetID: targetID)
        }
      }
    }
  }

  private func verifyRelocation(targetID: UInt32) {
    guard config.dockPinEnabled else {
      postStatus(.off)
      return
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
      guard let self, self.config.dockPinEnabled else { return }
      guard let currentID = self.currentDockDisplayID() else {
        NSLog("Dock relocation could not verify the current Dock display")
        self.dockIsOnTarget = false
        self.postStatus(.moveFailed)
        return
      }
      if currentID == targetID {
        self.dockIsOnTarget = true
        self.postStatus(.active)
      } else {
        self.dockIsOnTarget = false
        NSLog("Dock relocation failed: current=\(currentID) target=\(targetID)")
        self.postStatus(.moveFailed)
      }
    }
  }

  private func postDockMove(_ point: CGPoint, source: CGEventSource?, token: RelocationToken) {
    guard !token.isCancelled else { return }
    CGWarpMouseCursorPosition(point)
    guard
      let event = CGEvent(
        mouseEventSource: source,
        mouseType: .mouseMoved,
        mouseCursorPosition: point,
        mouseButton: .left
      )
    else { return }
    guard !token.isCancelled else { return }
    event.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
    event.post(tap: .cghidEventTap)
  }

  private func targetDisplayID() -> UInt32? {
    if let configured = config.dockPinDisplayID,
      availableDisplays.contains(where: { $0.id == configured })
    {
      return configured
    }
    let mainID = CGMainDisplayID()
    return availableDisplays.contains(where: { $0.id == mainID })
      ? mainID : availableDisplays.first?.id
  }

  private func refreshDisplays() {
    let maxDisplays: UInt32 = 16
    var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplays))
    var displayCount: UInt32 = 0
    guard CGGetActiveDisplayList(maxDisplays, &displayIDs, &displayCount) == .success else {
      availableDisplays = []
      return
    }
    availableDisplays = displayIDs.prefix(Int(displayCount)).compactMap { id in
      let frame = CGDisplayBounds(id)
      guard frame.width > 0, frame.height > 0 else { return nil }
      return DisplayInfo(id: id, frame: frame)
    }
  }

  private func currentDockDisplayID() -> UInt32? {
    if let id = currentDockDisplayIDFromWindowServer() {
      return id
    }
    guard
      let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock")
        .first
    else {
      return nil
    }
    let dockElement = AXUIElementCreateApplication(dockApp.processIdentifier)
    var windowsValue: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(dockElement, kAXWindowsAttribute as CFString, &windowsValue)
        == .success,
      let windows = windowsValue as? [AXUIElement]
    else {
      return nil
    }
    for window in windows {
      var positionValue: CFTypeRef?
      guard
        AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue)
          == .success,
        let positionValue,
        CFGetTypeID(positionValue) == AXValueGetTypeID()
      else {
        continue
      }
      var position = CGPoint.zero
      guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position) else {
        continue
      }
      for display in availableDisplays {
        if display.frame.contains(position) {
          return display.id
        }
      }
    }
    return nil
  }

  private func dockOrientation() -> String {
    let value =
      CFPreferencesCopyAppValue(
        "orientation" as CFString,
        "com.apple.dock" as CFString
      ) as? String
    guard let value, ["bottom", "left", "right"].contains(value) else {
      return "bottom"
    }
    return value
  }
}

final class ScreenshotWatcher {
  private enum InteractiveCaptureMode {
    case selection
    case window
  }

  private struct ImageFile {
    let path: String
    let modificationDate: Date
  }

  private struct PendingFile {
    let nextRetryAt: Date
    let attempts: Int
  }

  private struct ClipboardPayload {
    let sourceType: NSPasteboard.PasteboardType
    let sourceData: Data
    let pngData: Data?
  }

  private enum CopyResult {
    case copied
    case retry
    case rejected
  }

  private enum PreparationResult {
    case ready(ClipboardPayload)
    case retry
    case rejected
  }

  private let config: Config
  private var timer: Timer?
  private var shortcutTap: EventTapHost?
  private var shortcutMouseTap: EventTapHost?
  private var directorySource: DispatchSourceFileSystemObject?
  private var scheduledScan: DispatchWorkItem?
  private var scheduledRetry: DispatchWorkItem?
  private var seenPaths: Set<String> = []
  private var pendingPaths: [String: PendingFile] = [:]
  private var isScanning = false
  private var isRunning = false
  private var monitoringGeneration: UInt64 = 0
  private var monitoringStartedAt = Date.distantFuture
  private var interactiveCaptureMode: InteractiveCaptureMode?
  private var interactivePasteboardChangeCount: Int?
  private var selectionStart: CGPoint?
  private var selectedWindowID: CGWindowID?
  private var immediatelyCopiedCaptures: [Date] = []
  private var nativeCaptureSequence: UInt64 = 0
  private let screenshotPreviewController = ScreenshotPreviewController()
  private let screenshotControlQueue = DispatchQueue(
    label: "com.lazyest.flow.screenshot-control",
    qos: .userInteractive
  )
  private let nativeCaptureMarker: Int64 = 0x4C_46_4E_43
  private let imageExtensions = Set(["png", "jpg", "jpeg", "tif", "tiff", "heic"])
  private let maxRetryCount = 50
  private let trackedFileLifetime: TimeInterval = 120

  init(config: Config) {
    self.config = config
  }

  var isActive: Bool {
    isRunning && config.screenshotClipboardWatch
  }

  func start() {
    stop()
    isRunning = true
    monitoringStartedAt = Date()
    seenPaths.removeAll(keepingCapacity: true)
    pendingPaths.removeAll(keepingCapacity: true)
    immediatelyCopiedCaptures.removeAll(keepingCapacity: true)
    startShortcutMonitor()
    startDirectoryMonitor()
    scan()

    let timer = Timer(timeInterval: 30.0, repeats: true) { [weak self] _ in
      self?.scan()
    }
    timer.tolerance = 5.0
    self.timer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  func stop() {
    monitoringGeneration &+= 1
    isRunning = false
    isScanning = false
    timer?.invalidate()
    timer = nil
    shortcutTap?.stop()
    shortcutTap = nil
    shortcutMouseTap?.stop()
    shortcutMouseTap = nil
    interactiveCaptureMode = nil
    interactivePasteboardChangeCount = nil
    selectionStart = nil
    selectedWindowID = nil
    scheduledScan?.cancel()
    scheduledScan = nil
    scheduledRetry?.cancel()
    scheduledRetry = nil
    directorySource?.cancel()
    directorySource = nil
    seenPaths.removeAll(keepingCapacity: true)
    pendingPaths.removeAll()
    immediatelyCopiedCaptures.removeAll()
    nativeCaptureSequence &+= 1
  }

  func reload() {
    config.reloadBootstrap()
    if config.screenshotClipboardWatch {
      start()
    } else {
      stop()
    }
  }

  private func scan() {
    guard isRunning, config.screenshotClipboardWatch else { return }
    guard !isScanning else { return }
    isScanning = true
    let generation = monitoringGeneration
    let cutoff = max(
      monitoringStartedAt,
      Date().addingTimeInterval(-trackedFileLifetime)
    )
    DispatchQueue.global(qos: .utility).async { [weak self] in
      guard let self else { return }
      let files = self.currentImageFiles(modifiedAfter: cutoff)
      DispatchQueue.main.async {
        guard self.monitoringGeneration == generation else { return }
        guard self.isRunning else {
          self.isScanning = false
          return
        }
        let currentPaths = Set(files.map(\.path))
        self.seenPaths.formIntersection(currentPaths)
        self.pendingPaths = self.pendingPaths.filter { currentPaths.contains($0.key) }

        let unseenFiles = files.filter { !self.seenPaths.contains($0.path) }
        guard let nextFile = unseenFiles.first else {
          self.isScanning = false
          return
        }

        let now = Date()
        if self.consumeImmediateCopy(matching: nextFile.modificationDate, now: now) {
          self.seenPaths.insert(nextFile.path)
          self.pendingPaths.removeValue(forKey: nextFile.path)
          self.isScanning = false
          self.scheduleScan(after: 0.01)
          return
        }
        if let pending = self.pendingPaths[nextFile.path], pending.nextRetryAt > now {
          self.isScanning = false
          self.scheduleScan(after: pending.nextRetryAt.timeIntervalSince(now))
          return
        }

        self.prepareImageForClipboard(path: nextFile.path, generation: generation)
      }
    }
  }

  private func startShortcutMonitor() {
    let keyMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
    let keyTap = EventTapHost(eventMask: keyMask) { [weak self] type, event in
      guard let self else { return Unmanaged.passUnretained(event) }
      guard type == .keyDown else { return Unmanaged.passUnretained(event) }
      if event.getIntegerValueField(.eventSourceUserData) == self.nativeCaptureMarker {
        return Unmanaged.passUnretained(event)
      }
      if self.shouldReplaceScreenshotShortcut(event) {
        self.beginNativeClipboardAndPreviewCapture(event)
        return nil
      }
      self.handleScreenshotShortcutEvent(type: type, event: event)
      return Unmanaged.passUnretained(event)
    }
    guard keyTap.start() else { return }
    shortcutTap = keyTap

    let mouseTypes: [CGEventType] = [.leftMouseDown, .leftMouseUp]
    let mouseMask = mouseTypes.reduce(CGEventMask(0)) { partial, type in
      partial | CGEventMask(1 << type.rawValue)
    }
    let mouseTap = EventTapHost(eventMask: mouseMask, options: .listenOnly) {
      [weak self] type, event in
      self?.handleScreenshotShortcutEvent(type: type, event: event)
      return Unmanaged.passUnretained(event)
    }
    guard mouseTap.start() else {
      keyTap.stop()
      shortcutTap = nil
      return
    }
    shortcutMouseTap = mouseTap
  }

  private func shouldReplaceScreenshotShortcut(_ event: CGEvent) -> Bool {
    let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
    let flags = event.flags
    return flags.contains(.maskCommand)
      && flags.contains(.maskShift)
      && !flags.contains(.maskControl)
      && (keyCode == 20 || keyCode == 21)
  }

  private func beginNativeClipboardAndPreviewCapture(_ event: CGEvent) {
    let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
    let flags = event.flags
    nativeCaptureSequence &+= 1
    let sequence = nativeCaptureSequence
    let pasteboardChangeCount = NSPasteboard.general.changeCount

    if keyCode == 21 {
      interactiveCaptureMode = .selection
      interactivePasteboardChangeCount = pasteboardChangeCount
      selectionStart = nil
      selectedWindowID = nil
    } else {
      resetInteractiveCapture()
    }

    screenshotControlQueue.async { [weak self] in
      guard let self, self.isCurrentNativeCapture(sequence) else { return }

      let keyReleaseDeadline = Date().addingTimeInterval(1.5)
      while Date() < keyReleaseDeadline,
        self.screenshotShortcutKeysArePressed(triggerKeyCode: keyCode),
        self.isCurrentNativeCapture(sequence)
      {
        usleep(5_000)
      }
      guard
        self.isCurrentNativeCapture(sequence),
        !self.screenshotShortcutKeysArePressed(triggerKeyCode: keyCode)
      else { return }

      usleep(120_000)
      guard self.isCurrentNativeCapture(sequence) else { return }
      self.postKey(
        keyCode: keyCode,
        flags: flags.union(.maskControl),
        userData: self.nativeCaptureMarker
      )

      guard keyCode == 20 else { return }
      let pngData = self.waitForNativeClipboardImage(
        from: pasteboardChangeCount,
        sequence: sequence
      )
      guard self.isCurrentNativeCapture(sequence) else { return }
      guard let pngData else {
        NSLog("LazyestFlow screenshot: native clipboard did not expose image data")
        return
      }
      self.saveAndPreviewNativeCapture(pngData, sequence: sequence)
    }
  }

  private func screenshotShortcutKeysArePressed(triggerKeyCode: CGKeyCode) -> Bool {
    let keyCodes: [CGKeyCode] = [triggerKeyCode, 54, 55, 56, 60]
    return keyCodes.contains {
      CGEventSource.keyState(.combinedSessionState, key: $0)
    }
  }

  private func isCurrentNativeCapture(_ sequence: UInt64) -> Bool {
    DispatchQueue.main.sync {
      isRunning && nativeCaptureSequence == sequence
    }
  }

  private func waitForNativeClipboardImage(
    from initialChangeCount: Int,
    sequence: UInt64
  ) -> Data? {
    let deadline = Date().addingTimeInterval(1.5)
    while Date() < deadline, isCurrentNativeCapture(sequence) {
      let pngData: Data? = DispatchQueue.main.sync {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != initialChangeCount else { return nil }
        if let pngData = pasteboard.data(forType: .png) {
          return pngData
        }
        guard
          let tiffData = pasteboard.data(forType: .tiff),
          let representation = NSBitmapImageRep(data: tiffData)
        else {
          return nil
        }
        return representation.representation(using: .png, properties: [:])
      }
      if let pngData { return pngData }
      usleep(5_000)
    }
    return nil
  }

  private func postKey(
    keyCode: CGKeyCode,
    flags: CGEventFlags,
    userData: Int64 = 0
  ) {
    let source = CGEventSource(stateID: .combinedSessionState)
    guard
      let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
      let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
    else { return }
    keyDown.flags = flags
    keyUp.flags = flags
    keyDown.setIntegerValueField(.eventSourceUserData, value: userData)
    keyUp.setIntegerValueField(.eventSourceUserData, value: userData)
    keyDown.post(tap: .cghidEventTap)
    keyUp.post(tap: .cghidEventTap)
  }

  private func handleScreenshotShortcutEvent(type: CGEventType, event: CGEvent) {
    switch type {
    case .keyDown:
      handleScreenshotKeyDown(event)
    case .leftMouseDown:
      guard let mode = interactiveCaptureMode else { return }
      if mode == .window {
        selectedWindowID = windowID(at: event.location)
      } else {
        selectionStart = event.location
      }
    case .leftMouseUp:
      completeInteractiveCapture(at: event.location)
    default:
      break
    }
  }

  private func handleScreenshotKeyDown(_ event: CGEvent) {
    let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
    guard interactiveCaptureMode != nil else { return }
    switch keyCode {
    case 49:
      interactiveCaptureMode = interactiveCaptureMode == .selection ? .window : .selection
      selectionStart = nil
      selectedWindowID = nil
    case 53:
      resetInteractiveCapture()
    default:
      break
    }
  }

  private func completeInteractiveCapture(at end: CGPoint) {
    guard let mode = interactiveCaptureMode else { return }
    let start = selectionStart
    let windowID = selectedWindowID
    let pasteboardChangeCount = interactivePasteboardChangeCount
    let sequence = nativeCaptureSequence
    resetInteractiveCapture()

    switch mode {
    case .selection:
      guard let start else { return }
      let rect = CGRect(
        x: min(start.x, end.x),
        y: min(start.y, end.y),
        width: abs(end.x - start.x),
        height: abs(end.y - start.y)
      ).integral
      guard rect.width >= 2, rect.height >= 2 else { return }
      NSLog("LazyestFlow screenshot: selection complete %@", rectangleArgument(rect))
      finishInteractiveNativeCapture(
        pasteboardChangeCount: pasteboardChangeCount,
        sequence: sequence
      )
    case .window:
      guard let windowID else { return }
      NSLog("LazyestFlow screenshot: window complete %u", windowID)
      finishInteractiveNativeCapture(
        pasteboardChangeCount: pasteboardChangeCount,
        sequence: sequence
      )
    }
  }

  private func finishInteractiveNativeCapture(
    pasteboardChangeCount: Int?,
    sequence: UInt64
  ) {
    guard let pasteboardChangeCount else { return }
    screenshotControlQueue.async { [weak self] in
      guard let self, self.isCurrentNativeCapture(sequence) else { return }
      let pngData = self.waitForNativeClipboardImage(
        from: pasteboardChangeCount,
        sequence: sequence
      )
      guard self.isCurrentNativeCapture(sequence) else { return }
      guard let pngData else {
        NSLog("LazyestFlow screenshot: interactive clipboard did not expose image data")
        return
      }
      self.saveAndPreviewNativeCapture(pngData, sequence: sequence)
    }
  }

  private func saveAndPreviewNativeCapture(_ pngData: Data, sequence: UInt64) {
    guard let fileURL = nextScreenshotFileURL() else { return }
    do {
      try pngData.write(to: fileURL, options: .atomic)
    } catch {
      return
    }
    let capturedAt = Date()
    DispatchQueue.main.async { [weak self] in
      guard let self, self.isRunning, self.nativeCaptureSequence == sequence else { return }
      self.immediatelyCopiedCaptures.append(capturedAt)
      self.screenshotPreviewController.show(pngData: pngData, fileURL: fileURL)
      self.scan()
    }
  }

  private func nextScreenshotFileURL() -> URL? {
    let directory = URL(fileURLWithPath: config.screenshotDir, isDirectory: true)
    let defaults = UserDefaults(suiteName: "com.apple.screencapture")
    let configuredName = defaults?.string(forKey: "name")?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let fallbackName =
      Locale.current.language.languageCode?.identifier == "ko"
      ? "스크린샷"
      : "Screen Shot"
    let prefix = configuredName?.isEmpty == false ? configuredName! : fallbackName

    let formatter = DateFormatter()
    formatter.locale = Locale.current
    formatter.dateFormat = "yyyy-MM-dd a h.mm.ss"
    let stem = "\(prefix) \(formatter.string(from: Date()))"

    let fileManager = FileManager.default
    for suffix in 0..<100 {
      let name = suffix == 0 ? "\(stem).png" : "\(stem)(\(suffix + 1)).png"
      let candidate = directory.appendingPathComponent(name)
      if !fileManager.fileExists(atPath: candidate.path) {
        return candidate
      }
    }
    return nil
  }

  private func rectangleArgument(_ rect: CGRect) -> String {
    "\(Int(rect.origin.x)),\(Int(rect.origin.y)),\(Int(rect.width)),\(Int(rect.height))"
  }

  private func resetInteractiveCapture() {
    interactiveCaptureMode = nil
    interactivePasteboardChangeCount = nil
    selectionStart = nil
    selectedWindowID = nil
  }

  private func windowID(at point: CGPoint) -> CGWindowID? {
    guard
      let windows = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
      ) as? [[CFString: Any]]
    else { return nil }

    let ignoredOwners = Set([
      "LazyestFlow", "Screenshot", "Window Server", "Dock", "Control Center",
    ])
    for window in windows {
      guard let layer = window[kCGWindowLayer] as? NSNumber, layer.intValue == 0,
        let owner = window[kCGWindowOwnerName] as? String, !ignoredOwners.contains(owner),
        let bounds = window[kCGWindowBounds] as? NSDictionary,
        let windowID = window[kCGWindowNumber] as? NSNumber
      else { continue }
      var rect = CGRect.zero
      guard CGRectMakeWithDictionaryRepresentation(bounds as CFDictionary, &rect),
        rect.contains(point)
      else {
        continue
      }
      return CGWindowID(windowID.uint32Value)
    }
    return nil
  }

  private func consumeImmediateCopy(matching modificationDate: Date, now: Date) -> Bool {
    immediatelyCopiedCaptures.removeAll { now.timeIntervalSince($0) > 20 }
    guard
      let index = immediatelyCopiedCaptures.firstIndex(where: {
        abs(modificationDate.timeIntervalSince($0)) <= 15
      })
    else { return false }
    immediatelyCopiedCaptures.remove(at: index)
    return true
  }

  private func prepareImageForClipboard(path: String, generation: UInt64) {
    DispatchQueue.global(qos: .utility).async { [weak self] in
      guard let self else { return }
      let result = autoreleasepool {
        self.prepareClipboardPayload(path: path)
      }
      DispatchQueue.main.async {
        guard self.isRunning, self.monitoringGeneration == generation else { return }
        let copyResult: CopyResult
        switch result {
        case .ready(let payload):
          copyResult = self.publishToClipboard(payload) ? .copied : .retry
        case .retry:
          copyResult = .retry
        case .rejected:
          copyResult = .rejected
        }
        self.completeCopy(path: path, result: copyResult, generation: generation)
      }
    }
  }

  private func completeCopy(path: String, result: CopyResult, generation: UInt64) {
    switch result {
    case .copied, .rejected:
      seenPaths.insert(path)
      pendingPaths.removeValue(forKey: path)
      isScanning = false
      scheduleScan(after: 0.01)
    case .retry:
      let attempts = (pendingPaths[path]?.attempts ?? 0) + 1
      if attempts >= maxRetryCount {
        seenPaths.insert(path)
        pendingPaths.removeValue(forKey: path)
        isScanning = false
        scheduleScan(after: 0.01)
      } else {
        let delay = min(0.02 * pow(1.25, Double(attempts - 1)), 0.2)
        pendingPaths[path] = PendingFile(
          nextRetryAt: Date().addingTimeInterval(delay),
          attempts: attempts
        )
        scheduleRetry(path: path, generation: generation, after: delay)
      }
    }
  }

  private func scheduleRetry(path: String, generation: UInt64, after delay: TimeInterval) {
    scheduledRetry?.cancel()
    let workItem = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.scheduledRetry = nil
      guard self.isRunning, self.monitoringGeneration == generation,
        self.pendingPaths[path] != nil
      else {
        self.isScanning = false
        return
      }
      self.prepareImageForClipboard(path: path, generation: generation)
    }
    scheduledRetry = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + max(0.01, delay), execute: workItem)
  }

  private func startDirectoryMonitor() {
    let descriptor = Darwin.open(config.screenshotDir, O_EVTONLY)
    guard descriptor >= 0 else { return }
    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: descriptor,
      eventMask: [.write, .extend, .rename, .delete],
      queue: DispatchQueue.global(qos: .utility)
    )
    source.setEventHandler { [weak self] in
      DispatchQueue.main.async {
        self?.scheduleScan(after: 0.01)
      }
    }
    source.setCancelHandler {
      Darwin.close(descriptor)
    }
    directorySource = source
    source.resume()
  }

  private func scheduleScan(after delay: TimeInterval) {
    guard isRunning else { return }
    scheduledScan?.cancel()
    let workItem = DispatchWorkItem { [weak self] in
      self?.scheduledScan = nil
      self?.scan()
    }
    scheduledScan = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + max(0.01, delay), execute: workItem)
  }

  private func currentImageFiles(modifiedAfter cutoff: Date) -> [ImageFile] {
    let dir = config.screenshotDir
    guard
      let urls = try? FileManager.default.contentsOfDirectory(
        at: URL(fileURLWithPath: dir),
        includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
        options: [.skipsHiddenFiles]
      )
    else { return [] }
    return
      urls
      .compactMap { url -> ImageFile? in
        guard imageExtensions.contains(url.pathExtension.lowercased()),
          let values = try? url.resourceValues(forKeys: [
            .isRegularFileKey, .contentModificationDateKey,
          ]),
          values.isRegularFile == true,
          let modificationDate = values.contentModificationDate,
          modificationDate >= cutoff
        else { return nil }
        return ImageFile(path: url.path, modificationDate: modificationDate)
      }
      .sorted {
        if $0.modificationDate == $1.modificationDate {
          return $0.path < $1.path
        }
        return $0.modificationDate < $1.modificationDate
      }
  }

  private func prepareClipboardPayload(path: String) -> PreparationResult {
    let url = URL(fileURLWithPath: path)
    let fileExtension = url.pathExtension.lowercased()
    guard imageExtensions.contains(fileExtension) else { return .rejected }
    let sourceType: NSPasteboard.PasteboardType
    switch fileExtension {
    case "png":
      sourceType = .png
    case "jpg", "jpeg":
      sourceType = NSPasteboard.PasteboardType("public.jpeg")
    case "tif", "tiff":
      sourceType = .tiff
    case "heic":
      sourceType = NSPasteboard.PasteboardType("public.heic")
    default:
      return .rejected
    }

    guard let isScreenCapture = isScreenCapture(path: url.path) else { return .retry }
    guard isScreenCapture else { return .rejected }

    guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
      values.isRegularFile == true,
      let fileSize = values.fileSize
    else { return .retry }
    guard ScreenshotFilePolicy.acceptsEncodedByteCount(fileSize) else { return .rejected }
    guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { return .retry }
    guard hasCompleteFileTrailer(data, fileExtension: fileExtension),
      let source = CGImageSourceCreateWithData(data as CFData, nil)
    else { return .retry }
    let frameCount = CGImageSourceGetCount(source)
    guard CGImageSourceGetStatus(source) == .statusComplete else { return .retry }
    guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
      let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
      ScreenshotFilePolicy.acceptsImage(width: width, height: height, frameCount: frameCount)
    else {
      return .rejected
    }

    var pngData: Data?
    if sourceType != .png,
      ScreenshotFilePolicy.shouldCreatePNGCompatibilityImage(width: width, height: height)
    {
      guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        return .retry
      }
      let representation = NSBitmapImageRep(cgImage: cgImage)
      pngData = representation.representation(using: .png, properties: [:])
    }

    return .ready(
      ClipboardPayload(sourceType: sourceType, sourceData: data, pngData: pngData)
    )
  }

  private func publishToClipboard(_ payload: ClipboardPayload) -> Bool {
    let item = NSPasteboardItem()
    item.setData(payload.sourceData, forType: payload.sourceType)
    if let pngData = payload.pngData {
      item.setData(pngData, forType: .png)
    }

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    return pasteboard.writeObjects([item])
  }

  private func isScreenCapture(path: String) -> Bool? {
    let attributeName = "com.apple.metadata:kMDItemIsScreenCapture"
    let attributeSize = path.withCString { pathPointer in
      attributeName.withCString { namePointer in
        getxattr(pathPointer, namePointer, nil, 0, 0, 0)
      }
    }
    if attributeSize > 0 {
      var data = Data(count: attributeSize)
      let bytesRead = data.withUnsafeMutableBytes { buffer in
        path.withCString { pathPointer in
          attributeName.withCString { namePointer in
            getxattr(pathPointer, namePointer, buffer.baseAddress, buffer.count, 0, 0)
          }
        }
      }
      if bytesRead == attributeSize,
        let value = try? PropertyListSerialization.propertyList(from: data, format: nil)
          as? NSNumber
      {
        return value.boolValue
      }
    }

    guard let metadata = MDItemCreate(kCFAllocatorDefault, path as CFString),
      let captureFlag = MDItemCopyAttribute(metadata, "kMDItemIsScreenCapture" as CFString)
        as? NSNumber
    else {
      return nil
    }
    return captureFlag.boolValue
  }

  private func hasCompleteFileTrailer(_ data: Data, fileExtension: String) -> Bool {
    switch fileExtension {
    case "png":
      let iend = Data([0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82])
      return data.count >= iend.count && data.suffix(iend.count).elementsEqual(iend)
    case "jpg", "jpeg":
      return data.count >= 2 && data.suffix(2).elementsEqual([0xff, 0xd9])
    default:
      return true
    }
  }
}
