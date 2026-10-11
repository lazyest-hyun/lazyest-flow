import AppKit
import ApplicationServices
import Foundation
import LazyestCore

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
  private let isPreview: Bool
  private let config: Config
  private let screenshotStatusProvider: () -> Bool
  private let dockPinStatusProvider: () -> DockPinStatus
  private let keepAwakeStatusProvider: () -> KeepAwakeStatus
  private let automaticLoginStatusLabel = NSTextField(wrappingLabelWithString: "")
  private var automaticLoginQueryPending = false
  private var loginSecuritySnapshot: LoginSecuritySnapshot?
  private var loginSecuritySession = LoginSecurityChangeSession()
  private let startupLoginChoice = NSPopUpButton()
  private let wakeLoginChoice = NSPopUpButton()
  private let startupLoginObservationLabel = NSTextField(wrappingLabelWithString: "")
  private let wakeLoginObservationLabel = NSTextField(wrappingLabelWithString: "")
  private lazy var reviewStartupLoginButton = actionButton(
    title: flowText("login.reviewChange"), action: #selector(reviewStartupLoginChange))
  private lazy var reviewWakeLoginButton = actionButton(
    title: flowText("login.reviewChange"), action: #selector(reviewWakeLoginChange))
  private lazy var applyLoginSecurityButton = actionButton(
    title: flowText("login.apply"), action: #selector(applyLoginSecurityChange))
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
  private lazy var screenshotPermissionButton = actionButton(
    title: flowText("dock.permission"), action: #selector(openAccessibilitySettings))
  private let screenshotStatusLabel = NSTextField(labelWithString: "")
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
  private lazy var sleepOnKoreanLidCloseSwitch = settingSwitch(
    action: #selector(toggleSleepOnKoreanLidClose))
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
  private var tabButtons: [SettingsNavigationButton] = []
  private static let selectedPageKey = "LazyestFlow.settingsPage.v1"
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
    previewMode: Bool = false,
    dockPinStatusProvider: @escaping () -> DockPinStatus,
    screenshotStatusProvider: @escaping () -> Bool,
    keepAwakeStatusProvider: @escaping () -> KeepAwakeStatus
  ) {
    self.isPreview = previewMode
    self.config = config
    self.screenshotStatusProvider = screenshotStatusProvider
    self.dockPinStatusProvider = dockPinStatusProvider
    self.keepAwakeStatusProvider = keepAwakeStatusProvider
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.contentView = FlowSettingsBackgroundView(
      frame: NSRect(x: 0, y: 0, width: 900, height: 620))
    window.title = flowText("title")
    window.isReleasedWhenClosed = false
    window.minSize = NSSize(width: 860, height: 580)
    super.init(window: window)
    window.delegate = self
    buildUI()
    if !previewMode {
      if !window.setFrameUsingName("LazyestFlow.Settings") { window.center() }
      window.setFrameAutosaveName("LazyestFlow.Settings")
    }
    if previewMode {
      configurePreview()
      return
    }
    observers = [
      NotificationCenter.default.addObserver(
        forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
      ) { [weak self] _ in
        guard let self,
          self.settingsTabs.selectedTabViewItem?.identifier as? String == "automatic-login"
        else { return }
        self.refreshAutomaticLoginStatus()
      },
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
        self?.cancelShortcutEditing()
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
    let sidebar = NSVisualEffectView()
    sidebar.material = .sidebar
    sidebar.blendingMode = .withinWindow
    sidebar.state = .active
    sidebar.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(sidebar)

    let navigation = NSStackView()
    navigation.orientation = .vertical
    navigation.alignment = .leading
    navigation.spacing = 4
    navigation.edgeInsets = NSEdgeInsets(top: 24, left: 12, bottom: 14, right: 12)
    navigation.translatesAutoresizingMaskIntoConstraints = false
    sidebar.addSubview(navigation)
    let brand = NSTextField(labelWithString: "Lazyest Flow")
    brand.font = .systemFont(ofSize: 16, weight: .semibold)
    brand.heightAnchor.constraint(equalToConstant: 30).isActive = true
    navigation.addArrangedSubview(brand)
    navigation.setCustomSpacing(20, after: brand)

    let definitions: [(Int, String, String)] = [
      (1, "tab.apps", "command"), (2, "tab.inputDevices", "keyboard"),
      (3, "tab.screenshots", "camera.viewfinder"), (5, "tab.dockPin", "dock.rectangle"),
      (4, "tab.keepAwake", "moon"), (6, "tab.automaticLogin", "person.crop.circle"),
      (0, "tab.general", "gearshape"),
    ]
    for (position, definition) in definitions.enumerated() {
      if position == 0 || position == 2 || position == 4 {
        let key = position == 0 ? "nav.work" : (position == 2 ? "nav.screen" : "nav.system")
        let label = NSTextField(labelWithString: flowText(key))
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        if position > 0 { navigation.setCustomSpacing(18, after: navigation.arrangedSubviews.last!) }
        navigation.addArrangedSubview(label)
        navigation.setCustomSpacing(6, after: label)
      }
      let button = SettingsNavigationButton(title: flowText(definition.1), symbolName: definition.2)
      button.target = self
      button.action = #selector(selectSettingsTab(_:))
      button.tag = definition.0
      tabButtons.append(button)
      navigation.addArrangedSubview(button)
    }
    for view in navigation.arrangedSubviews {
      view.widthAnchor.constraint(equalTo: navigation.widthAnchor, constant: -24).isActive = true
    }
    navigation.addArrangedSubview(NSView())

    let detail = NSView()
    detail.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(detail)
    let divider = separator()
    divider.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(divider)
    settingsTabs.tabViewType = .noTabsNoBorder
    settingsTabs.translatesAutoresizingMaskIntoConstraints = false
    for page in [generalTab(), appBindingsTab(), inputDevicesTab(), screenshotsTab(), keepAwakeTab(), dockPinTab(), automaticLoginTab()] {
      settingsTabs.addTabViewItem(page)
    }
    detail.addSubview(settingsTabs)
    let fillWidth = settingsTabs.widthAnchor.constraint(equalTo: detail.widthAnchor)
    fillWidth.priority = .defaultHigh

    let footer = NSStackView()
    footer.orientation = .horizontal
    footer.alignment = .centerY
    footer.spacing = 8
    footer.translatesAutoresizingMaskIntoConstraints = false
    statusLabel.textColor = .secondaryLabelColor
    statusLabel.font = NSFont.systemFont(ofSize: 11)
    statusLabel.lineBreakMode = .byTruncatingTail
    statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    footerReloadButton.isBordered = false
    footer.addArrangedSubview(statusLabel)
    footer.addArrangedSubview(NSView())
    footer.addArrangedSubview(footerReloadButton)
    detail.addSubview(footer)
    NSLayoutConstraint.activate([
      sidebar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      sidebar.topAnchor.constraint(equalTo: contentView.topAnchor),
      sidebar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
      sidebar.widthAnchor.constraint(equalToConstant: 176),
      navigation.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
      navigation.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
      navigation.topAnchor.constraint(equalTo: sidebar.topAnchor),
      navigation.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor),
      divider.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
      divider.widthAnchor.constraint(equalToConstant: 1),
      divider.topAnchor.constraint(equalTo: contentView.topAnchor),
      divider.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
      detail.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
      detail.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      detail.topAnchor.constraint(equalTo: contentView.topAnchor),
      detail.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
      settingsTabs.topAnchor.constraint(equalTo: detail.topAnchor),
      settingsTabs.centerXAnchor.constraint(equalTo: detail.centerXAnchor),
      settingsTabs.widthAnchor.constraint(lessThanOrEqualTo: detail.widthAnchor),
      settingsTabs.widthAnchor.constraint(lessThanOrEqualToConstant: 820), fillWidth,
      settingsTabs.bottomAnchor.constraint(equalTo: footer.topAnchor),
      footer.leadingAnchor.constraint(equalTo: settingsTabs.leadingAnchor, constant: 24),
      footer.trailingAnchor.constraint(equalTo: settingsTabs.trailingAnchor, constant: -24),
      footer.heightAnchor.constraint(equalToConstant: 36),
      footer.bottomAnchor.constraint(equalTo: detail.bottomAnchor, constant: -8),
    ])
    let saved = isPreview ? nil : UserDefaults.standard.string(forKey: Self.selectedPageKey)
    let index = settingsTabs.tabViewItems.firstIndex { ($0.identifier as? String) == saved } ?? 1
    selectPage(index)
  }

  private func selectPage(_ index: Int) {
    guard settingsTabs.tabViewItems.indices.contains(index) else { return }
    cancelShortcutEditing()
    settingsTabs.selectTabViewItem(at: index)
    if index == 6, !isPreview { refreshAutomaticLoginStatus() }
    for button in tabButtons { button.isSelectedTab = button.tag == index }
    if !isPreview, let identifier = settingsTabs.selectedTabViewItem?.identifier as? String {
      UserDefaults.standard.set(identifier, forKey: Self.selectedPageKey)
    }
  }

  private func cancelShortcutEditing() {
    if activeEditingRow != nil || isEditingHideAll {
      activeEditingRow?.cancelEditing()
      isEditingHideAll = false
      stopShortcutCaptureMonitor(reloadHotkeys: true)
      configureHideAllControls()
      setAppShortcutEditingMode(activeRow: nil)
      window?.makeFirstResponder(nil)
    }
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

  @objc private func selectSettingsTab(_ sender: SettingsNavigationButton) {
    selectPage(sender.tag)
    guard !isPreview else { return }
    if sender.tag == 0 { refreshLoginLaunchUI() }
    if sender.tag == 5 {
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
    button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
    button.setAccessibilityLabel(tooltip)
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

  private func pageHeader(title: String, detail: String) -> NSView {
    // A missing description must not move peer pages' content upward.
    let header = NSView()
    header.identifier = NSUserInterfaceItemIdentifier("settings-page-header")
    header.heightAnchor.constraint(equalToConstant: 50).isActive = true
    let titleLabel = NSTextField(labelWithString: title)
    titleLabel.identifier = NSUserInterfaceItemIdentifier("settings-page-title")
    titleLabel.font = NSFont.systemFont(ofSize: 22, weight: .semibold)
    titleLabel.alignment = .left
    titleLabel.lineBreakMode = .byTruncatingTail
    let detailLabel = NSTextField(labelWithString: detail)
    detailLabel.identifier = NSUserInterfaceItemIdentifier("settings-page-detail")
    detailLabel.textColor = .secondaryLabelColor
    detailLabel.font = NSFont.systemFont(ofSize: 12)
    detailLabel.alignment = .left
    detailLabel.lineBreakMode = .byTruncatingTail
    detailLabel.toolTip = detail.isEmpty ? nil : detail
    detailLabel.setAccessibilityElement(!detail.isEmpty)
    for label in [titleLabel, detailLabel] {
      label.translatesAutoresizingMaskIntoConstraints = false
      header.addSubview(label)
    }
    NSLayoutConstraint.activate([
      titleLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor),
      titleLabel.trailingAnchor.constraint(equalTo: header.trailingAnchor),
      titleLabel.topAnchor.constraint(equalTo: header.topAnchor),
      titleLabel.heightAnchor.constraint(equalToConstant: 28),
      detailLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor),
      detailLabel.trailingAnchor.constraint(equalTo: header.trailingAnchor),
      detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
      detailLabel.heightAnchor.constraint(equalToConstant: 18),
    ])
    return header
  }

  private func settingRow(title: String, detail: String = "", control: NSView) -> NSStackView {
    let row = NSStackView()
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 12
    row.edgeInsets = NSEdgeInsets(top: 9, left: 0, bottom: 9, right: 0)

    let labels = NSStackView()
    labels.orientation = .vertical
    labels.alignment = .leading
    labels.spacing = 2
    let titleLabel = NSTextField(wrappingLabelWithString: title)
    titleLabel.font = NSFont.systemFont(ofSize: 13)
    let heading = NSStackView(views: [titleLabel])
    heading.spacing = 6
    heading.alignment = .centerY
    if !detail.isEmpty {
      let help = NSImageView(
        image: NSImage(
          systemSymbolName: "info.circle", accessibilityDescription: detail) ?? NSImage())
      help.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
      help.contentTintColor = .tertiaryLabelColor
      help.toolTip = detail
      help.setAccessibilityLabel(detail)
      help.setContentHuggingPriority(.required, for: .horizontal)
      heading.addArrangedSubview(help)
      titleLabel.toolTip = detail
      control.toolTip = detail
      control.setAccessibilityHelp(detail)
    }
    control.setAccessibilityLabel(title)
    labels.addArrangedSubview(heading)
    labels.setContentHuggingPriority(.defaultLow, for: .horizontal)
    row.addArrangedSubview(labels)
    row.addArrangedSubview(NSView())
    control.setContentHuggingPriority(.required, for: .horizontal)
    row.addArrangedSubview(control)
    row.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
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

  private func settingsPage(title: String, detail: String) -> NSStackView {
    let page = NSStackView()
    page.orientation = .vertical
    page.alignment = .leading
    page.spacing = 20
    page.edgeInsets = NSEdgeInsets(top: 26, left: 24, bottom: 18, right: 24)
    let header = pageHeader(title: title, detail: detail)
    page.addArrangedSubview(header)
    header.widthAnchor.constraint(equalTo: page.widthAnchor, constant: -48).isActive = true
    page.setCustomSpacing(24, after: header)
    return page
  }

  private func settingsGroup(title: String? = nil, reserveTitle: Bool = false, rows: [NSView]) -> NSStackView {
    let group = NSStackView()
    group.orientation = .vertical
    group.alignment = .leading
    group.spacing = 8
    // The first card starts on one baseline, with or without a section heading.
    if title != nil || reserveTitle {
      let label = NSTextField(labelWithString: title ?? "")
      label.font = .systemFont(ofSize: 12, weight: .semibold)
      label.textColor = .secondaryLabelColor
      label.alignment = .left
      label.heightAnchor.constraint(equalToConstant: 16).isActive = true
      label.setAccessibilityElement(title != nil)
      group.addArrangedSubview(label)
    }
    let card = AdaptiveCardStackView()
    card.orientation = .vertical
    card.alignment = .width
    card.spacing = 0
    card.edgeInsets = NSEdgeInsets(top: 4, left: 14, bottom: 4, right: 14)
    for (index, row) in rows.enumerated() {
      if index > 0 { card.addArrangedSubview(separator()) }
      card.addArrangedSubview(row)
    }
    group.addArrangedSubview(card)
    card.widthAnchor.constraint(equalTo: group.widthAnchor).isActive = true
    for row in card.arrangedSubviews {
      row.widthAnchor.constraint(equalTo: card.widthAnchor, constant: -28).isActive = true
    }
    return group
  }

  private func controls(_ views: [NSView]) -> NSStackView {
    let row = NSStackView(views: views)
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 8
    return row
  }

  private func statusView(_ label: NSTextField) -> NSView {
    label.font = .systemFont(ofSize: 11)
    label.lineBreakMode = .byTruncatingTail
    label.textColor = .secondaryLabelColor
    let view = NSView()
    view.heightAnchor.constraint(equalToConstant: 28).isActive = true
    label.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(label)
    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      label.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor),
      label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
    ])
    return view
  }

  private func scrollableTabView(content: NSView) -> NSScrollView {
    if let page = content as? NSStackView {
      let horizontalInset = page.edgeInsets.left + page.edgeInsets.right
      for view in page.arrangedSubviews {
        view.widthAnchor.constraint(equalTo: page.widthAnchor, constant: -horizontalInset).isActive = true
      }
    }
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 684, height: 540))
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
    let tint: NSColor = isActive ? .systemBlue : (isOff ? .secondaryLabelColor : .systemOrange)
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
    let tint: NSColor = isActive ? .systemBlue : (isOff ? .secondaryLabelColor : .systemOrange)
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
      tint = .systemBlue
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
    sleepOnKoreanLidCloseSwitch.isEnabled = enabled

    let runtimeStatus = status ?? keepAwakeStatusProvider()
    let resolvedStatus: KeepAwakeStatus = enabled ? runtimeStatus : .off(runtimeStatus.power)
    switch resolvedStatus {
    case .helperApprovalRequired:
      keepAwakeApprovalButton.isHidden = false
    default:
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
      tint = .systemBlue
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
    keepAwakeStatusLabel.stringValue = "\(statusText)  —  \(powerText)"
    keepAwakeStatusLabel.textColor = tint
    if case .helperUnavailable = resolvedStatus {
      keepAwakeStatusLabel.toolTip = flowText("keep.helperUnavailableHelp")
    } else {
      keepAwakeStatusLabel.toolTip = keepAwakeStatusLabel.stringValue
    }
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
    let root = settingsPage(title: flowText("tab.apps"), detail: flowText("apps.hint"))
    root.addArrangedSubview(settingsGroup(reserveTitle: true, rows: [
      settingRow(title: flowText("apps.enabled"), control: appHotkeysSwitch),
      settingRow(title: flowText("apps.hideAll"), detail: flowText("apps.hideAllDetail"), control: appHotkeyControls()),
    ]))
    let heading = NSStackView()
    heading.alignment = .centerY
    heading.spacing = 8
    appsHintLabel.font = .systemFont(ofSize: 12, weight: .semibold)
    appsHintLabel.textColor = .secondaryLabelColor
    appsHintLabel.toolTip = flowText("apps.hint")
    heading.addArrangedSubview(appsHintLabel)
    heading.addArrangedSubview(NSView())
    appAddButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: flowText("apps.addRunning"))
    appAddButton.imagePosition = .imageLeading
    heading.addArrangedSubview(appAddButton)
    root.addArrangedSubview(heading)
    root.setCustomSpacing(8, after: heading)
    bindingsStack.orientation = .vertical
    bindingsStack.alignment = .width
    bindingsStack.spacing = 6
    root.addArrangedSubview(bindingsStack)
    item.view = scrollableTabView(content: root)
    return item
  }

  private func appHotkeyControls() -> NSStackView {
    hideAllShortcutField.widthAnchor.constraint(equalToConstant: 110).isActive = true
    hideAllShortcutField.alignment = .center
    hideAllShortcutField.placeholderString = flowText("apps.notSet")
    hideAllEditButton.widthAnchor.constraint(equalToConstant: 72).isActive = true
    hideAllClearButton.widthAnchor.constraint(equalToConstant: 40).isActive = true
    let controls = NSStackView(views: [
      hideAllShortcutField, hideAllEditButton, hideAllClearButton,
    ])
    controls.orientation = .horizontal
    controls.alignment = .centerY
    controls.spacing = 8
    configureHideAllControls()
    return controls
  }

  private func automaticLoginTab() -> NSTabViewItem {
    let item = NSTabViewItem(identifier: "automatic-login")
    item.label = flowText("tab.automaticLogin")
    let root = settingsPage(title: flowText("login.title"), detail: flowText("login.detail"))
    automaticLoginStatusLabel.font = .systemFont(ofSize: 12)
    automaticLoginStatusLabel.setContentCompressionResistancePriority(.required, for: .vertical)
    automaticLoginStatusLabel.stringValue = flowText("login.status.unknown")
    startupLoginObservationLabel.stringValue = flowText("login.current.unknown")
    wakeLoginObservationLabel.stringValue = flowText("login.current.unknown")
    startupLoginChoice.addItems(withTitles: [
      flowText("login.choose"), flowText("login.choice.startupOff"),
      flowText("login.choice.startupCurrent"),
    ])
    wakeLoginChoice.addItems(withTitles: [
      flowText("login.choose"), flowText("login.choice.immediate"),
      flowText("login.choice.fiveSeconds"), flowText("login.choice.oneMinute"),
      flowText("login.choice.fiveMinutes"), flowText("login.choice.off"),
    ])
    for popup in [startupLoginChoice, wakeLoginChoice] {
      popup.target = self
      popup.action = #selector(loginSecurityChoiceChanged)
      popup.widthAnchor.constraint(equalToConstant: 180).isActive = true
    }
    reviewStartupLoginButton.isEnabled = false
    reviewWakeLoginButton.isEnabled = false
    applyLoginSecurityButton.isEnabled = false
    root.addArrangedSubview(
      settingsGroup(
        reserveTitle: true,
        rows: [
          automaticLoginNote(flowText("login.physicalAccess")),
          automaticLoginNote(flowText("login.directGate")),
          settingRow(title: flowText("login.requestedStartup"), control: startupLoginChoice),
          automaticLoginNoteRow(startupLoginObservationLabel),
          settingRow(title: flowText("login.changePlan"), control: reviewStartupLoginButton),
          settingRow(
            title: flowText("login.startup"),
            control: actionButton(
              title: flowText("login.openSettings"), action: #selector(openAutomaticLoginSettings))),
          automaticLoginNote(flowText("login.startupRoute")),
          automaticLoginNoteRow(automaticLoginStatusLabel),
          automaticLoginNote(flowText("login.restrictions")),
          settingRow(
            title: flowText("login.refresh"),
            control: actionButton(
              title: flowText("footer.reload"), action: #selector(refreshAutomaticLoginStatus))),
        ]))
    root.addArrangedSubview(
      settingsGroup(
        title: flowText("login.wake"),
        rows: [
          automaticLoginNote(flowText("login.wakeDetail")),
          settingRow(title: flowText("login.requestedWake"), control: wakeLoginChoice),
          automaticLoginNoteRow(wakeLoginObservationLabel),
          settingRow(title: flowText("login.changePlan"), control: reviewWakeLoginButton),
          settingRow(
            title: flowText("login.wakeRoute"),
            control: actionButton(
              title: flowText("login.openSettings"), action: #selector(openAutomaticLoginSettings))),
        ]))
    root.addArrangedSubview(
      settingsGroup(
        title: flowText("login.before"),
        rows: [
          automaticLoginNote(flowText("login.handoff")),
          settingRow(title: flowText("login.directGateShort"), control: applyLoginSecurityButton),
          settingRow(
            title: flowText("login.appleGuide"),
            control: actionButton(
              title: flowText("login.readGuide"), action: #selector(openAutomaticLoginGuide))),
        ]))
    item.view = scrollableTabView(content: root)
    return item
  }

  private func automaticLoginNote(_ text: String) -> NSView {
    let label = NSTextField(wrappingLabelWithString: text)
    label.font = .systemFont(ofSize: 12)
    label.textColor = .secondaryLabelColor
    label.setContentCompressionResistancePriority(.required, for: .vertical)
    return automaticLoginNoteRow(label)
  }

  private func automaticLoginNoteRow(_ label: NSTextField) -> NSView {
    let row = NSStackView(views: [label])
    row.orientation = .vertical
    row.alignment = .width
    row.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
    label.widthAnchor.constraint(equalTo: row.widthAnchor).isActive = true
    return row
  }

  @objc private func refreshAutomaticLoginStatus() {
    guard !isPreview, !automaticLoginQueryPending else { return }
    automaticLoginQueryPending = true
    loginSecuritySnapshot = nil
    loginSecuritySession.cancel()
    updateLoginSecurityChoices()
    startupLoginObservationLabel.stringValue = flowText("login.current.checking")
    wakeLoginObservationLabel.stringValue = flowText("login.current.checking")
    automaticLoginStatusLabel.stringValue = flowText("login.status.checking")
    AutomaticLoginSupport.queryFileVault { [weak self] fileVault in
      guard let self else { return }
      let key: String
      switch AutomaticLoginPolicy.eligibility(fileVault: fileVault) {
      case .blockedByFileVault: key = "login.status.blocked"
      case .needsSystemSettingsReview: key = "login.status.review"
      case .unknown: key = "login.status.unknown"
      }
      self.automaticLoginStatusLabel.stringValue = flowText(key)
      LoginSecurityStatusReader.query(fileVault: fileVault) { [weak self] snapshot in
        guard let self else { return }
        self.automaticLoginQueryPending = false
        self.loginSecuritySnapshot = snapshot
        self.startupLoginObservationLabel.stringValue = self.startupObservationText(
          snapshot.startup)
        self.wakeLoginObservationLabel.stringValue = self.wakeObservationText(snapshot.wake)
        self.updateLoginSecurityChoices()
      }
    }
  }

  private func selectedStartupAction() -> LoginSecurityAction? {
    switch startupLoginChoice.indexOfSelectedItem {
    case 1: return .startupOff
    case 2: return .startupCurrentUser
    default: return nil
    }
  }

  private func selectedWakeAction() -> LoginSecurityAction? {
    let index = wakeLoginChoice.indexOfSelectedItem - 1
    guard WakePasswordDelay.allCases.indices.contains(index) else { return nil }
    return .wake(WakePasswordDelay.allCases[index])
  }

  @objc private func loginSecurityChoiceChanged() {
    loginSecuritySession.cancel()
    updateLoginSecurityChoices()
  }

  private func updateLoginSecurityChoices() {
    guard !isPreview, let snapshot = loginSecuritySnapshot else {
      reviewStartupLoginButton.isEnabled = false
      reviewWakeLoginButton.isEnabled = false
      return
    }
    reviewStartupLoginButton.isEnabled =
      selectedStartupAction().flatMap {
        LoginSecurityCommandPlan.make(action: $0, snapshot: snapshot)
      } != nil
    reviewWakeLoginButton.isEnabled =
      selectedWakeAction().flatMap {
        LoginSecurityCommandPlan.make(action: $0, snapshot: snapshot)
      } != nil
    // No real apply is offered until per-action OS-owned authentication and
    // account-password transport are verified. Selection is never persistence.
    applyLoginSecurityButton.isEnabled = false
  }

  private func startupObservationText(_ observed: StartupLoginObservation) -> String {
    switch observed {
    case .off: return flowText("login.current.startupOff")
    case .user(let name): return flowText("login.current.startupUser") + " " + name
    case .blockedByFileVault: return flowText("login.status.blocked")
    case .unknown: return flowText("login.current.unknown")
    }
  }

  private func wakeObservationText(_ observed: WakeLoginObservation) -> String {
    switch observed {
    case .off: return flowText("login.current.wakeOff")
    case .seconds(0): return flowText("login.current.wakeImmediate")
    case .seconds(let seconds): return flowText("login.current.wakeSeconds") + " \(seconds)"
    case .unknown: return flowText("login.current.unknown")
    }
  }

  @objc private func reviewStartupLoginChange() {
    reviewLoginSecurityChange(selectedStartupAction())
  }
  @objc private func reviewWakeLoginChange() { reviewLoginSecurityChange(selectedWakeAction()) }

  private func reviewLoginSecurityChange(_ action: LoginSecurityAction?) {
    guard !isPreview, let action, let snapshot = loginSecuritySnapshot else { return }
    loginSecuritySession.choose(action, snapshot: snapshot)
    guard let plan = loginSecuritySession.plan else { return }
    statusLabel.stringValue = flowText("login.phase.confirm")
    let alert = NSAlert()
    alert.messageText = flowText("login.confirmTitle")
    let before: String
    let after: String
    switch action {
    case .startupOff:
      before = startupObservationText(snapshot.startup)
      after = flowText("login.choice.startupOff")
    case .startupCurrentUser:
      before = startupObservationText(snapshot.startup)
      after = flowText("login.choice.startupCurrent")
    case .wake(let delay):
      before = wakeObservationText(snapshot.wake)
      after = wakeLoginChoice.titleOfSelectedItem ?? delay.rawValue
    }
    alert.informativeText =
      "\(flowText("login.account")): \(plan.identity.userName)\n\(before)\n\(flowText("login.requested")): \(after)\n\n\(flowText("login.physicalAccess"))\n\n\(flowText("login.directGate"))"
    alert.addButton(withTitle: flowText("login.confirmPlan"))
    alert.addButton(withTitle: flowText("apps.cancel"))
    guard alert.runModal() == .alertFirstButtonReturn else {
      loginSecuritySession.cancel()
      updateLoginSecurityPhase(.cancelled)
      return
    }
    // This only exercises the explicit production gate; it cannot prompt or write.
    applyLoginSecurityChange()
  }

  @objc private func applyLoginSecurityChange() {
    guard !isPreview, let snapshot = loginSecuritySnapshot else { return }
    let runner = GatedLoginSecurityRunner { [weak self] in
      guard let self, LoginSecurityStatusReader.consoleIdentity() == snapshot.identity else {
        return LoginSecuritySnapshot(
          identity: nil, capabilities: .unknown, fileVault: .unknown,
          startup: .unknown, wake: .unknown)
      }
      return self.loginSecuritySnapshot
        ?? LoginSecuritySnapshot(
          identity: nil, capabilities: .unknown,
          fileVault: .unknown, startup: .unknown, wake: .unknown)
    }
    loginSecuritySession.confirm(using: runner) { [weak self] phase in
      self?.updateLoginSecurityPhase(phase)
    }
    if let observed = loginSecuritySession.lastObservation {
      loginSecuritySnapshot = observed
      startupLoginObservationLabel.stringValue = startupObservationText(observed.startup)
      wakeLoginObservationLabel.stringValue = wakeObservationText(observed.wake)
    }
  }

  private func updateLoginSecurityPhase(_ phase: LoginSecurityPhase) {
    let key: String
    switch phase {
    case .idle: key = "login.phase.idle"
    case .awaitingConfirmation: key = "login.phase.confirm"
    case .authenticating: key = "login.phase.auth"
    case .applying: key = "login.phase.applying"
    case .verifying: key = "login.phase.readback"
    case .applied: key = "login.phase.applied"
    case .cancelled: key = "login.phase.cancelled"
    case .failed(.authenticationTransportUnverified): key = "login.directGateShort"
    case .failed(.contextChanged): key = "login.phase.changed"
    case .failed(.unsupported): key = "login.phase.unsupported"
    case .failed(.denied): key = "login.phase.denied"
    case .failed(.outcomeUnknown): key = "login.phase.unknown"
    case .failed(.readbackMismatch): key = "login.phase.mismatch"
    case .failed(.commandFailed): key = "login.phase.failed"
    }
    statusLabel.stringValue = flowText(key)
  }

  @objc private func openAutomaticLoginSettings() {
    guard !isPreview else { return }
    AutomaticLoginSupport.openSystemSettings { [weak self] opened in
      self?.statusLabel.stringValue = flowText(
        opened ? "login.settingsRoute" : "login.settingsFailed")
    }
  }

  @objc private func openAutomaticLoginGuide() {
    guard !isPreview else { return }
    let url = URL(string: "https://support.apple.com/102316")!
    if !NSWorkspace.shared.open(url) { statusLabel.stringValue = flowText("login.guideFailed") }
  }

  private func generalTab() -> NSTabViewItem {
    let item = NSTabViewItem(identifier: "general")
    item.label = flowText("tab.general")
    let root = settingsPage(title: flowText("general.title"), detail: "")
    loginLaunchStatusLabel.font = .systemFont(ofSize: 11)
    configureLanguagePopup()
    languagePopup.target = self
    languagePopup.action = #selector(changeLanguage)
    languagePopup.widthAnchor.constraint(equalToConstant: 150).isActive = true
    root.addArrangedSubview(settingsGroup(reserveTitle: true, rows: [
      settingRow(title: flowText("general.loginLaunch"), detail: flowText("general.loginLaunchDetail"),
        control: controls([loginLaunchStatusLabel, loginLaunchSwitch])),
      settingRow(title: flowText("language.label"), control: languagePopup),
    ]))
    root.addArrangedSubview(settingsGroup(title: flowText("section.permissions"), rows: [
      settingRow(title: flowText("general.permissions"), detail: flowText("general.permissionsDetail"), control: generalPermissionButton),
    ]))
    root.addArrangedSubview(settingsGroup(title: flowText("section.app"), rows: [
      settingRow(title: flowText("general.remove"), detail: flowText("general.removeDetail"), control: removeAgentButton),
    ]))
    item.view = scrollableTabView(content: root)
    return item
  }

  private func keepAwakeTab() -> NSTabViewItem {
    let item = NSTabViewItem(identifier: "keep-awake")
    item.label = flowText("tab.keepAwake")
    let root = settingsPage(title: flowText("keep.title"), detail: flowText("keep.detail"))
    root.addArrangedSubview(settingsGroup(reserveTitle: true, rows: [
      settingRow(title: flowText("keep.prevent"), control: controls([keepAwakeApprovalButton, keepAwakeSwitch])),
      statusView(keepAwakeStatusLabel),
    ]))
    root.addArrangedSubview(settingsGroup(title: flowText("section.power"), rows: [
      settingRow(title: flowText("keep.powerScope"), detail: flowText("keep.powerScopeDetail"), control: keepAwakePowerScopeControl),
    ]))
    root.addArrangedSubview(settingsGroup(title: flowText("section.lid"), rows: [
      settingRow(title: flowText("keep.lockOnLid"), detail: flowText("keep.lockOnLidDetail"), control: lockOnLidCloseSwitch),
      settingRow(title: flowText("keep.sleepOnKoreanLid"), detail: flowText("keep.sleepOnKoreanLidDetail"), control: sleepOnKoreanLidCloseSwitch),
    ]))
    item.view = scrollableTabView(content: root)
    return item
  }

  private func dockPinTab() -> NSTabViewItem {
    let item = NSTabViewItem(identifier: "dock-anchor")
    item.label = flowText("tab.dockPin")
    let root = settingsPage(title: flowText("dock.title"), detail: flowText("dock.detail"))
    dockDisplayPopup.target = self
    dockDisplayPopup.action = #selector(saveRuntimeSettings)
    dockDisplayPopup.widthAnchor.constraint(equalToConstant: 260).isActive = true
    root.addArrangedSubview(settingsGroup(title: flowText("section.position"), rows: [
      settingRow(title: flowText("dock.checkbox"), detail: flowText("dock.positionDetail"), control: controls([dockPermissionButton, dockPinSwitch])),
      settingRow(title: flowText("dock.display"), control: dockDisplayPopup),
      statusView(dockPinStatusLabel),
    ]))
    root.addArrangedSubview(settingsGroup(title: flowText("section.response"), rows: [
      settingRow(title: flowText("dock.timing"), detail: flowText("dock.timingDetail"), control: dockTimingSwitch),
      statusView(dockTimingStatusLabel),
    ]))
    item.view = scrollableTabView(content: root)
    return item
  }

  private func inputDevicesTab() -> NSTabViewItem {
    let item = NSTabViewItem(identifier: "input-devices")
    item.label = flowText("tab.inputDevices")
    let root = settingsPage(title: flowText("devices.title"), detail: "")
    root.addArrangedSubview(settingsGroup(title: flowText("devices.mouse.title"), rows: [
      settingRow(title: flowText("devices.mouse.reverse"), detail: flowText("devices.mouse.reverseDetail"),
        control: controls([mousePermissionButton, mouseScrollReverseSwitch])),
      statusView(mouseScrollStatusLabel),
    ]))
    mouseDevicesStack.orientation = .vertical
    mouseDevicesStack.alignment = .width
    mouseDevicesStack.spacing = 8
    root.setCustomSpacing(8, after: root.arrangedSubviews.last!)
    root.addArrangedSubview(mouseDevicesStack)
    let heading = NSTextField(labelWithString: flowText("devices.keyboard.title"))
    heading.font = .systemFont(ofSize: 12, weight: .semibold)
    heading.textColor = .secondaryLabelColor
    heading.toolTip = flowText("devices.keyboard.detail")
    root.addArrangedSubview(heading)
    root.setCustomSpacing(8, after: heading)
    keyboardDevicesStack.orientation = .vertical
    keyboardDevicesStack.alignment = .width
    keyboardDevicesStack.spacing = 8
    root.addArrangedSubview(keyboardDevicesStack)
    item.view = scrollableTabView(content: root)
    return item
  }

  private func screenshotsTab() -> NSTabViewItem {
    let item = NSTabViewItem(identifier: "screenshots")
    item.label = flowText("tab.screenshots")
    let root = settingsPage(title: flowText("screenshots.title"), detail: flowText("screenshots.detail"))
    root.addArrangedSubview(settingsGroup(reserveTitle: true, rows: [
      settingRow(title: flowText("screenshots.copy"), detail: flowText("screenshots.copyDetail"),
        control: controls([screenshotPermissionButton, screenshotWatchSwitch])),
      statusView(screenshotStatusLabel),
    ]))
    screenshotFolderButton.widthAnchor.constraint(lessThanOrEqualToConstant: 280).isActive = true
    screenshotFolderButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
    screenshotFolderButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    root.addArrangedSubview(settingsGroup(title: flowText("section.file"), rows: [
      settingRow(title: flowText("screenshots.folder"), control: controls([
        screenshotFolderButton,
        actionButton(title: flowText("screenshots.choose"), action: #selector(chooseScreenshotDirectory)),
      ])),
    ]))
    item.view = scrollableTabView(content: root)
    return item
  }

  private func configurePreview() {
    screenshotDirectoryPath = "~/Pictures/Screenshots"
    updateScreenshotFolderButton()
    loginLaunchStatusLabel.stringValue = flowText("state.off")
    generalPermissionButton.toolTip = flowText("general.permissionsDetail")
    screenshotWatchSwitch.state = .on
    screenshotStatusLabel.stringValue = flowText("screenshots.status.active")
    screenshotStatusLabel.textColor = .systemBlue
    screenshotPermissionButton.isHidden = true
    mouseScrollStatusLabel.stringValue = flowText("devices.mouse.status.off")
    mousePermissionButton.isHidden = true
    let exampleMouse = InputDeviceDescriptor(
      id: "preview-mouse", name: "Wireless Mouse", manufacturer: "Example", transport: "Bluetooth",
      vendorID: 1, productID: 1, locationID: 0)
    let exampleKeyboard = InputDeviceDescriptor(
      id: "preview-keyboard", name: "External Keyboard", manufacturer: "Example", transport: "USB",
      vendorID: 1, productID: 2, locationID: 0)
    mouseDevicesStack.addArrangedSubview(
      MouseDeviceRowView(device: exampleMouse, previewMode: true))
    keyboardDevicesStack.addArrangedSubview(
      KeyboardDeviceRowView(device: exampleKeyboard, previewMode: true))
    dockDisplayPopup.addItem(withTitle: "Built-in Display")
    dockPermissionButton.isHidden = true
    dockPinStatusLabel.stringValue = flowText("state.off")
    dockTimingStatusLabel.stringValue = flowText("dock.timing.systemDefault")
    keepAwakeSwitch.state = .on
    keepAwakeApprovalButton.isHidden = true
    keepAwakeStatusLabel.stringValue = flowText("keep.status.active")
    keepAwakeStatusLabel.textColor = .systemBlue
    appHotkeysSwitch.state = .on
    appendRow(
      AppBinding(
        shortcut: "cmd+option+s", bundleID: "com.apple.Safari", label: "Safari", isEnabled: true))
    appendRow(
      AppBinding(
        shortcut: "cmd+option+n", bundleID: "com.apple.Notes", label: "Notes", isEnabled: true))
    configureHideAllControls()
    updateAppsHint(count: 2)
  }

  /// Paint real AppKit views with synthetic data without opening a window or
  /// constructing Flow runtime controllers, event taps or power helpers.
  func renderPreviews(to directory: URL) throws {
    guard isPreview, let window, let contentView = window.contentView else { return }
    try validatePreviewNavigation()
    guard !applyLoginSecurityButton.isEnabled, !reviewStartupLoginButton.isEnabled,
      !reviewWakeLoginButton.isEnabled, startupLoginChoice.numberOfItems == 3,
      wakeLoginChoice.numberOfItems == 6 else {
      throw NSError(domain: "FlowPreview", code: 8, userInfo: [NSLocalizedDescriptionKey:
        "Prepared login controls must not enable the production mutation driver"])
    }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let names = ["general", "shortcuts", "input-devices", "screenshots", "keep-awake", "dock", "automatic-login"]
    var layouts: [[String: Any]] = []
    for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
      window.appearance = NSAppearance(named: appearanceName)
      let style = appearanceName == .aqua ? "light" : "dark"
      for width in [860, 997] {
        window.setContentSize(NSSize(width: width, height: 580))
        var reference: [String: Double]?
        for (index, name) in names.enumerated() {
          selectPage(index)
          contentView.layoutSubtreeIfNeeded()
          contentView.displayIfNeeded()
          let nativeWidth = window.contentRect(forFrameRect: window.frame).width
          guard abs(contentView.bounds.width - CGFloat(width)) <= 0.5,
            abs(nativeWidth - CGFloat(width)) <= 0.5 else {
            throw NSError(domain: "FlowPreview", code: 6, userInfo: [NSLocalizedDescriptionKey: "Requested preview width was not applied"])
          }
          let layout = try previewPageLayout(in: contentView)
          if let reference {
            for (key, expected) in reference where abs((layout[key] ?? -1) - expected) > 0.5 {
              throw NSError(domain: "FlowPreview", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "\(name) \(style) \(width): \(key) moved from \(expected) to \(layout[key] ?? -1)"
              ])
            }
          } else {
            reference = layout
          }
          layouts.append([
            "page": name, "appearance": style, "requestedWidth": width,
            "actualWidth": contentView.bounds.width, "positions": layout,
          ])
          guard let bitmap = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds)
          else {
            throw CocoaError(.fileWriteUnknown)
          }
          contentView.cacheDisplay(in: contentView.bounds, to: bitmap)
          guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
          }
          try data.write(to: directory.appendingPathComponent("flow-\(name)-\(style)-\(width).png"))
        }
      }
    }
    let data = try JSONSerialization.data(withJSONObject: layouts, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: directory.appendingPathComponent("page-layout.json"))
  }

  private func previewPageLayout(in contentView: NSView) throws -> [String: Double] {
    guard let scrollView = settingsTabs.selectedTabViewItem?.view as? NSScrollView,
      let page = scrollView.documentView?.subviews.first as? NSStackView,
      let header = page.arrangedSubviews.first,
      let title = header.subviews.first(where: { $0.identifier?.rawValue == "settings-page-title" }),
      let detail = header.subviews.first(where: { $0.identifier?.rawValue == "settings-page-detail" }),
      page.arrangedSubviews.count > 1,
      let body = page.arrangedSubviews[1] as? NSStackView,
      let card = body.arrangedSubviews.first(where: { $0 is AdaptiveCardStackView }) else {
      throw NSError(domain: "FlowPreview", code: 4, userInfo: [NSLocalizedDescriptionKey: "Missing settings page landmarks"])
    }
    var positions: [String: Double] = [:]
    for (name, view) in [("title", title), ("description", detail), ("body", body), ("card", card)] {
      let frame = view.convert(view.bounds, to: contentView)
      let top = contentView.bounds.height - frame.maxY
      positions["\(name).x"] = frame.minX
      positions["\(name).y"] = top
      if view is NSTextField {
        positions["\(name).baseline"] = top + view.firstBaselineOffsetFromTop
      }
      guard frame.minX >= 0, frame.maxX <= contentView.bounds.width + 0.5 else {
        throw NSError(domain: "FlowPreview", code: 5, userInfo: [NSLocalizedDescriptionKey: "\(name) extends outside the settings window"])
      }
    }
    for button in tabButtons {
      let frame = button.convert(button.bounds, to: contentView)
      positions["navigation.\(button.tag).x"] = frame.minX
      positions["navigation.\(button.tag).y"] = contentView.bounds.height - frame.maxY
      guard let row = button.subviews.first(where: { $0 is NSStackView }) as? NSStackView,
        let icon = row.arrangedSubviews.first as? NSImageView else {
        throw NSError(domain: "FlowPreview", code: 7, userInfo: [NSLocalizedDescriptionKey: "Missing settings navigation icon"])
      }
      let iconFrame = icon.convert(icon.bounds, to: contentView)
      positions["navigation.\(button.tag).icon.x"] = iconFrame.midX
      positions["navigation.\(button.tag).icon.y"] = contentView.bounds.height - iconFrame.midY
    }
    return positions
  }

  /// Exercise real edit/cancel paths using only the synthetic preview model.
  private func validatePreviewNavigation() throws {
    guard isPreview, let row = rows.first else { return }
    var starts = 0
    var ends = 0
    onShortcutCaptureStart = { starts += 1 }
    onShortcutCaptureEnd = { ends += 1 }
    defer { onShortcutCaptureStart = nil; onShortcutCaptureEnd = nil }
    let original = row.binding.shortcut
    selectPage(1)
    editRow(row.editButton)
    row.shortcutField.lastCompleteShortcut = "ctrl+shift+x"
    selectPage(4)
    guard starts == 1, ends == 1, activeEditingRow == nil, !row.isEditing,
      shortcutCaptureMonitor == nil, row.binding.shortcut == original,
      row.shortcutField.lastCompleteShortcut == original,
      row.shortcutField.stringValue == displayShortcut(original) else {
      throw NSError(domain: "FlowPreview", code: 1, userInfo: [NSLocalizedDescriptionKey: "Page change did not cancel shortcut editing"])
    }
    selectPage(1)
    editHideAllShortcut()
    hideAllShortcutField.lastCompleteShortcut = "ctrl+shift+y"
    cancelShortcutEditing()
    guard starts == 2, ends == 2, !isEditingHideAll, shortcutCaptureMonitor == nil,
      hideAllBinding.shortcut.isEmpty, hideAllShortcutField.lastCompleteShortcut.isEmpty else {
      throw NSError(domain: "FlowPreview", code: 2, userInfo: [NSLocalizedDescriptionKey: "Focus change did not cancel shortcut editing"])
    }
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
    sleepOnKoreanLidCloseSwitch.state = config.sleepOnKoreanLidClose ? .on : .off
    dockPinSwitch.state = config.dockPinEnabled ? .on : .off
    populateDockDisplayPopup(selectedID: config.dockPinDisplayID)
    refreshMouseScrollUI()
    refreshScreenshotUI()
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
    row.iconView.widthAnchor.constraint(equalToConstant: 26).isActive = true
    row.iconView.heightAnchor.constraint(equalToConstant: 26).isActive = true

    let identity = NSStackView()
    identity.orientation = .vertical
    identity.alignment = .leading
    identity.spacing = 2
    identity.addArrangedSubview(row.label)
    row.label.toolTip = row.binding.bundleID
    identity.widthAnchor.constraint(greaterThanOrEqualToConstant: 92).isActive = true
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
    row.shortcutField.placeholderString = flowText("apps.capturePlaceholder")
    row.shortcutField.lineBreakMode = .byTruncatingMiddle
    row.enabledSwitch.target = self
    row.enabledSwitch.action = #selector(toggleRowEnabled(_:))
    row.enabledSwitch.setContentHuggingPriority(.required, for: .horizontal)
    row.editButton.target = self
    row.editButton.action = #selector(editRow(_:))
    row.editButton.bezelStyle = .rounded
    row.editButton.controlSize = .regular
    row.editButton.heightAnchor.constraint(equalToConstant: 32).isActive = true
    row.editButton.widthAnchor.constraint(equalToConstant: 64).isActive = true
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
    row.removeButton.widthAnchor.constraint(equalToConstant: 32).isActive = true

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
    trailingControls.widthAnchor.constraint(equalToConstant: 278).isActive = true

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
      hideAllShortcutField.stringValue = displayShortcut(hideAllBinding.shortcut)
      hideAllShortcutField.lastCompleteShortcut = hideAllBinding.shortcut
    }
    hideAllShortcutField.placeholderString = flowText(isEditingHideAll ? "apps.capturePlaceholder" : "apps.notSet")
    hideAllShortcutField.toolTip = flowText("apps.editShortcutHint")
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
    guard !isPreview else { return }
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
        row.removeButton.title = ""
        row.removeButton.image = NSImage(
          systemSymbolName: "xmark", accessibilityDescription: flowText("apps.cancel"))
        row.removeButton.imagePosition = .imageOnly
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
    let wasCapturing = shortcutCaptureMonitor != nil || activeShortcutField != nil
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
    if reloadHotkeys && wasCapturing {
      onShortcutCaptureEnd?()
    }
  }

  private func updateAppsHint(count: Int) {
    appsHintLabel.stringValue = "\(flowText("section.registeredApps")) · \(count)\(flowText("apps.countSuffix"))"
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
    screenshotFolderButton.title =
      NSString(string: screenshotDirectoryPath).abbreviatingWithTildeInPath
    screenshotFolderButton.toolTip = screenshotDirectoryPath
  }

  private func refreshScreenshotUI() {
    let status: String
    if screenshotWatchSwitch.state != .on {
      status = flowText("screenshots.status.off")
    } else if !AXIsProcessTrusted() {
      status = flowText("screenshots.status.needsPermission")
    } else {
      status = flowText(
        screenshotStatusProvider() ? "screenshots.status.active" : "screenshots.status.failed")
    }
    screenshotStatusLabel.stringValue = status
    let isActive = status == flowText("screenshots.status.active")
    let isOff = status == flowText("screenshots.status.off")
    let tint: NSColor = isActive ? .systemBlue : (isOff ? .secondaryLabelColor : .systemOrange)
    screenshotStatusLabel.textColor = tint
    screenshotStatusLabel.layer?.backgroundColor =
      tint.withAlphaComponent(isOff ? 0.08 : 0.13).cgColor
    screenshotPermissionButton.isHidden =
      status != flowText("screenshots.status.needsPermission")
  }

  @objc private func toggleScreenshotWatch() {
    let needsAccessibility = screenshotWatchSwitch.state == .on && !AXIsProcessTrusted()
    refreshScreenshotUI()
    saveRuntimeSettings()
    if needsAccessibility {
      openAccessibilitySettings()
    }
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
      tint = .systemBlue
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
    loginLaunchStatusLabel.stringValue =
      LoginLaunchManager.shared.needsUpgradeReview
      ? flowText("general.status.review") : text
    loginLaunchStatusLabel.toolTip =
      LoginLaunchManager.shared.needsUpgradeReview
      ? flowText("general.upgradeLoginHelp") : text
    loginLaunchStatusLabel.textColor = tint
    loginLaunchStatusLabel.layer?.backgroundColor = tint.withAlphaComponent(0.1).cgColor
  }

  @objc private func toggleAppHotkeys() {
    let enabled = appHotkeysSwitch.state == .on
    let needsAccessibility = enabled && !AXIsProcessTrusted()
    updateAppHotkeyControls()
    savePressed()
    if needsAccessibility {
      openAccessibilitySettings()
    }
  }

  private func updateAppHotkeyControls() {
    let masterEnabled = appHotkeysSwitch.state == .on
    let individuallyEditable = masterEnabled && activeEditingRow == nil
    for row in rows {
      row.enabledSwitch.isEnabled = individuallyEditable
    }
  }

  @objc private func toggleKeepAwake() {
    refreshKeepAwakeUI()
    saveRuntimeSettings()
  }

  @objc private func requestKeepAwakeAuthorization() {
    onKeepAwakeAuthorizationRequest?(true)
  }

  @objc private func changeKeepAwakePowerScope() {
    saveRuntimeSettings()
  }

  @objc private func toggleLockOnLidClose() {
    let needsAccessibility = lockOnLidCloseSwitch.state == .on && !AXIsProcessTrusted()
    saveRuntimeSettings()
    if needsAccessibility {
      openAccessibilitySettings()
    }
  }

  @objc private func toggleSleepOnKoreanLidClose() {
    saveRuntimeSettings()
  }

  @objc private func toggleMouseScrollReverse() {
    let needsAccessibility = mouseScrollReverseSwitch.state == .on && !AXIsProcessTrusted()
    refreshMouseScrollUI()
    saveRuntimeSettings()
    if needsAccessibility {
      openAccessibilitySettings()
    }
  }

  @objc private func toggleDockPin() {
    let needsAccessibility = dockPinSwitch.state == .on && !AXIsProcessTrusted()
    saveRuntimeSettings()
    refreshDockPinUI(status: dockPinStatusProvider())
    if needsAccessibility {
      openAccessibilitySettings()
    }
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
    openAccessibilitySystemSettings()
    refreshScreenshotUI()
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
        sleepOnKoreanLidClose: sleepOnKoreanLidCloseSwitch.state == .on,
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
        sleepOnKoreanLidClose: sleepOnKoreanLidCloseSwitch.state == .on,
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

private final class FlowSettingsBackgroundView: NSView {
  override var isOpaque: Bool { true }

  override func draw(_ dirtyRect: NSRect) {
    NSColor.windowBackgroundColor.setFill()
    dirtyRect.fill()
  }
}
