import AppKit

final class BindingRow {
  var binding: AppBinding
  var draftShortcut = ""
  let iconView: NSImageView
  let label: NSTextField
  let bundleID: NSTextField
  let shortcutField: ShortcutCaptureField
  let enabledSwitch: NSSwitch
  let editButton: NSButton
  let removeButton: NSButton
  var isEditing = false

  init(binding: AppBinding) {
    self.binding = binding
    self.draftShortcut = binding.shortcut
    self.iconView = NSImageView()
    self.label = NSTextField(labelWithString: binding.label)
    self.bundleID = NSTextField(labelWithString: binding.bundleID)
    self.shortcutField = ShortcutCaptureField(string: binding.shortcut)
    self.shortcutField.lastCompleteShortcut = binding.shortcut
    self.enabledSwitch = NSSwitch(frame: .zero)
    self.editButton = NSButton(title: agentText("apps.editRow"), target: nil, action: nil)
    self.removeButton = NSButton(title: "", target: nil, action: nil)
    if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: binding.bundleID) {
      self.iconView.image = NSWorkspace.shared.icon(forFile: appURL.path)
    } else {
      self.iconView.image = NSImage(
        systemSymbolName: "app", accessibilityDescription: binding.label)
    }
    self.iconView.imageScaling = .scaleProportionallyUpOrDown
    self.iconView.setContentHuggingPriority(.required, for: .horizontal)
    self.label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
    self.label.lineBreakMode = .byTruncatingTail
    self.bundleID.font = NSFont.systemFont(ofSize: 11)
    self.bundleID.textColor = .secondaryLabelColor
    self.bundleID.lineBreakMode = .byTruncatingHead
    self.enabledSwitch.state = binding.isEnabled ? .on : .off
    self.enabledSwitch.toolTip = agentText("apps.enabled")
    self.enabledSwitch.setAccessibilityLabel("\(binding.label) \(agentText("apps.enabled"))")
    setEditing(false)
  }

  func update(_ binding: AppBinding) {
    self.binding = binding
    self.draftShortcut = binding.shortcut
    label.stringValue = binding.label
    bundleID.stringValue = binding.bundleID
    shortcutField.stringValue = binding.shortcut
    shortcutField.lastCompleteShortcut = binding.shortcut
    enabledSwitch.state = binding.isEnabled ? .on : .off
    refreshEnabledAppearance()
  }

  func setEditing(_ editing: Bool) {
    isEditing = editing
    shortcutField.isEditable = false
    shortcutField.isSelectable = false
    shortcutField.isBordered = editing
    shortcutField.drawsBackground = editing
    shortcutField.backgroundColor = editing ? .textBackgroundColor : .clear
    editButton.title = editing ? agentText("apps.applyRow") : agentText("apps.editRow")
    if editing {
      draftShortcut = binding.shortcut
      shortcutField.lastCompleteShortcut = binding.shortcut
      shortcutField.placeholderString = agentText("apps.editShortcutHint")
    } else {
      removeButton.title = ""
      removeButton.image = NSImage(
        systemSymbolName: "trash", accessibilityDescription: agentText("apps.remove"))
      removeButton.imagePosition = .imageOnly
      removeButton.contentTintColor = .systemRed
      removeButton.toolTip = agentText("apps.remove")
    }
    refreshEnabledAppearance()
  }

  func cancelEditing() {
    shortcutField.stringValue = binding.shortcut
    shortcutField.lastCompleteShortcut = binding.shortcut
    setEditing(false)
  }

  func refreshEnabledAppearance() {
    let enabled = enabledSwitch.state == .on
    iconView.alphaValue = enabled ? 1 : 0.5
    label.textColor = enabled ? .labelColor : .secondaryLabelColor
    bundleID.textColor = enabled ? .secondaryLabelColor : .tertiaryLabelColor
    shortcutField.textColor = enabled ? .labelColor : .tertiaryLabelColor
  }
}

final class FlippedDocumentView: NSView {
  override var isFlipped: Bool { true }
}

final class ShortcutCaptureField: NSTextField {
  var onShortcutCaptured: ((String) -> Void)?
  var onCancelCapture: (() -> Void)?
  var onFocus: (() -> Void)?
  var lastCompleteShortcut = ""
  var isCapturingShortcut = false
  var hasCapturedCompleteShortcut = false

  override var acceptsFirstResponder: Bool { true }
  override var needsPanelToBecomeKey: Bool { true }

  override func becomeFirstResponder() -> Bool {
    if stringValue.isEmpty {
      placeholderString = agentText("apps.editShortcutHint")
    }
    onFocus?()
    return true
  }

  override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(self)
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    guard isCapturingShortcut else { return false }
    return capture(event)
  }

  override func keyDown(with event: NSEvent) {
    guard isCapturingShortcut else {
      super.keyDown(with: event)
      return
    }
    _ = capture(event)
  }

  override func flagsChanged(with event: NSEvent) {
    guard isCapturingShortcut else {
      super.flagsChanged(with: event)
      return
    }
    guard !hasCapturedCompleteShortcut,
      let modifiers = modifierString(from: event), !modifiers.isEmpty
    else {
      return
    }
    stringValue = modifiers
    needsDisplay = true
  }

  @discardableResult
  private func capture(_ event: NSEvent) -> Bool {
    if event.keyCode == 53 {
      onCancelCapture?()
      return true
    }
    guard let shortcut = shortcutString(from: event) else {
      return true
    }
    stringValue = shortcut
    lastCompleteShortcut = shortcut
    hasCapturedCompleteShortcut = true
    needsDisplay = true
    onShortcutCaptured?(shortcut)
    return true
  }
}

final class SettingsTabButton: NSButton {
  private let tabLabel: NSTextField
  private let tabIcon: NSImageView

  var isSelectedTab = false {
    didSet { updateAppearance() }
  }

  init(title: String, symbolName: String) {
    tabLabel = NSTextField(labelWithString: title)
    tabIcon = NSImageView(
      image: NSImage(systemSymbolName: symbolName, accessibilityDescription: title) ?? NSImage())
    super.init(frame: .zero)

    self.title = ""
    isBordered = false
    setButtonType(.momentaryPushIn)
    wantsLayer = true
    layer?.cornerRadius = 6
    setAccessibilityLabel(title)

    tabLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
    tabLabel.alignment = .center
    tabLabel.lineBreakMode = .byTruncatingTail
    tabIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
    tabIcon.setContentHuggingPriority(.required, for: .horizontal)

    let content = NSStackView(views: [tabIcon, tabLabel])
    content.orientation = .horizontal
    content.alignment = .centerY
    content.spacing = 7
    content.translatesAutoresizingMaskIntoConstraints = false
    addSubview(content)
    NSLayoutConstraint.activate([
      content.centerXAnchor.constraint(equalTo: centerXAnchor),
      content.centerYAnchor.constraint(equalTo: centerYAnchor),
      content.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 8),
      content.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
      heightAnchor.constraint(equalToConstant: 32),
    ])
    updateAppearance()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func updateLayer() {
    super.updateLayer()
    updateAppearance()
  }

  private func updateAppearance() {
    guard let layer else { return }
    layer.backgroundColor =
      (isSelectedTab
      ? NSColor.controlAccentColor.withAlphaComponent(0.2)
      : NSColor.controlBackgroundColor.withAlphaComponent(0.55)).cgColor
    layer.borderWidth = 1
    layer.borderColor =
      (isSelectedTab
      ? NSColor.controlAccentColor.withAlphaComponent(0.45)
      : NSColor.separatorColor.withAlphaComponent(0.4)).cgColor
    tabLabel.textColor = isSelectedTab ? .labelColor : .secondaryLabelColor
    tabIcon.contentTintColor = isSelectedTab ? .controlAccentColor : .secondaryLabelColor
  }
}
