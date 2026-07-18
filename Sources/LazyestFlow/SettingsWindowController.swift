import AppKit
import ApplicationServices
import Foundation

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
  private let config: Config
  private let dockPinStatusProvider: () -> DockPinStatus
  private let keepAwakeStatusProvider: () -> KeepAwakeStatus
  private var rows: [BindingRow] = []
  private let bindingsStack = NSStackView()
  private let appsHintLabel = NSTextField(labelWithString: flowText("apps.hint"))
  private var screenshotDirectoryPath = ""
  private var shortcutCaptureMonitor: Any?
  private weak var activeShortcutField: ShortcutCaptureField?
  private var activeShortcutLabel = ""
  private weak var activeEditingRow: BindingRow?
  private var isEditingHideAll = false
  private var hideAllBinding = HideAllBinding(shortcut: "")
  private var shortcutCaptureCancel: (() -> Void)?
  private var removalSheet: FlowRemovalSheetController?
  private lazy var loginLaunchSwitch = settingSwitch(action: #selector(toggleLoginLaunch))
  private let loginLaunchStatusLabel = NSTextField(labelWithString: "")
  private lazy var generalPermissionButton = actionButton(
    title: flowText("general.permissionsOpen"), action: #selector(openAccessibilitySettings))
  private lazy var removeAgentButton: NSButton = {
    let button = actionButton(title: flowText("general.remove"), action: #selector(removeAgent))
    button.contentTintColor = .systemRed
    return button
  }()
  private lazy var appHotkeysSwitch = settingSwitch(action: #selector(toggleAppHotkeys))
  private let hideAllShortcutField = ShortcutCaptureField(string: "")
  private lazy var hideAllEditButton = actionButton(
    title: flowText("apps.hideAllSet"), action: #selector(editHideAllShortcut))
  private lazy var hideAllClearButton = iconButton(
    symbolName: "xmark", tooltip: flowText("apps.hideAllClear"),
    action: #selector(clearHideAllShortcut))
  private lazy var mouseScrollReverseSwitch = settingSwitch(
    action: #selector(toggleMouseScrollReverse))
  private lazy var mousePermissionButton = actionButton(
    title: flowText("dock.permission"), action: #selector(openAccessibilitySettings))
  private lazy var screenshotFolderButton = pathButton(action: #selector(openScreenshotDirectory))
  private lazy var screenshotWatchSwitch = settingSwitch(action: #selector(toggleScreenshotWatch))
  private lazy var keepAwakeSwitch = settingSwitch(action: #selector(toggleKeepAwake))
  private lazy var keepAwakeApprovalButton: NSButton = {
    let button = actionButton(
      title: flowText("keep.approve"), action: #selector(requestKeepAwakeAuthorization))
    button.widthAnchor.constraint(equalToConstant: 104).isActive = true
    return button
  }()
  private lazy var keepAwakePowerScopeControl: NSSegmentedControl = {
    let control = NSSegmentedControl(
      labels: [flowText("keep.powerOnly"), flowText("keep.includeBattery")],
      trackingMode: .selectOne,
      target: self,
      action: #selector(changeKeepAwakePowerScope)
    )
    control.segmentStyle = .rounded
    control.selectedSegment = 1
    control.widthAnchor.constraint(equalToConstant: 230).isActive = true
    return control
  }()
  private lazy var lockOnLidCloseSwitch = settingSwitch(action: #selector(toggleLockOnLidClose))
  private let keepAwakeStatusLabel = NSTextField(labelWithString: "")
  private lazy var dockPinSwitch = settingSwitch(action: #selector(toggleDockPin))
  private lazy var dockTimingSwitch = settingSwitch(action: #selector(toggleDockTiming))
  private lazy var dockPermissionButton = actionButton(
    title: flowText("dock.permission"), action: #selector(openAccessibilitySettings))
  private lazy var appAddButton = actionButton(
    title: flowText("apps.addRunning"), action: #selector(addRunningApp))
  private lazy var footerReloadButton = iconButton(
    symbolName: "arrow.clockwise", tooltip: flowText("footer.reload"),
    action: #selector(reloadPressed))
  private let languagePopup = NSPopUpButton()
  private let settingsTabs = NSTabView()
  private var tabButtons: [SettingsTabButton] = []
  private let dockDisplayPopup = NSPopUpButton()
  private let dockPinStatusLabel = NSTextField(labelWithString: "")
  private let dockTimingStatusLabel = NSTextField(labelWithString: "")
  private let mouseScrollStatusLabel = NSTextField(labelWithString: "")
  private let mouseDevicesStack = NSStackView()
  private let keyboardDevicesStack = NSStackView()
  private let statusLabel = NSTextField(labelWithString: "")
  private var observers: [NSObjectProtocol] = []
  var onSave: (() -> Void)?
  var onShortcutCaptureStart: (() -> Void)?
  var onShortcutCaptureEnd: (() -> Void)?
  var onLanguageChange: (() -> Void)?
  var onKeepAwakeAuthorizationRequest: ((Bool) -> Void)?
  var onClose: (() -> Void)?

  init(
    config: Config,
    dockPinStatusProvider: @escaping () -> DockPinStatus,
    keepAwakeStatusProvider: @escaping () -> KeepAwakeStatus
  ) {
    self.config = config
    self.dockPinStatusProvider = dockPinStatusProvider
    self.keepAwakeStatusProvider = keepAwakeStatusProvider
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 820, height: 540),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = flowText("title")
    window.isReleasedWhenClosed = false
    window.minSize = NSSize(width: 760, height: 500)
    super.init(window: window)
    window.delegate = self
    buildUI()
    observers = [
      NotificationCenter.default.addObserver(
        forName: dockPinStatusNotification, object: nil, queue: .main
      ) { [weak self] note in
        self?.refreshDockPinUI(status: note.object as? DockPinStatus)
      },
      NotificationCenter.default.addObserver(
        forName: mouseScrollStatusNotification, object: nil, queue: .main
      ) { [weak self] note in
        self?.refreshMouseScrollUI(status: note.object as? String)
      },
      NotificationCenter.default.addObserver(
        forName: keepAwakeStatusNotification, object: nil, queue: .main
      ) { [weak self] note in
        self?.refreshKeepAwakeUI(status: note.object as? KeepAwakeStatus)
      },
      NotificationCenter.default.addObserver(
        forName: inputDeviceInventoryDidChangeNotification, object: nil, queue: .main
      ) { [weak self] _ in
        self?.refreshMouseDevices()
        self?.refreshKeyboardDevices()
      },
      NotificationCenter.default.addObserver(
        forName: NSWindow.didResignKeyNotification, object: window, queue: .main
      ) { [weak self] _ in
        self?.stopShortcutCaptureMonitor(reloadHotkeys: true)
      },
    ]
    loadFromDisk()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  deinit {
    stopShortcutCaptureMonitor(reloadHotkeys: false)
    for observer in observers {
      NotificationCenter.default.removeObserver(observer)
    }
  }

  func windowWillClose(_ notification: Notification) {
    stopShortcutCaptureMonitor(reloadHotkeys: true)
    window?.delegate = nil
    window = nil
    onClose?()
  }

  private func buildUI() {
    guard let contentView = window?.contentView else { return }
    let root = NSStackView()
    root.orientation = .vertical
    root.alignment = .width
    root.spacing = 10
    root.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 12, right: 14)
    root.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(root)
    NSLayoutConstraint.activate([
      root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      root.topAnchor.constraint(equalTo: contentView.topAnchor),
      root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
    ])

    let tabBarRow = NSStackView()
    tabBarRow.orientation = .horizontal
    let tabBar = NSStackView()
    tabBar.orientation = .horizontal
    tabBar.distribution = .fillEqually
    tabBar.spacing = 4
    let tabDefinitions = [
      (flowText("tab.general"), "gearshape"),
      (flowText("tab.apps"), "keyboard"),
      (flowText("tab.inputDevices"), "computermouse"),
      (flowText("tab.screenshots"), "camera.viewfinder"),
      (flowText("tab.keepAwake"), "moon.zzz"),
      (flowText("tab.dockPin"), "dock.rectangle"),
    ]
    for (index, definition) in tabDefinitions.enumerated() {
      let button = SettingsTabButton(title: definition.0, symbolName: definition.1)
      button.target = self
      button.action = #selector(selectSettingsTab(_:))
      button.tag = index
      button.isSelectedTab = index == 0
      tabButtons.append(button)
      tabBar.addArrangedSubview(button)
    }
    tabBar.widthAnchor.constraint(equalToConstant: 700).isActive = true
    tabBarRow.addArrangedSubview(NSView())
    tabBarRow.addArrangedSubview(tabBar)
    tabBarRow.addArrangedSubview(NSView())
    root.addArrangedSubview(tabBarRow)

    settingsTabs.tabViewType = .noTabsNoBorder
    settingsTabs.frame = NSRect(x: 0, y: 0, width: 792, height: 400)
    settingsTabs.translatesAutoresizingMaskIntoConstraints = false
    settingsTabs.addTabViewItem(generalTab())
    settingsTabs.addTabViewItem(appBindingsTab())
    settingsTabs.addTabViewItem(inputDevicesTab())
    settingsTabs.addTabViewItem(screenshotsTab())
    settingsTabs.addTabViewItem(keepAwakeTab())
    settingsTabs.addTabViewItem(dockPinTab())
    root.addArrangedSubview(settingsTabs)
    settingsTabs.widthAnchor.constraint(equalTo: contentView.widthAnchor, constant: -28).isActive =
      true
    settingsTabs.heightAnchor.constraint(greaterThanOrEqualToConstant: 400).isActive = true

    let footer = NSStackView()
    footer.orientation = .horizontal
    footer.spacing = 8
    statusLabel.textColor = .secondaryLabelColor
    statusLabel.font = NSFont.systemFont(ofSize: 11)
    footer.addArrangedSubview(statusLabel)
    footer.addArrangedSubview(NSView())
    footer.addArrangedSubview(footerReloadButton)
    root.addArrangedSubview(footer)
  }

  private func configureLanguagePopup() {
    languagePopup.removeAllItems()
    let options: [(String, String)] = [
      (flowText("language.auto"), FlowLanguage.automatic.rawValue),
      (flowText("language.korean"), FlowLanguage.korean.rawValue),
      (flowText("language.english"), FlowLanguage.english.rawValue),
    ]
    for option in options {
      languagePopup.addItem(withTitle: option.0)
      languagePopup.lastItem?.representedObject = option.1
    }
    let savedCode = flowSavedLanguageCode()
    if let index = languagePopup.itemArray.firstIndex(where: {
      ($0.representedObject as? String) == savedCode
    }) {
      languagePopup.selectItem(at: index)
    } else {
      languagePopup.selectItem(at: 0)
    }
  }

  @objc private func changeLanguage() {
    guard let code = languagePopup.selectedItem?.representedObject as? String else { return }
    do {
      try saveFlowLanguageCode(code)
      onLanguageChange?()
    } catch {
      statusLabel.stringValue = "\(flowText("status.failed")): \(error.localizedDescription)"
    }
  }

  @objc private func selectSettingsTab(_ sender: SettingsTabButton) {
    for button in tabButtons {
      button.isSelectedTab = button === sender
    }
    settingsTabs.selectTabViewItem(at: sender.tag)
    if (settingsTabs.selectedTabViewItem?.identifier as? String) == "general" {
      refreshLoginLaunchUI()
    }
    if (settingsTabs.selectedTabViewItem?.identifier as? String) == "dock-anchor" {
      refreshDockPinUI(status: dockPinStatusProvider())
      refreshDockTimingUI()
    }
  }

  private func settingSwitch(action: Selector) -> NSSwitch {
    let toggle = NSSwitch(frame: .zero)
    toggle.target = self
    toggle.action = action
    toggle.setContentHuggingPriority(.required, for: .horizontal)
    return toggle
  }

  private func actionButton(title: String, action: Selector) -> NSButton {
    let button = NSButton(title: title, target: self, action: action)
    button.bezelStyle = .rounded
    button.controlSize = .regular
    button.heightAnchor.constraint(equalToConstant: 32).isActive = true
    return button
  }

  private func iconButton(symbolName: String, tooltip: String, action: Selector) -> NSButton {
    let button = NSButton(title: "", target: self, action: action)
    button.bezelStyle = .rounded
    button.controlSize = .regular
    button.toolTip = tooltip
    button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: tooltip)
    button.imagePosition = .imageOnly
    button.heightAnchor.constraint(equalToConstant: 32).isActive = true
    button.widthAnchor.constraint(equalToConstant: 40).isActive = true
    return button
  }

  private func pathButton(action: Selector) -> NSButton {
    let button = NSButton(title: "", target: self, action: action)
    button.isBordered = false
    button.alignment = .right
    button.contentTintColor = .linkColor
    button.font = NSFont.systemFont(ofSize: 12)
    button.lineBreakMode = .byTruncatingMiddle
    button.toolTip = flowText("screenshots.open")
    return button
  }

  private func pageHeader(title: String, detail: String) -> NSStackView {
    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 4
    let titleLabel = NSTextField(labelWithString: title)
    titleLabel.font = NSFont.systemFont(ofSize: 17, weight: .semibold)
    titleLabel.alignment = .left
    stack.addArrangedSubview(titleLabel)
    if !detail.isEmpty {
      let detailLabel = NSTextField(wrappingLabelWithString: detail)
      detailLabel.textColor = .secondaryLabelColor
      detailLabel.font = NSFont.systemFont(ofSize: 12)
      detailLabel.alignment = .left
      stack.addArrangedSubview(detailLabel)
    }
    return stack
  }

  private func settingRow(title: String, detail: String = "", control: NSView) -> NSStackView {
    let row = NSStackView()
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 12
    row.edgeInsets = NSEdgeInsets(top: 10, left: 2, bottom: 10, right: 2)

    let labels = NSStackView()
    labels.orientation = .vertical
    labels.alignment = .leading
    labels.spacing = 2
    let titleLabel = NSTextField(labelWithString: title)
    titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
    labels.addArrangedSubview(titleLabel)
    if !detail.isEmpty {
      let detailLabel = NSTextField(wrappingLabelWithString: detail)
      detailLabel.textColor = .secondaryLabelColor
      detailLabel.font = NSFont.systemFont(ofSize: 11)
      labels.addArrangedSubview(detailLabel)
    }
    labels.setContentHuggingPriority(.defaultLow, for: .horizontal)
    row.addArrangedSubview(labels)
    row.addArrangedSubview(NSView())
    control.setContentHuggingPriority(.required, for: .horizontal)
    row.addArrangedSubview(control)
    row.heightAnchor.constraint(greaterThanOrEqualToConstant: 58).isActive = true
    return row
  }

  private func compactSettingRow(title: String, control: NSView) -> NSStackView {
    let row = NSStackView()
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 10
    row.edgeInsets = NSEdgeInsets(top: 2, left: 2, bottom: 2, right: 2)
    let titleLabel = NSTextField(labelWithString: title)
    titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
    row.addArrangedSubview(titleLabel)
    row.addArrangedSubview(NSView())
    control.setContentHuggingPriority(.required, for: .horizontal)
    row.addArrangedSubview(control)
    return row
  }

  private func separator() -> NSBox {
    let box = NSBox()
    box.boxType = .separator
    return box
  }

  private func scrollableTabView(content: NSView) -> NSScrollView {
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 760, height: 400))
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.drawsBackground = false

    let documentView = FlippedDocumentView()
    documentView.translatesAutoresizingMaskIntoConstraints = false
    content.translatesAutoresizingMaskIntoConstraints = false
    documentView.addSubview(content)
    scrollView.documentView = documentView
    NSLayoutConstraint.activate([
      content.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
      content.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
      content.topAnchor.constraint(equalTo: documentView.topAnchor),
      content.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
      documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
    ])
    return scrollView
  }

  private func rowContainer(compact: Bool = false) -> NSStackView {
    let view = AdaptiveCardStackView()
    view.orientation = .horizontal
    view.spacing = 8
    let verticalInset: CGFloat = compact ? 5 : 7
    view.edgeInsets = NSEdgeInsets(top: verticalInset, left: 10, bottom: verticalInset, right: 10)
    return view
  }

  private func refreshMouseScrollUI(status override: String? = nil) {
    let enabled =
      mouseScrollReverseSwitch.state == .on || MouseDevicePreferences.shared.hasReversedOverride
    let status: String
    if !enabled {
      status = flowText("devices.mouse.status.off")
    } else if let override {
      status = override
    } else if !AXIsProcessTrusted() {
      status = flowText("devices.mouse.status.needsPermission")
    } else {
      status = flowText("devices.mouse.status.active")
    }
    mouseScrollStatusLabel.stringValue = status
    let isActive = status == flowText("devices.mouse.status.active")
    let isOff = status == flowText("devices.mouse.status.off")
    let tint: NSColor = isActive ? .systemGreen : (isOff ? .secondaryLabelColor : .systemOrange)
    mouseScrollStatusLabel.textColor = tint
    mouseScrollStatusLabel.layer?.backgroundColor =
      tint.withAlphaComponent(isOff ? 0.08 : 0.13).cgColor
    mousePermissionButton.isHidden = status != flowText("devices.mouse.status.needsPermission")
  }

  private func refreshMouseDevices() {
    for view in mouseDevicesStack.arrangedSubviews {
      mouseDevicesStack.removeArrangedSubview(view)
      view.removeFromSuperview()
    }
    let devices = InputDeviceInventory.shared.externalMice()
    if devices.isEmpty {
      let empty = NSTextField(wrappingLabelWithString: flowText("devices.mouse.identify"))
      empty.textColor = .secondaryLabelColor
      empty.font = NSFont.systemFont(ofSize: 11)
      empty.alignment = .left
      mouseDevicesStack.addArrangedSubview(empty)
      return
    }
    for device in devices {
      let row = MouseDeviceRowView(device: device)
      row.onResult = { [weak self] result in
        switch result {
        case .success:
          self?.statusLabel.stringValue = flowText("status.saved")
          self?.onSave?()
          self?.refreshMouseScrollUI()
        case .failure(let error):
          self?.statusLabel.stringValue =
            "\(flowText("status.failed")): \(error.localizedDescription)"
        }
      }
      mouseDevicesStack.addArrangedSubview(row)
      row.widthAnchor.constraint(equalTo: mouseDevicesStack.widthAnchor).isActive = true
    }
  }

  private func refreshKeyboardDevices() {
    for view in keyboardDevicesStack.arrangedSubviews {
      keyboardDevicesStack.removeArrangedSubview(view)
      view.removeFromSuperview()
    }
    let devices = InputDeviceInventory.shared.externalKeyboards()
    guard !devices.isEmpty else {
      let empty = NSTextField(wrappingLabelWithString: flowText("devices.keyboard.empty"))
      empty.textColor = .secondaryLabelColor
      empty.font = NSFont.systemFont(ofSize: 12)
      empty.alignment = .left
      keyboardDevicesStack.addArrangedSubview(empty)
      return
    }
    for device in devices {
      let row = KeyboardDeviceRowView(device: device)
      row.onResult = { [weak self] result in
        switch result {
        case .success:
          self?.statusLabel.stringValue = flowText("status.saved")
        case .failure(let error):
          self?.statusLabel.stringValue =
            "\(flowText("status.failed")): \(error.localizedDescription)"
        }
      }
      keyboardDevicesStack.addArrangedSubview(row)
      row.widthAnchor.constraint(equalTo: keyboardDevicesStack.widthAnchor).isActive = true
    }
  }

  private func updateDockPinControls(isEnabled: Bool, status: DockPinStatus) {
    dockPinSwitch.state = isEnabled ? .on : .off
    let warning = status == .needsPermission || status == .failed
    dockPermissionButton.isHidden = !isEnabled || !warning
    dockDisplayPopup.isEnabled = !isEnabled
  }

  private func refreshDockPinUI(status: DockPinStatus? = nil) {
    let enabled = dockPinSwitch.state == .on
    let resolvedStatus = dockPinResolvedStatus(
      isEnabled: enabled,
      runtimeStatus: status ?? dockPinStatusProvider()
    )
    dockPinStatusLabel.stringValue = resolvedStatus.localizedText
    let isActive = resolvedStatus == .active || resolvedStatus == .blocked
    let isOff = resolvedStatus == .off
    let tint: NSColor = isActive ? .systemGreen : (isOff ? .secondaryLabelColor : .systemOrange)
    dockPinStatusLabel.textColor = tint
    dockPinStatusLabel.layer?.backgroundColor =
      tint.withAlphaComponent(isOff ? 0.08 : 0.13).cgColor
    updateDockPinControls(isEnabled: enabled, status: resolvedStatus)
  }

  private func refreshDockTimingUI() {
    let mode = DockAutoHideTiming.currentMode()
    let statusKey: String
    let tint: NSColor
    switch mode {
    case .systemDefault:
      dockTimingSwitch.state = .off
      statusKey = "dock.timing.systemDefault"
      tint = .secondaryLabelColor
    case .fast:
      dockTimingSwitch.state = .on
      statusKey = "dock.timing.fast"
      tint = .systemGreen
    case .custom:
      dockTimingSwitch.state = .off
      statusKey = "dock.timing.custom"
      tint = .systemOrange
    }
    dockTimingStatusLabel.stringValue = flowText(statusKey)
    dockTimingStatusLabel.textColor = tint
    dockTimingStatusLabel.layer?.backgroundColor = tint.withAlphaComponent(0.1).cgColor
  }

  private func refreshKeepAwakeUI(status: KeepAwakeStatus? = nil) {
    let enabled = keepAwakeSwitch.state == .on
    keepAwakePowerScopeControl.isEnabled = enabled
    lockOnLidCloseSwitch.isEnabled = enabled

    let runtimeStatus = status ?? keepAwakeStatusProvider()
    let resolvedStatus: KeepAwakeStatus = enabled ? runtimeStatus : .off(runtimeStatus.power)
    if case .helperApprovalRequired = resolvedStatus {
      keepAwakeApprovalButton.isHidden = false
    } else if case .helperUnavailable = resolvedStatus {
      keepAwakeApprovalButton.isHidden = false
    } else {
      keepAwakeApprovalButton.isHidden = true
    }
    let powerText = keepAwakePowerText(resolvedStatus.power)
    let statusText: String
    let tint: NSColor
    switch resolvedStatus {
    case .off:
      statusText = flowText("keep.status.off")
      tint = .secondaryLabelColor
    case .activating:
      statusText = flowText("keep.status.activating")
      tint = .systemOrange
    case .active:
      statusText = flowText("keep.status.active")
      tint = .systemGreen
    case .waitingForPower:
      statusText = flowText("keep.status.waitingPower")
      tint = .systemOrange
    case .lowBattery:
      statusText = flowText("keep.status.lowBattery")
      tint = .systemOrange
    case .thermalSafety:
      statusText = flowText("keep.status.thermal")
      tint = .systemOrange
    case .helperApprovalRequired:
      statusText = flowText("keep.status.helperApproval")
      tint = .systemOrange
    case .helperUnavailable:
      statusText = flowText("keep.status.helperUnavailable")
      tint = .systemOrange
    }
    keepAwakeStatusLabel.stringValue = "\(statusText) · \(powerText)"
    keepAwakeStatusLabel.textColor = tint
    keepAwakeStatusLabel.toolTip = keepAwakeStatusLabel.stringValue
  }

  private func keepAwakePowerText(_ power: PowerSnapshot) -> String {
    if power.onACPower {
      return flowText("keep.power.ac")
    }
    if let percent = power.batteryPercent {
      return String(format: flowText("keep.power.batteryPercent"), percent)
    }
    return flowText("keep.power.battery")
  }

  private func dockPinResolvedStatus(
    isEnabled: Bool,
    runtimeStatus: DockPinStatus
  ) -> DockPinStatus {
    guard isEnabled else {
      return .off
    }
    guard AXIsProcessTrusted() else {
      return .needsPermission
    }
    if runtimeStatus == .relocating {
      return .relocating
    }
    guard let targetID = config.dockPinDisplayID,
      let currentID = currentDockDisplayIDFromWindowServer()
    else {
      return runtimeStatus == .failed ? .failed : .moveFailed
    }
    guard currentID == targetID else {
      return .moveFailed
    }
    switch runtimeStatus {
    case .active, .moveFailed:
      return .active
    case .blocked:
      return .blocked
    case .relocating:
      return .relocating
    case .needsPermission:
      return .needsPermission
    case .failed, .off:
      return .failed
    }
  }

  private func appBindingsTab() -> NSTabViewItem {
    let item = NSTabViewItem(identifier: "apps")
    item.label = flowText("tab.apps")
    let root = NSStackView()
    root.frame = NSRect(x: 0, y: 0, width: 760, height: 400)
    root.orientation = .vertical
    root.alignment = .width
    root.spacing = 8
    root.edgeInsets = NSEdgeInsets(top: 14, left: 18, bottom: 12, right: 18)

    let header = NSStackView()
    header.orientation = .horizontal
    header.alignment = .centerY
    header.spacing = 8
    appsHintLabel.textColor = .secondaryLabelColor
    appsHintLabel.font = NSFont.systemFont(ofSize: 12)
    let heading = NSStackView()
    heading.orientation = .vertical
    heading.alignment = .leading
    heading.spacing = 4
    let headingTitle = NSTextField(labelWithString: flowText("tab.apps"))
    headingTitle.font = NSFont.systemFont(ofSize: 17, weight: .semibold)
    heading.addArrangedSubview(headingTitle)
    heading.addArrangedSubview(appsHintLabel)
    header.addArrangedSubview(heading)
    header.addArrangedSubview(NSView())
    appAddButton.image = NSImage(
      systemSymbolName: "plus", accessibilityDescription: flowText("apps.addRunning"))
    appAddButton.imagePosition = .imageLeading
    header.addArrangedSubview(appAddButton)
    root.addArrangedSubview(header)
    header.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
    root.addArrangedSubview(separator())
    root.addArrangedSubview(
      compactSettingRow(title: flowText("apps.enabled"), control: appHotkeyControls()))
    let listSeparator = separator()
    root.addArrangedSubview(listSeparator)

    bindingsStack.orientation = .vertical
    bindingsStack.alignment = .width
    bindingsStack.spacing = 6
    let scrollView = NSScrollView()
    scrollView.hasVerticalScroller = true
    scrollView.drawsBackground = false
    let documentView = FlippedDocumentView()
    documentView.translatesAutoresizingMaskIntoConstraints = false
    bindingsStack.translatesAutoresizingMaskIntoConstraints = false
    documentView.addSubview(bindingsStack)
    NSLayoutConstraint.activate([
      bindingsStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
      bindingsStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
      bindingsStack.topAnchor.constraint(equalTo: documentView.topAnchor),
      bindingsStack.bottomAnchor.constraint(lessThanOrEqualTo: documentView.bottomAnchor),
      bindingsStack.widthAnchor.constraint(equalTo: documentView.widthAnchor),
    ])
    scrollView.documentView = documentView
    NSLayoutConstraint.activate([
      documentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
      documentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
      documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
    ])
    let scrollContainer = NSView()
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollContainer.addSubview(scrollView)
    root.addArrangedSubview(scrollContainer)
    NSLayoutConstraint.activate([
      listSeparator.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
      listSeparator.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
      scrollContainer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
      scrollContainer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
      scrollView.leadingAnchor.constraint(equalTo: scrollContainer.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: scrollContainer.trailingAnchor),
      scrollView.topAnchor.constraint(equalTo: scrollContainer.topAnchor),
      scrollView.bottomAnchor.constraint(equalTo: scrollContainer.bottomAnchor),
    ])
    item.view = root
    return item
  }

  private func appHotkeyControls() -> NSStackView {
    let hideAllLabel = NSTextField(labelWithString: flowText("apps.hideAll"))
    hideAllLabel.font = NSFont.systemFont(ofSize: 12)
    hideAllLabel.textColor = .secondaryLabelColor
    hideAllLabel.toolTip = flowText("apps.hideAllDetail")
    hideAllShortcutField.widthAnchor.constraint(equalToConstant: 110).isActive = true
    hideAllShortcutField.alignment = .center
    hideAllShortcutField.placeholderString = flowText("apps.editShortcutHint")
    hideAllEditButton.widthAnchor.constraint(equalToConstant: 72).isActive = true
    hideAllClearButton.widthAnchor.constraint(equalToConstant: 40).isActive = true
    let switchSlot = NSView()
    switchSlot.widthAnchor.constraint(equalToConstant: 48).isActive = true
    switchSlot.heightAnchor.constraint(equalToConstant: 32).isActive = true
    switchSlot.addSubview(appHotkeysSwitch)
    appHotkeysSwitch.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      appHotkeysSwitch.centerXAnchor.constraint(equalTo: switchSlot.centerXAnchor),
      appHotkeysSwitch.centerYAnchor.constraint(equalTo: switchSlot.centerYAnchor),
    ])
    let controls = NSStackView(views: [
      hideAllLabel, hideAllShortcutField, hideAllEditButton, hideAllClearButton, switchSlot,
    ])
    controls.orientation = .horizontal
    controls.alignment = .centerY
    controls.spacing = 8
    configureHideAllControls()
    return controls
  }

  private func generalTab() -> NSTabViewItem {
    let item = NSTabViewItem(identifier: "general")
    item.label = flowText("tab.general")
    let root = NSStackView()
    root.orientation = .vertical
    root.alignment = .width
    root.spacing = 14
    root.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)

    let header = pageHeader(
      title: flowText("general.title"), detail: flowText("general.detail"))
    root.addArrangedSubview(header)
    header.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
    root.addArrangedSubview(separator())

    loginLaunchStatusLabel.alignment = .center
    loginLaunchStatusLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
    loginLaunchStatusLabel.wantsLayer = true
    loginLaunchStatusLabel.layer?.cornerRadius = 7
    loginLaunchStatusLabel.layer?.masksToBounds = true
    loginLaunchStatusLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 64).isActive = true
    let controls = NSStackView()
    controls.orientation = .horizontal
    controls.alignment = .centerY
    controls.spacing = 8
    controls.addArrangedSubview(loginLaunchStatusLabel)
    controls.addArrangedSubview(loginLaunchSwitch)
    root.addArrangedSubview(
      settingRow(
        title: flowText("general.loginLaunch"),
        detail: flowText("general.loginLaunchDetail"),
        control: controls
      ))
    root.addArrangedSubview(separator())
    root.addArrangedSubview(
      settingRow(
        title: flowText("general.permissions"),
        detail: flowText("general.permissionsDetail"),
        control: generalPermissionButton
      ))
    root.addArrangedSubview(separator())
    configureLanguagePopup()
    languagePopup.target = self
    languagePopup.action = #selector(changeLanguage)
    languagePopup.widthAnchor.constraint(equalToConstant: 118).isActive = true
    root.addArrangedSubview(
      settingRow(title: flowText("language.label"), control: languagePopup))
    root.addArrangedSubview(separator())
    root.addArrangedSubview(
      settingRow(
        title: flowText("general.remove"), detail: flowText("general.removeDetail"),
        control: removeAgentButton
      ))
    root.addArrangedSubview(NSView())
    item.view = root
    return item
  }

  private func keepAwakeTab() -> NSTabViewItem {
    let item = NSTabViewItem(identifier: "keep-awake")
    item.label = flowText("tab.keepAwake")
    let root = NSStackView()
    root.orientation = .vertical
    root.alignment = .width
    root.spacing = 14
    root.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)

    let header = pageHeader(title: flowText("keep.title"), detail: flowText("keep.detail"))
    root.addArrangedSubview(header)
    header.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
    root.addArrangedSubview(separator())
    let approvalSlot = NSView()
    approvalSlot.widthAnchor.constraint(equalToConstant: 104).isActive = true
    approvalSlot.heightAnchor.constraint(equalToConstant: 32).isActive = true
    keepAwakeApprovalButton.translatesAutoresizingMaskIntoConstraints = false
    approvalSlot.addSubview(keepAwakeApprovalButton)
    NSLayoutConstraint.activate([
      keepAwakeApprovalButton.leadingAnchor.constraint(equalTo: approvalSlot.leadingAnchor),
      keepAwakeApprovalButton.trailingAnchor.constraint(equalTo: approvalSlot.trailingAnchor),
      keepAwakeApprovalButton.centerYAnchor.constraint(equalTo: approvalSlot.centerYAnchor),
    ])
    let masterControls = NSStackView()
    masterControls.orientation = .horizontal
    masterControls.alignment = .centerY
    masterControls.spacing = 8
    masterControls.addArrangedSubview(approvalSlot)
    masterControls.addArrangedSubview(keepAwakeSwitch)
    root.addArrangedSubview(
      settingRow(title: flowText("keep.prevent"), control: masterControls))
    root.addArrangedSubview(separator())
    root.addArrangedSubview(
      settingRow(
        title: flowText("keep.powerScope"),
        detail: flowText("keep.powerScopeDetail"),
        control: keepAwakePowerScopeControl
      ))
    root.addArrangedSubview(separator())
    root.addArrangedSubview(
      settingRow(
        title: flowText("keep.lockOnLid"),
        detail: flowText("keep.lockOnLidDetail"),
        control: lockOnLidCloseSwitch
      ))
    root.addArrangedSubview(separator())
    keepAwakeStatusLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
    keepAwakeStatusLabel.lineBreakMode = .byTruncatingTail
    keepAwakeStatusLabel.heightAnchor.constraint(equalToConstant: 22).isActive = true
    root.addArrangedSubview(keepAwakeStatusLabel)
    root.addArrangedSubview(NSView())
    item.view = root
    return item
  }

  private func dockPinTab() -> NSTabViewItem {
    let item = NSTabViewItem(identifier: "dock-anchor")
    item.label = flowText("tab.dockPin")
    let root = NSStackView()
    root.orientation = .vertical
    root.alignment = .width
    root.spacing = 14
    root.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)

    let header = pageHeader(title: flowText("dock.title"), detail: flowText("dock.detail"))
    root.addArrangedSubview(header)
    header.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
    root.addArrangedSubview(separator())

    dockPinStatusLabel.alignment = .center
    dockPinStatusLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
    dockPinStatusLabel.wantsLayer = true
    dockPinStatusLabel.layer?.cornerRadius = 7
    dockPinStatusLabel.layer?.masksToBounds = true
    dockPinStatusLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 76).isActive = true
    let anchorControls = NSStackView()
    anchorControls.orientation = .horizontal
    anchorControls.spacing = 8
    anchorControls.addArrangedSubview(dockPinStatusLabel)
    anchorControls.addArrangedSubview(dockPermissionButton)
    anchorControls.addArrangedSubview(dockPinSwitch)
    root.addArrangedSubview(settingRow(title: flowText("dock.checkbox"), control: anchorControls))
    root.addArrangedSubview(separator())

    dockDisplayPopup.target = self
    dockDisplayPopup.action = #selector(saveRuntimeSettings)
    dockDisplayPopup.widthAnchor.constraint(equalToConstant: 440).isActive = true
    root.addArrangedSubview(settingRow(title: flowText("dock.display"), control: dockDisplayPopup))
    root.addArrangedSubview(separator())

    dockTimingStatusLabel.alignment = .center
    dockTimingStatusLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
    dockTimingStatusLabel.wantsLayer = true
    dockTimingStatusLabel.layer?.cornerRadius = 7
    dockTimingStatusLabel.layer?.masksToBounds = true
    dockTimingStatusLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 90).isActive = true
    let timingControls = NSStackView()
    timingControls.orientation = .horizontal
    timingControls.spacing = 8
    timingControls.addArrangedSubview(dockTimingStatusLabel)
    timingControls.addArrangedSubview(dockTimingSwitch)
    root.addArrangedSubview(
      settingRow(
        title: flowText("dock.timing"), detail: flowText("dock.timingDetail"),
        control: timingControls))
    root.addArrangedSubview(NSView())
    item.view = root
    return item
  }

  private func inputDevicesTab() -> NSTabViewItem {
    let item = NSTabViewItem(identifier: "input-devices")
    item.label = flowText("tab.inputDevices")
    let root = NSStackView()
    root.orientation = .vertical
    root.alignment = .width
    root.spacing = 14
    root.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)

    let header = pageHeader(title: flowText("devices.title"), detail: flowText("devices.detail"))
    root.addArrangedSubview(header)
    header.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
    root.addArrangedSubview(separator())

    let mouseHeading = pageHeader(title: flowText("devices.mouse.title"), detail: "")
    if let titleLabel = mouseHeading.arrangedSubviews.first as? NSTextField {
      titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
    }
    root.addArrangedSubview(mouseHeading)
    mouseHeading.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

    mouseScrollStatusLabel.alignment = .center
    mouseScrollStatusLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
    mouseScrollStatusLabel.wantsLayer = true
    mouseScrollStatusLabel.layer?.cornerRadius = 7
    mouseScrollStatusLabel.layer?.masksToBounds = true
    mouseScrollStatusLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 76).isActive = true
    let mouseControls = NSStackView()
    mouseControls.orientation = .horizontal
    mouseControls.alignment = .centerY
    mouseControls.spacing = 8
    mouseControls.addArrangedSubview(mouseScrollStatusLabel)
    mouseControls.addArrangedSubview(mousePermissionButton)
    mouseControls.addArrangedSubview(mouseScrollReverseSwitch)
    root.addArrangedSubview(
      settingRow(
        title: flowText("devices.mouse.reverse"),
        detail: flowText("devices.mouse.reverseDetail"),
        control: mouseControls
      ))
    mouseDevicesStack.orientation = .vertical
    mouseDevicesStack.alignment = .width
    mouseDevicesStack.spacing = 8
    root.addArrangedSubview(mouseDevicesStack)

    root.addArrangedSubview(separator())

    let keyboardHeading = pageHeader(
      title: flowText("devices.keyboard.title"), detail: flowText("devices.keyboard.detail"))
    if let titleLabel = keyboardHeading.arrangedSubviews.first as? NSTextField {
      titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
      titleLabel.alignment = .left
    }
    root.addArrangedSubview(keyboardHeading)
    keyboardHeading.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
    keyboardDevicesStack.orientation = .vertical
    keyboardDevicesStack.alignment = .width
    keyboardDevicesStack.spacing = 8
    root.addArrangedSubview(keyboardDevicesStack)

    root.addArrangedSubview(NSView())

    item.view = scrollableTabView(content: root)
    return item
  }

  private func screenshotsTab() -> NSTabViewItem {
    let item = NSTabViewItem(identifier: "screenshots")
    item.label = flowText("tab.screenshots")
    let root = NSStackView()
    root.orientation = .vertical
    root.alignment = .width
    root.spacing = 14
    root.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)

    let header = pageHeader(
      title: flowText("screenshots.title"), detail: flowText("screenshots.detail"))
    root.addArrangedSubview(header)
    header.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
    root.addArrangedSubview(separator())

    let pathControls = NSStackView()
    pathControls.orientation = .horizontal
    pathControls.spacing = 8
    screenshotFolderButton.widthAnchor.constraint(equalToConstant: 390).isActive = true
    pathControls.addArrangedSubview(screenshotFolderButton)
    pathControls.addArrangedSubview(
      actionButton(
        title: flowText("screenshots.choose"), action: #selector(chooseScreenshotDirectory)))
    root.addArrangedSubview(
      settingRow(title: flowText("screenshots.folder"), control: pathControls))
    root.addArrangedSubview(separator())
    root.addArrangedSubview(
      settingRow(
        title: flowText("screenshots.copy"),
        detail: flowText("screenshots.copyDetail"),
        control: screenshotWatchSwitch
      ))
    root.addArrangedSubview(NSView())
    item.view = root
    return item
  }

  private func loadFromDisk() {
    config.reloadBootstrap()
    refreshLoginLaunchUI()
    screenshotDirectoryPath = config.screenshotDir
    updateScreenshotFolderButton()
    appHotkeysSwitch.state = config.appHotkeysEnabled ? .on : .off
    mouseScrollReverseSwitch.state = config.mouseScrollReverseEnabled ? .on : .off
    screenshotWatchSwitch.state = config.screenshotClipboardWatch ? .on : .off
    keepAwakeSwitch.state = config.keepAwakeEnabled ? .on : .off
    keepAwakePowerScopeControl.selectedSegment = config.keepAwakeOnBattery ? 1 : 0
    lockOnLidCloseSwitch.state = config.lockOnLidClose ? .on : .off
    dockPinSwitch.state = config.dockPinEnabled ? .on : .off
    populateDockDisplayPopup(selectedID: config.dockPinDisplayID)
    refreshMouseScrollUI()
    refreshMouseDevices()
    refreshKeyboardDevices()
    refreshDockPinUI()
    refreshDockTimingUI()
    refreshKeepAwakeUI()
    clearRows()
    let bindings = (try? config.loadBindings()) ?? []
    hideAllBinding =
      (try? config.loadHideAllBinding()) ?? HideAllBinding(shortcut: "")
    for binding in bindings {
      appendRow(binding)
    }
    configureHideAllControls()
    setAppShortcutEditingMode(activeRow: nil)
    updateAppHotkeyControls()
    updateAppsHint(count: bindings.count)
    statusLabel.stringValue = ""
  }

  private func clearRows() {
    rows.removeAll()
    for view in bindingsStack.arrangedSubviews {
      bindingsStack.removeArrangedSubview(view)
      view.removeFromSuperview()
    }
  }

  private func appendRow(_ binding: AppBinding) {
    let row = BindingRow(binding: binding)

    let view = rowContainer(compact: true)
    view.alignment = .centerY
    view.distribution = .fill
    view.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
    row.iconView.widthAnchor.constraint(equalToConstant: 30).isActive = true
    row.iconView.heightAnchor.constraint(equalToConstant: 30).isActive = true

    let identity = NSStackView()
    identity.orientation = .vertical
    identity.alignment = .leading
    identity.spacing = 2
    identity.addArrangedSubview(row.label)
    identity.addArrangedSubview(row.bundleID)
    identity.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
    identity.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    let appInfo = NSStackView()
    appInfo.orientation = .horizontal
    appInfo.alignment = .centerY
    appInfo.spacing = 9
    appInfo.addArrangedSubview(row.iconView)
    appInfo.addArrangedSubview(identity)
    appInfo.setContentHuggingPriority(.defaultLow, for: .horizontal)
    appInfo.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    row.shortcutField.widthAnchor.constraint(equalToConstant: 110).isActive = true
    row.shortcutField.alignment = .center
    row.shortcutField.placeholderString = flowText("apps.editShortcutHint")
    row.shortcutField.lineBreakMode = .byTruncatingMiddle
    row.enabledSwitch.target = self
    row.enabledSwitch.action = #selector(toggleRowEnabled(_:))
    row.enabledSwitch.setContentHuggingPriority(.required, for: .horizontal)
    row.editButton.target = self
    row.editButton.action = #selector(editRow(_:))
    row.editButton.bezelStyle = .rounded
    row.editButton.controlSize = .regular
    row.editButton.heightAnchor.constraint(equalToConstant: 32).isActive = true
    row.editButton.widthAnchor.constraint(equalToConstant: 72).isActive = true
    row.removeButton.target = self
    row.removeButton.action = #selector(removeRow(_:))
    row.removeButton.bezelStyle = .rounded
    row.removeButton.controlSize = .regular
    row.removeButton.toolTip = flowText("apps.remove")
    row.removeButton.image = NSImage(
      systemSymbolName: "trash", accessibilityDescription: flowText("apps.remove"))
    row.removeButton.imagePosition = .imageOnly
    row.removeButton.contentTintColor = .systemRed
    row.removeButton.heightAnchor.constraint(equalToConstant: 32).isActive = true
    row.removeButton.widthAnchor.constraint(equalToConstant: 84).isActive = true

    let switchSlot = NSView()
    switchSlot.widthAnchor.constraint(equalToConstant: 48).isActive = true
    switchSlot.heightAnchor.constraint(equalToConstant: 32).isActive = true
    switchSlot.addSubview(row.enabledSwitch)
    row.enabledSwitch.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      row.enabledSwitch.centerXAnchor.constraint(equalTo: switchSlot.centerXAnchor),
      row.enabledSwitch.centerYAnchor.constraint(equalTo: switchSlot.centerYAnchor),
    ])

    let trailingControls = NSStackView()
    trailingControls.orientation = .horizontal
    trailingControls.alignment = .centerY
    trailingControls.spacing = 8
    trailingControls.setContentHuggingPriority(.required, for: .horizontal)
    trailingControls.setContentCompressionResistancePriority(.required, for: .horizontal)
    for control in [row.shortcutField, row.editButton, row.removeButton, switchSlot] as [NSView] {
      trailingControls.addArrangedSubview(control)
    }
    trailingControls.widthAnchor.constraint(equalToConstant: 338).isActive = true

    let flexibleSpace = NSView()
    flexibleSpace.setContentHuggingPriority(.defaultLow, for: .horizontal)
    flexibleSpace.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    view.addArrangedSubview(appInfo)
    view.addArrangedSubview(flexibleSpace)
    view.addArrangedSubview(trailingControls)
    rows.append(row)
    bindingsStack.addArrangedSubview(view)
    view.widthAnchor.constraint(equalTo: bindingsStack.widthAnchor).isActive = true
    row.enabledSwitch.isEnabled = appHotkeysSwitch.state == .on && activeEditingRow == nil
    updateAppsHint(count: rows.count)
  }

  @objc private func addRunningApp() {
    let apps = visibleRunningApplications()
    let alert = NSAlert()
    alert.messageText = flowText("apps.addRunning")
    alert.informativeText =
      flowLanguage() == .korean
      ? "현재 화면에 창이 보이는 앱만 표시합니다. 앱을 선택한 뒤 단축키를 지정합니다."
      : "Only apps with visible windows are listed. Choose an app, then set its shortcut."
    let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 420, height: 28))
    for app in apps {
      let title = "\(app.localizedName ?? "Unknown") — \(app.bundleIdentifier ?? "")"
      popup.addItem(withTitle: title)
    }
    alert.accessoryView = popup
    alert.addButton(withTitle: flowText("apps.add"))
    alert.addButton(withTitle: flowText("apps.cancel"))
    guard alert.runModal() == .alertFirstButtonReturn,
      popup.indexOfSelectedItem >= 0,
      apps.indices.contains(popup.indexOfSelectedItem)
    else { return }
    let app = apps[popup.indexOfSelectedItem]
    appendRow(
      AppBinding(
        shortcut: "", bundleID: app.bundleIdentifier ?? "", label: app.localizedName ?? "App",
        isEnabled: true))
    if let row = rows.last, let rowView = bindingsStack.arrangedSubviews.last {
      row.setEditing(true)
      beginShortcutCapture(for: row.shortcutField, label: row.binding.label)
      window?.makeFirstResponder(row.shortcutField)
      rowView.needsDisplay = true
    }
  }

  private func visibleRunningApplications() -> [NSRunningApplication] {
    let visiblePIDs = visibleWindowProcessIDs()
    var seen = Set<String>()
    return NSWorkspace.shared.runningApplications
      .filter { app in
        guard let bundleID = app.bundleIdentifier, !bundleID.isEmpty else { return false }
        guard bundleID != Bundle.main.bundleIdentifier else { return false }
        guard app.activationPolicy == .regular else { return false }
        guard visiblePIDs.contains(app.processIdentifier) else { return false }
        if seen.contains(bundleID) { return false }
        seen.insert(bundleID)
        return true
      }
      .sorted {
        let left =
          ($0.localizedName?.isEmpty == false ? $0.localizedName! : $0.bundleIdentifier ?? "")
        let right =
          ($1.localizedName?.isEmpty == false ? $1.localizedName! : $1.bundleIdentifier ?? "")
        return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
      }
  }

  private func visibleWindowProcessIDs() -> Set<pid_t> {
    let windows =
      CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
      as? [[String: Any]] ?? []
    var pids = Set<pid_t>()
    for window in windows {
      guard (window[kCGWindowLayer as String] as? Int) == 0 else { continue }
      let rawPID = window[kCGWindowOwnerPID as String]
      let pid: pid_t
      if let value = rawPID as? pid_t {
        pid = value
      } else if let value = rawPID as? NSNumber {
        pid = value.int32Value
      } else {
        continue
      }
      guard let bounds = window[kCGWindowBounds as String] as? [String: Any],
        let width = bounds["Width"] as? CGFloat,
        let height = bounds["Height"] as? CGFloat,
        width > 0, height > 0
      else { continue }
      pids.insert(pid)
    }
    return pids
  }

  private func editBinding(_ initial: AppBinding) -> AppBinding? {
    let nameField = NSTextField(string: initial.label)
    let bundleField = NSTextField(string: initial.bundleID)
    let shortcutField = ShortcutCaptureField(string: initial.shortcut)
    shortcutField.placeholderString = flowText("apps.editShortcutHint")

    let grid = NSGridView(views: [
      [NSTextField(labelWithString: flowText("apps.editName")), nameField],
      [NSTextField(labelWithString: flowText("apps.editBundle")), bundleField],
      [NSTextField(labelWithString: flowText("apps.editShortcut")), shortcutField],
    ])
    grid.column(at: 0).xPlacement = .trailing
    grid.column(at: 1).width = 360
    grid.rowSpacing = 8
    grid.columnSpacing = 10

    let alert = NSAlert()
    alert.messageText = flowText("apps.editTitle")
    alert.accessoryView = grid
    alert.addButton(withTitle: flowText("apps.add"))
    alert.addButton(withTitle: flowText("apps.cancel"))
    onShortcutCaptureStart?()
    let result = alert.runModal()
    onShortcutCaptureEnd?()
    guard result == .alertFirstButtonReturn else { return nil }

    let label = nameField.stringValue.trimmingCharacters(in: .whitespaces)
    let bundleID = bundleField.stringValue.trimmingCharacters(in: .whitespaces)
    let shortcut = shortcutField.stringValue.trimmingCharacters(in: .whitespaces)
    guard !label.isEmpty, !bundleID.isEmpty, !shortcut.isEmpty else { return nil }
    return AppBinding(
      shortcut: shortcut, bundleID: bundleID, label: label, isEnabled: initial.isEnabled)
  }

  private func populateDockDisplayPopup(selectedID: UInt32?) {
    dockDisplayPopup.removeAllItems()
    let screens = sortedScreens()
    for (index, screen) in screens.enumerated() {
      let id = displayID(for: screen)
      let frame = screen.frame
      let title =
        "\(screen.localizedName) · Display \(index + 1) · \(Int(frame.width))x\(Int(frame.height)) · ID \(id)"
      dockDisplayPopup.addItem(withTitle: title)
      dockDisplayPopup.lastItem?.representedObject = id
    }
    let targetID = selectedID ?? currentDisplayID()
    if let index = dockDisplayPopup.itemArray.firstIndex(where: {
      ($0.representedObject as? UInt32) == targetID
    }) {
      dockDisplayPopup.selectItem(at: index)
    } else if dockDisplayPopup.numberOfItems > 0 {
      dockDisplayPopup.selectItem(at: 0)
    }
  }

  private func selectedDockDisplayID() -> UInt32? {
    dockDisplayPopup.selectedItem?.representedObject as? UInt32
  }

  @objc private func removeRow(_ sender: NSButton) {
    if let activeEditingRow, activeEditingRow.removeButton === sender {
      activeEditingRow.cancelEditing()
      endShortcutCapture()
      setAppShortcutEditingMode(activeRow: nil)
      updateAppsHint(count: rows.count)
      statusLabel.stringValue = ""
      return
    }
    guard let index = rows.firstIndex(where: { $0.removeButton === sender }),
      rows.indices.contains(index),
      bindingsStack.arrangedSubviews.indices.contains(index)
    else { return }
    let rowView = bindingsStack.arrangedSubviews[index]
    if rows[index].isEditing {
      endShortcutCapture()
    }
    rows.remove(at: index)
    bindingsStack.removeArrangedSubview(rowView)
    rowView.removeFromSuperview()
    updateAppsHint(count: rows.count)
    savePressed()
  }

  @objc private func toggleRowEnabled(_ sender: NSSwitch) {
    guard let row = rows.first(where: { $0.enabledSwitch === sender }) else { return }
    row.binding.isEnabled = sender.state == .on
    row.refreshEnabledAppearance()
    savePressed()
  }

  @objc private func editRow(_ sender: NSButton) {
    guard let index = rows.firstIndex(where: { $0.editButton === sender }),
      rows.indices.contains(index)
    else { return }
    let row = rows[index]
    if row.isEditing {
      let shortcut = row.shortcutField.lastCompleteShortcut.trimmingCharacters(in: .whitespaces)
      guard parseShortcut(shortcut) != nil else { return }
      row.update(
        AppBinding(
          shortcut: shortcut, bundleID: row.binding.bundleID, label: row.binding.label,
          isEnabled: row.binding.isEnabled))
      row.setEditing(false)
      endShortcutCapture()
      setAppShortcutEditingMode(activeRow: nil)
      savePressed()
    } else {
      for otherRow in rows where otherRow !== row && otherRow.isEditing {
        otherRow.setEditing(false)
      }
      row.setEditing(true)
      setAppShortcutEditingMode(activeRow: row)
      beginShortcutCapture(for: row.shortcutField, label: row.binding.label)
      window?.makeFirstResponder(row.shortcutField)
    }
  }

  @objc private func editHideAllShortcut() {
    if isEditingHideAll {
      let shortcut = hideAllShortcutField.lastCompleteShortcut.trimmingCharacters(in: .whitespaces)
      guard parseShortcut(shortcut) != nil else { return }
      hideAllBinding.shortcut = shortcut
      isEditingHideAll = false
      endShortcutCapture()
      configureHideAllControls()
      setAppShortcutEditingMode(activeRow: nil)
      savePressed()
      return
    }

    isEditingHideAll = true
    hideAllShortcutField.lastCompleteShortcut = hideAllBinding.shortcut
    configureHideAllControls()
    setAppShortcutEditingMode(activeRow: nil)
    beginShortcutCapture(
      for: hideAllShortcutField,
      label: flowText("apps.hideAll"),
      onCancel: { [weak self] in self?.cancelHideAllEditing() }
    )
    window?.makeFirstResponder(hideAllShortcutField)
  }

  @objc private func clearHideAllShortcut() {
    if isEditingHideAll {
      cancelHideAllEditing()
      return
    }
    hideAllBinding = HideAllBinding(shortcut: "")
    configureHideAllControls()
    savePressed()
  }

  private func cancelHideAllEditing() {
    isEditingHideAll = false
    endShortcutCapture()
    configureHideAllControls()
    setAppShortcutEditingMode(activeRow: nil)
  }

  private func configureHideAllControls() {
    let configured = parseShortcut(hideAllBinding.shortcut) != nil
    if !isEditingHideAll {
      hideAllShortcutField.stringValue = hideAllBinding.shortcut
      hideAllShortcutField.lastCompleteShortcut = hideAllBinding.shortcut
    }
    hideAllShortcutField.isEditable = false
    hideAllShortcutField.isSelectable = false
    hideAllShortcutField.isBordered = isEditingHideAll
    hideAllShortcutField.drawsBackground = isEditingHideAll
    hideAllShortcutField.backgroundColor = isEditingHideAll ? .textBackgroundColor : .clear
    hideAllShortcutField.textColor =
      configured || isEditingHideAll ? .labelColor : .tertiaryLabelColor
    hideAllEditButton.title =
      isEditingHideAll
      ? flowText("apps.applyRow")
      : (configured ? flowText("apps.editRow") : flowText("apps.hideAllSet"))
    hideAllClearButton.image = NSImage(
      systemSymbolName: isEditingHideAll ? "xmark" : "trash",
      accessibilityDescription: isEditingHideAll
        ? flowText("apps.cancel") : flowText("apps.hideAllClear")
    )
    hideAllClearButton.contentTintColor = isEditingHideAll ? .controlAccentColor : .systemRed
    hideAllClearButton.toolTip =
      isEditingHideAll ? flowText("apps.cancel") : flowText("apps.hideAllClear")
    hideAllClearButton.isEnabled = isEditingHideAll || configured
  }

  private func beginShortcutCapture(
    for field: ShortcutCaptureField,
    label: String,
    onCancel: (() -> Void)? = nil
  ) {
    endShortcutCapture()
    activeShortcutField = field
    activeShortcutLabel = label
    field.hasCapturedCompleteShortcut = false
    field.onShortcutCaptured = { [weak field] shortcut in
      field?.stringValue = shortcut
      field?.lastCompleteShortcut = shortcut
      field?.needsDisplay = true
    }
    shortcutCaptureCancel =
      onCancel ?? { [weak self] in
        self?.activeEditingRow?.cancelEditing()
        self?.endShortcutCapture()
        self?.setAppShortcutEditingMode(activeRow: nil)
      }
    field.onCancelCapture = { [weak self] in self?.shortcutCaptureCancel?() }
    field.onFocus = { [weak self, weak field] in
      guard let self, let field else { return }
      guard self.activeEditingRow != nil else { return }
      if self.activeShortcutField !== field {
        self.beginShortcutCapture(for: field, label: self.activeEditingRow?.binding.label ?? label)
      }
    }
    onShortcutCaptureStart?()
    shortcutCaptureMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) {
      [weak self] event in
      guard let self, let field = self.activeShortcutField else { return event }
      guard self.window?.isKeyWindow == true, field.window?.firstResponder === field else {
        return event
      }
      if event.type == .flagsChanged {
        guard !field.hasCapturedCompleteShortcut else { return nil }
        if let modifiers = modifierString(from: event), !modifiers.isEmpty {
          field.stringValue = modifiers
          field.needsDisplay = true
        }
        return nil
      }
      if event.keyCode == 53 {
        self.shortcutCaptureCancel?()
        return nil
      }
      guard let shortcut = shortcutString(from: event) else { return nil }
      field.stringValue = shortcut
      field.lastCompleteShortcut = shortcut
      field.hasCapturedCompleteShortcut = true
      field.needsDisplay = true
      return nil
    }
  }

  private func setAppShortcutEditingMode(activeRow: BindingRow?) {
    activeEditingRow = activeRow
    let editing = activeRow != nil || isEditingHideAll
    for row in rows {
      row.enabledSwitch.isEnabled = appHotkeysSwitch.state == .on && !editing
      if row === activeRow {
        row.shortcutField.isCapturingShortcut = true
        row.editButton.isEnabled = true
        row.removeButton.isEnabled = true
        row.removeButton.title = flowText("apps.cancel")
        row.removeButton.image = NSImage(
          systemSymbolName: "xmark", accessibilityDescription: flowText("apps.cancel"))
        row.removeButton.imagePosition = .imageLeading
        row.removeButton.contentTintColor = .controlAccentColor
        row.removeButton.toolTip = flowText("apps.cancel")
        row.shortcutField.textColor = .labelColor
      } else {
        row.editButton.isEnabled = !editing
        row.removeButton.isEnabled = !editing
        if row.isEditing {
          row.setEditing(false)
        }
        row.shortcutField.isCapturingShortcut = false
      }
    }
    if activeRow == nil {
      for row in rows {
        row.shortcutField.isCapturingShortcut = false
        row.shortcutField.onShortcutCaptured = nil
        row.shortcutField.onCancelCapture = nil
        row.shortcutField.onFocus = nil
      }
    }
    hideAllShortcutField.isCapturingShortcut = isEditingHideAll
    hideAllEditButton.isEnabled = !editing || isEditingHideAll
    hideAllClearButton.isEnabled =
      isEditingHideAll || (!editing && parseShortcut(hideAllBinding.shortcut) != nil)
    appAddButton.isEnabled = !editing
    appHotkeysSwitch.isEnabled = !editing
    languagePopup.isEnabled = !editing
    footerReloadButton.isEnabled = !editing
  }

  private func endShortcutCapture() {
    stopShortcutCaptureMonitor(reloadHotkeys: true)
  }

  private func stopShortcutCaptureMonitor(reloadHotkeys: Bool) {
    if let shortcutCaptureMonitor {
      NSEvent.removeMonitor(shortcutCaptureMonitor)
      self.shortcutCaptureMonitor = nil
    }
    activeShortcutField?.onShortcutCaptured = nil
    activeShortcutField?.onCancelCapture = nil
    activeShortcutField?.isCapturingShortcut = false
    activeShortcutField?.hasCapturedCompleteShortcut = false
    activeShortcutField = nil
    activeShortcutLabel = ""
    shortcutCaptureCancel = nil
    if reloadHotkeys {
      onShortcutCaptureEnd?()
    }
  }

  private func updateAppsHint(count: Int) {
    appsHintLabel.stringValue =
      count == 0
      ? flowText("apps.hint")
      : "\(count)\(flowText("apps.countSuffix")) · \(flowText("apps.hint"))"
  }

  @objc private func chooseScreenshotDirectory() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.directoryURL = URL(fileURLWithPath: screenshotDirectoryPath, isDirectory: true)
    guard panel.runModal() == .OK, let url = panel.url else { return }
    guard setMacOSScreenshotLocation(url.path) else {
      statusLabel.stringValue = flowText("status.failed")
      return
    }
    screenshotDirectoryPath = url.path
    updateScreenshotFolderButton()
    saveRuntimeSettings()
  }

  @objc private func openScreenshotDirectory() {
    guard !screenshotDirectoryPath.isEmpty else { return }
    NSWorkspace.shared.open(URL(fileURLWithPath: screenshotDirectoryPath, isDirectory: true))
  }

  private func updateScreenshotFolderButton() {
    screenshotFolderButton.title = screenshotDirectoryPath
    screenshotFolderButton.toolTip = screenshotDirectoryPath
  }

  @objc private func toggleScreenshotWatch() {
    saveRuntimeSettings()
  }

  @objc private func toggleLoginLaunch() {
    loginLaunchSwitch.isEnabled = false
    do {
      try LoginLaunchManager.shared.setEnabled(loginLaunchSwitch.state == .on)
      statusLabel.stringValue = flowText("status.saved")
      if LoginLaunchManager.shared.status == .requiresApproval {
        LoginLaunchManager.shared.openSystemSettings()
      }
    } catch {
      statusLabel.stringValue = "\(flowText("status.failed")): \(error.localizedDescription)"
    }
    refreshLoginLaunchUI()
  }

  @objc private func removeAgent() {
    guard let window, removalSheet == nil else { return }
    let sheet = FlowRemovalSheetController()
    removalSheet = sheet
    sheet.present(from: window) { [weak self] options in
      guard let self else { return }
      self.removalSheet = nil
      guard let options else { return }
      self.removeAgentButton.isEnabled = false
      self.statusLabel.stringValue = flowText("general.removeProgress")
      FlowRemovalCoordinator.remove(options: options) { [weak self] result in
        guard case .failure(let error) = result else { return }
        self?.removeAgentButton.isEnabled = true
        self?.statusLabel.stringValue = error.localizedDescription
      }
    }
  }

  private func refreshLoginLaunchUI() {
    let status = LoginLaunchManager.shared.status
    let text: String
    let tint: NSColor
    switch status {
    case .disabled:
      loginLaunchSwitch.state = .off
      loginLaunchSwitch.isEnabled = true
      text = flowText("state.off")
      tint = .secondaryLabelColor
    case .enabled:
      loginLaunchSwitch.state = .on
      loginLaunchSwitch.isEnabled = true
      text = flowText("state.on")
      tint = .systemGreen
    case .requiresApproval:
      loginLaunchSwitch.state = .on
      loginLaunchSwitch.isEnabled = true
      text = flowText("general.status.approval")
      tint = .systemOrange
    case .needsRepair:
      loginLaunchSwitch.state = .on
      loginLaunchSwitch.isEnabled = true
      text = flowText("general.status.repair")
      tint = .systemOrange
    case .appNotInstalled:
      loginLaunchSwitch.state = .off
      loginLaunchSwitch.isEnabled = false
      text = flowText("general.status.install")
      tint = .systemOrange
    }
    loginLaunchStatusLabel.stringValue = text
    loginLaunchStatusLabel.textColor = tint
    loginLaunchStatusLabel.layer?.backgroundColor = tint.withAlphaComponent(0.1).cgColor
  }

  @objc private func toggleAppHotkeys() {
    let enabled = appHotkeysSwitch.state == .on
    for row in rows {
      row.enabledSwitch.state = enabled ? .on : .off
      row.binding.isEnabled = enabled
      row.refreshEnabledAppearance()
    }
    updateAppHotkeyControls()
    savePressed()
  }

  private func updateAppHotkeyControls() {
    let masterEnabled = appHotkeysSwitch.state == .on
    let individuallyEditable = masterEnabled && activeEditingRow == nil
    for row in rows {
      if !masterEnabled {
        row.enabledSwitch.state = .off
        row.binding.isEnabled = false
        row.refreshEnabledAppearance()
      }
      row.enabledSwitch.isEnabled = individuallyEditable
    }
  }

  @objc private func toggleKeepAwake() {
    refreshKeepAwakeUI()
    saveRuntimeSettings()
    if keepAwakeSwitch.state == .on {
      onKeepAwakeAuthorizationRequest?(false)
    }
  }

  @objc private func requestKeepAwakeAuthorization() {
    onKeepAwakeAuthorizationRequest?(true)
  }

  @objc private func changeKeepAwakePowerScope() {
    saveRuntimeSettings()
  }

  @objc private func toggleLockOnLidClose() {
    let needsAccessibility = lockOnLidCloseSwitch.state == .on && !AXIsProcessTrusted()
    if needsAccessibility {
      let options =
        [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
      AXIsProcessTrustedWithOptions(options)
    }
    saveRuntimeSettings()
    if needsAccessibility && !AXIsProcessTrusted() {
      statusLabel.stringValue = flowText("dock.status.needsPermission")
    }
  }

  @objc private func toggleMouseScrollReverse() {
    refreshMouseScrollUI()
    saveRuntimeSettings()
  }

  @objc private func toggleDockPin() {
    saveRuntimeSettings()
    refreshDockPinUI(status: dockPinStatusProvider())
  }

  @objc private func toggleDockTiming() {
    do {
      try DockAutoHideTiming.setFastEnabled(dockTimingSwitch.state == .on)
      refreshDockTimingUI()
      statusLabel.stringValue = flowText("status.saved")
      DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
        self?.refreshDockPinUI(status: self?.dockPinStatusProvider())
      }
    } catch {
      refreshDockTimingUI()
      statusLabel.stringValue = "\(flowText("status.failed")): \(error.localizedDescription)"
    }
  }

  @objc private func openAccessibilitySettings() {
    let options =
      [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    AXIsProcessTrustedWithOptions(options)
    if let url = URL(
      string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    {
      NSWorkspace.shared.open(url)
    }
    refreshMouseScrollUI(
      status: AXIsProcessTrusted() ? nil : flowText("devices.mouse.status.needsPermission"))
    refreshDockPinUI(
      status: AXIsProcessTrusted() ? dockPinStatusProvider() : .needsPermission)
  }

  @objc func reloadPressed() {
    loadFromDisk()
  }

  @objc private func savePressed() {
    let bindings = rows.compactMap { row -> AppBinding? in
      let shortcut = row.shortcutField.lastCompleteShortcut.trimmingCharacters(in: .whitespaces)
      guard parseShortcut(shortcut) != nil else { return nil }
      return AppBinding(
        shortcut: shortcut,
        bundleID: row.binding.bundleID,
        label: row.binding.label,
        isEnabled: row.enabledSwitch.state == .on
      )
    }
    do {
      try config.saveBindings(bindings, hideAllBinding: hideAllBinding)
      try config.saveBootstrap(
        appHotkeysEnabled: appHotkeysSwitch.state == .on,
        mouseScrollReverseEnabled: mouseScrollReverseSwitch.state == .on,
        screenshotDir: screenshotDirectoryPath,
        screenshotClipboardWatch: screenshotWatchSwitch.state == .on,
        keepAwakeEnabled: keepAwakeSwitch.state == .on,
        keepAwakeOnBattery: keepAwakePowerScopeControl.selectedSegment == 1,
        lockOnLidClose: lockOnLidCloseSwitch.state == .on,
        dockPinEnabled: dockPinSwitch.state == .on,
        dockPinDisplayID: selectedDockDisplayID()
      )
      statusLabel.stringValue = flowText("status.saved")
      onSave?()
    } catch {
      statusLabel.stringValue = "\(flowText("status.failed")): \(error.localizedDescription)"
    }
  }

  @objc private func saveRuntimeSettings() {
    do {
      try config.saveBootstrap(
        appHotkeysEnabled: appHotkeysSwitch.state == .on,
        mouseScrollReverseEnabled: mouseScrollReverseSwitch.state == .on,
        screenshotDir: screenshotDirectoryPath,
        screenshotClipboardWatch: screenshotWatchSwitch.state == .on,
        keepAwakeEnabled: keepAwakeSwitch.state == .on,
        keepAwakeOnBattery: keepAwakePowerScopeControl.selectedSegment == 1,
        lockOnLidClose: lockOnLidCloseSwitch.state == .on,
        dockPinEnabled: dockPinSwitch.state == .on,
        dockPinDisplayID: selectedDockDisplayID()
      )
      statusLabel.stringValue = flowText("status.saved")
      onSave?()
    } catch {
      statusLabel.stringValue = "\(flowText("status.failed")): \(error.localizedDescription)"
    }
  }
}
