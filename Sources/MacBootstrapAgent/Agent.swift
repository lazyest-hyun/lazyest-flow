import AppKit
import Carbon
import Foundation
import MacBootstrapCore

final class Agent: NSObject, NSApplicationDelegate {
  private enum MenuFeature {
    case appHotkeys
    case screenshotClipboard
    case keepAwake
    case dockPin
  }

  private let config: Config
  private let launchedAtLogin: Bool
  private let screenshotWatcher: ScreenshotWatcher
  private let keepAwakeController: KeepAwakeController
  private let mouseScrollController: MouseScrollController
  private let keyboardMappingController: KeyboardMappingController
  private let dockPinController: DockPinController
  private var inputDeviceObserver: NSObjectProtocol?
  private var dockStatusObserver: NSObjectProtocol?
  private var keepAwakeStatusObserver: NSObjectProtocol?
  private var entriesByID: [UInt32: HotkeyAction] = [:]
  private var hotKeyRefs: [EventHotKeyRef] = []
  private var registeredHotkeyIDs = Set<UInt32>()
  private var eventHandler: EventHandlerRef?
  private var statusItem: NSStatusItem?
  private var appHotkeysMenuItem: NSMenuItem?
  private var screenshotClipboardMenuItem: NSMenuItem?
  private var keepAwakeMenuItem: NSMenuItem?
  private var dockPinMenuItem: NSMenuItem?
  private var settingsWindowController: SettingsWindowController?

  init(config: Config, launchedAtLogin: Bool = false) {
    self.config = config
    self.launchedAtLogin = launchedAtLogin
    self.screenshotWatcher = ScreenshotWatcher(config: config)
    self.keepAwakeController = KeepAwakeController(config: config)
    self.mouseScrollController = MouseScrollController(config: config)
    self.keyboardMappingController = KeyboardMappingController.shared
    self.dockPinController = DockPinController(config: config)
    super.init()
    inputDeviceObserver = NotificationCenter.default.addObserver(
      forName: inputDeviceInventoryDidChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.keyboardMappingController.reapplySavedProfiles()
    }
    dockStatusObserver = NotificationCenter.default.addObserver(
      forName: dockPinStatusNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.updateMenuState()
    }
    keepAwakeStatusObserver = NotificationCenter.default.addObserver(
      forName: keepAwakeStatusNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.updateMenuState()
    }
  }

  func run() {
    LoginLaunchManager.shared.migrateLegacyRegistrationIfNeeded()
    NSApplication.shared.setActivationPolicy(.accessory)
    NSApplication.shared.delegate = self
    setupStatusItem()
    installEventHandler()
    reloadAll()
    NSApplication.shared.finishLaunching()
    NSApplication.shared.run()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    guard !launchedAtLogin, !wasLaunchedAsLoginItem else { return }
    DispatchQueue.main.async { [weak self] in
      self?.openSettings()
    }
  }

  private var wasLaunchedAsLoginItem: Bool {
    NSAppleEventManager.shared().currentAppleEvent?
      .paramDescriptor(forKeyword: AEKeyword(keyAELaunchedAsLogInItem)) != nil
  }

  func applicationDidBecomeActive(_ notification: Notification) {
    keepAwakeController.reload()
  }

  func applicationWillTerminate(_ notification: Notification) {
    keepAwakeController.shutdown(waitForHelper: true)
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    openSettings()
    return true
  }

  private func setupStatusItem() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    item.button?.image = agentMenuBarIcon()
    let menu = NSMenu()
    let settings = NSMenuItem(
      title: agentText("menu.settings"), action: #selector(openSettingsFromMenu), keyEquivalent: ","
    )
    let appHotkeys = NSMenuItem(
      title: agentText("menu.appHotkeys"), action: #selector(toggleAppHotkeysFromMenu),
      keyEquivalent: "")
    let screenshotClipboard = NSMenuItem(
      title: agentText("menu.screenshotClipboard"),
      action: #selector(toggleScreenshotClipboardFromMenu), keyEquivalent: "")
    let keepAwake = NSMenuItem(
      title: agentText("menu.keepAwake"), action: #selector(toggleKeepAwakeFromMenu),
      keyEquivalent: "")
    let dockPin = NSMenuItem(
      title: agentText("menu.dockPin"), action: #selector(toggleDockPinFromMenu),
      keyEquivalent: "")
    let reload = NSMenuItem(
      title: agentText("menu.reload"), action: #selector(reloadFromMenu), keyEquivalent: "r")
    let quit = NSMenuItem(
      title: agentText("menu.quit"), action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q")
    for item in [settings, appHotkeys, screenshotClipboard, keepAwake, dockPin, reload] {
      item.target = self
    }
    menu.addItem(settings)
    menu.addItem(NSMenuItem.separator())
    menu.addItem(appHotkeys)
    menu.addItem(screenshotClipboard)
    menu.addItem(keepAwake)
    menu.addItem(dockPin)
    menu.addItem(NSMenuItem.separator())
    menu.addItem(reload)
    menu.addItem(NSMenuItem.separator())
    menu.addItem(quit)
    item.menu = menu
    appHotkeysMenuItem = appHotkeys
    screenshotClipboardMenuItem = screenshotClipboard
    keepAwakeMenuItem = keepAwake
    dockPinMenuItem = dockPin
    statusItem = item
  }

  private func installEventHandler() {
    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    let callback: EventHandlerUPP = { _, eventRef, userData in
      var hotKeyID = EventHotKeyID()
      GetEventParameter(
        eventRef,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
      )
      guard let userData else { return noErr }
      let agent = Unmanaged<Agent>.fromOpaque(userData).takeUnretainedValue()
      agent.handle(id: hotKeyID.id)
      return noErr
    }

    InstallEventHandler(
      GetApplicationEventTarget(),
      callback,
      1,
      &eventType,
      Unmanaged.passUnretained(self).toOpaque(),
      &eventHandler
    )
  }

  @objc private func openSettingsFromMenu() {
    openSettings()
  }

  @objc private func reloadFromMenu() {
    reloadAll()
    settingsWindowController?.reloadPressed()
  }

  @objc private func toggleAppHotkeysFromMenu() {
    toggleMenuFeature(.appHotkeys)
  }

  @objc private func toggleScreenshotClipboardFromMenu() {
    toggleMenuFeature(.screenshotClipboard)
  }

  @objc private func toggleKeepAwakeFromMenu() {
    toggleMenuFeature(.keepAwake)
  }

  @objc private func toggleDockPinFromMenu() {
    toggleMenuFeature(.dockPin)
  }

  private func toggleMenuFeature(_ feature: MenuFeature) {
    do {
      config.reloadBootstrap()
      switch feature {
      case .appHotkeys:
        try config.setAppHotkeysEnabled(!config.appHotkeysEnabled)
      case .screenshotClipboard:
        try config.setScreenshotClipboardWatch(!config.screenshotClipboardWatch)
      case .keepAwake:
        let enabling = !config.keepAwakeEnabled
        try config.setKeepAwakeEnabled(enabling)
        reloadAll()
        if enabling {
          keepAwakeController.requestAuthorization()
        }
        settingsWindowController?.reloadPressed()
        return
      case .dockPin:
        try config.setDockPinEnabled(!config.dockPinEnabled)
      }
      reloadAll()
      settingsWindowController?.reloadPressed()
    } catch {
      NSLog("Failed to toggle menu feature: \(error)")
    }
  }

  private func openSettings() {
    if settingsWindowController == nil {
      let controller = SettingsWindowController(
        config: config,
        dockPinStatusProvider: { [weak self] in
          self?.dockPinController.status ?? .off
        },
        keepAwakeStatusProvider: { [weak self] in
          self?.keepAwakeController.status
            ?? .off(PowerSnapshot(onACPower: true, batteryPercent: nil, charging: false))
        }
      )
      controller.onSave = { [weak self] in self?.reloadAll() }
      controller.onKeepAwakeAuthorizationRequest = { [weak self] forceReinstall in
        self?.keepAwakeController.requestAuthorization(forceReinstall: forceReinstall)
      }
      controller.onShortcutCaptureStart = { [weak self] in self?.pauseHotkeysForCapture() }
      controller.onShortcutCaptureEnd = { [weak self] in self?.reloadHotkeys() }
      controller.onLanguageChange = { [weak self] in
        DispatchQueue.main.async {
          self?.rebuildLocalizedUI()
        }
      }
      controller.onClose = { [weak self, weak controller] in
        guard let self, self.settingsWindowController === controller else { return }
        self.settingsWindowController = nil
      }
      settingsWindowController = controller
    }
    settingsWindowController?.showWindow(nil)
    settingsWindowController?.window?.center()
    settingsWindowController?.window?.makeKeyAndOrderFront(nil)
    settingsWindowController?.window?.orderFrontRegardless()
    NSApplication.shared.activate(ignoringOtherApps: true)
  }

  private func rebuildLocalizedUI() {
    settingsWindowController?.close()
    settingsWindowController = nil
    if let statusItem {
      NSStatusBar.system.removeStatusItem(statusItem)
      self.statusItem = nil
    }
    setupStatusItem()
    updateMenuState()
    openSettings()
  }

  private func reloadAll() {
    reloadHotkeys()
    screenshotWatcher.reload()
    keepAwakeController.reload()
    mouseScrollController.reload()
    keyboardMappingController.reapplySavedProfiles()
    dockPinController.reload()
    updateMenuState()
  }

  private func updateMenuState() {
    appHotkeysMenuItem?.state = menuState(
      requested: config.appHotkeysEnabled,
      active: appHotkeysAreActive
    )
    screenshotClipboardMenuItem?.state = menuState(
      requested: config.screenshotClipboardWatch,
      active: screenshotWatcher.isActive
    )
    keepAwakeMenuItem?.state = menuState(
      requested: config.keepAwakeEnabled,
      active: keepAwakeController.isActive
    )
    dockPinMenuItem?.state = menuState(
      requested: config.dockPinEnabled,
      active: dockPinController.isActive
    )
  }

  private var appHotkeysAreActive: Bool {
    guard config.appHotkeysEnabled else { return false }
    let appBindingCount = ((try? config.loadBindings()) ?? []).filter {
      $0.isEnabled && parseShortcut($0.shortcut) != nil
    }.count
    let hideAllCount =
      ((try? config.loadHideAllBinding()).flatMap { binding in
        parseShortcut(binding.shortcut) != nil ? 1 : nil
      }) ?? 0
    let expectedCount = appBindingCount + hideAllCount
    return hotKeyRefs.count == expectedCount
  }

  private func menuState(requested: Bool, active: Bool) -> NSControl.StateValue {
    switch RuntimeFeatureStatePolicy.resolve(requested: requested, active: active) {
    case .off:
      return .off
    case .active:
      return .on
    case .unavailable:
      return .mixed
    }
  }

  private func reloadHotkeys() {
    unregisterHotkeys()
    guard config.appHotkeysEnabled else { return }

    do {
      for binding in try config.loadBindings() where binding.isEnabled {
        register(shortcutText: binding.shortcut, label: binding.label, action: .toggleApp(binding))
      }
      let hideAll = try config.loadHideAllBinding()
      if parseShortcut(hideAll.shortcut) != nil {
        register(
          shortcutText: hideAll.shortcut,
          label: agentText("apps.hideAll"),
          action: .hideRegisteredApps
        )
      }
    } catch {
      NSLog("Failed to load hotkey bindings: \(error)")
    }
  }

  private func pauseHotkeysForCapture() {
    unregisterHotkeys()
  }

  private func unregisterHotkeys() {
    for ref in hotKeyRefs {
      UnregisterEventHotKey(ref)
    }
    hotKeyRefs.removeAll()
    entriesByID.removeAll()
    registeredHotkeyIDs.removeAll()
  }

  private func register(shortcutText: String, label: String, action: HotkeyAction) {
    guard let shortcut = parseShortcut(shortcutText) else {
      NSLog("Skipping invalid shortcut: \(shortcutText)")
      return
    }
    let id = stableHotkeyID(for: shortcut)
    guard !registeredHotkeyIDs.contains(id) else {
      NSLog("Skipping duplicate app hotkey: \(shortcutText) for \(label)")
      return
    }
    var hotKeyRef: EventHotKeyRef?
    let hotKeyID = EventHotKeyID(signature: OSType(0x4D42_4148), id: id)
    let status = RegisterEventHotKey(
      shortcut.keyCode, shortcut.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    if status == noErr, let hotKeyRef {
      entriesByID[id] = action
      hotKeyRefs.append(hotKeyRef)
      registeredHotkeyIDs.insert(id)
    } else {
      NSLog("Failed to register \(shortcutText) for \(label): \(status)")
    }
  }

  private func handle(id: UInt32) {
    guard let action = entriesByID[id] else { return }
    switch action {
    case .toggleApp(let binding):
      toggleApp(bundleID: binding.bundleID)
    case .hideRegisteredApps:
      hideRegisteredApps()
    }
  }

  private func hideRegisteredApps() {
    guard let bindings = try? config.loadBindings() else { return }
    let bundleIDs = Set(bindings.filter(\.isEnabled).map(\.bundleID))
    for bundleID in bundleIDs {
      for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
      where appHasVisibleWindows(processIdentifier: app.processIdentifier) && !app.isHidden {
        app.hide()
      }
    }
  }

  private func toggleApp(bundleID: String) {
    let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    if let app = running.first {
      let hasVisibleWindows = appHasVisibleWindows(processIdentifier: app.processIdentifier)
      if hasVisibleWindows && (app.isActive || !app.isHidden) {
        app.hide()
      } else {
        reopenAndActivate(app: app, bundleID: bundleID)
      }
      return
    }

    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
      let configuration = NSWorkspace.OpenConfiguration()
      configuration.activates = true
      NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }
  }

  private func reopenAndActivate(app: NSRunningApplication, bundleID: String) {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
      app.unhide()
      app.activate(options: [.activateIgnoringOtherApps])
      return
    }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    NSWorkspace.shared.openApplication(at: url, configuration: configuration) { reopenedApp, _ in
      DispatchQueue.main.async {
        let target = reopenedApp ?? app
        target.unhide()
        target.activate(options: [.activateIgnoringOtherApps])
      }
    }
  }

}
