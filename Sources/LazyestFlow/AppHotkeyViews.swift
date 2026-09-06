import AppKit

class AdaptiveCardStackView: NSStackView {
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.cornerRadius = 10
    layer?.borderWidth = 0.5
    updateCardAppearance()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    updateCardAppearance()
  }

  private func updateCardAppearance() {
    guard let layer else { return }
    effectiveAppearance.performAsCurrentDrawingAppearance {
      let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
      layer.backgroundColor =
        NSColor.controlBackgroundColor
        .withAlphaComponent(isDark ? 0.35 : 0.9).cgColor
      layer.borderColor =
        NSColor.separatorColor
        .withAlphaComponent(isDark ? 0.18 : 0.10).cgColor
    }
  }
}

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
    self.editButton = NSButton(title: flowText("apps.editRow"), target: nil, action: nil)
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
    self.enabledSwitch.toolTip = flowText("apps.enabled")
    self.enabledSwitch.setAccessibilityLabel("\(binding.label) \(flowText("apps.enabled"))")
    setEditing(false)
  }

  func update(_ binding: AppBinding) {
    self.binding = binding
    self.draftShortcut = binding.shortcut
    label.stringValue = binding.label
    bundleID.stringValue = binding.bundleID
    shortcutField.stringValue = displayShortcut(binding.shortcut)
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
    editButton.title = editing ? flowText("apps.applyRow") : flowText("apps.editRow")
    if editing {
      draftShortcut = binding.shortcut
      shortcutField.lastCompleteShortcut = binding.shortcut
      shortcutField.placeholderString = flowText("apps.capturePlaceholder")
    } else {
      shortcutField.lastCompleteShortcut = binding.shortcut
      shortcutField.stringValue = displayShortcut(binding.shortcut)
      shortcutField.toolTip = binding.shortcut
      removeButton.title = ""
      removeButton.image = NSImage(
        systemSymbolName: "trash", accessibilityDescription: flowText("apps.remove"))
      removeButton.imagePosition = .imageOnly
      removeButton.contentTintColor = .systemRed
      removeButton.toolTip = flowText("apps.remove")
    }
    refreshEnabledAppearance()
  }

  func cancelEditing() {
    shortcutField.stringValue = displayShortcut(binding.shortcut)
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
    if isCapturingShortcut && stringValue.isEmpty {
      placeholderString = flowText("apps.capturePlaceholder")
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

final class SettingsNavigationButton: NSButton {
  private let navigationLabel: NSTextField
  private let navigationIcon: NSImageView

  var isSelectedTab = false {
    didSet { updateAppearance() }
  }

  init(title: String, symbolName: String) {
    navigationLabel = NSTextField(labelWithString: title)
    navigationIcon = NSImageView(
      image: NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) ?? NSImage())
    super.init(frame: .zero)
    self.title = ""
    isBordered = false
    setButtonType(.momentaryPushIn)
    wantsLayer = true
    layer?.cornerRadius = 7
    setAccessibilityLabel(title)
    navigationLabel.font = .systemFont(ofSize: 13)
    navigationLabel.lineBreakMode = .byTruncatingTail
    navigationLabel.setAccessibilityElement(false)
    navigationIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
    navigationIcon.setAccessibilityElement(false)
    navigationIcon.widthAnchor.constraint(equalToConstant: 18).isActive = true
    let content = NSStackView(views: [navigationIcon, navigationLabel])
    content.orientation = .horizontal
    content.alignment = .centerY
    content.spacing = 9
    content.translatesAutoresizingMaskIntoConstraints = false
    addSubview(content)
    NSLayoutConstraint.activate([
      content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
      content.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
      content.centerYAnchor.constraint(equalTo: centerYAnchor),
      heightAnchor.constraint(equalToConstant: 34),
    ])
    updateAppearance()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    updateAppearance()
  }

  private func updateAppearance() {
    guard let layer else { return }
    setAccessibilityValue(isSelectedTab ? 1 : 0)
    effectiveAppearance.performAsCurrentDrawingAppearance {
      let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
      layer.backgroundColor = (isSelectedTab
        ? NSColor.systemBlue.withAlphaComponent(dark ? 0.22 : 0.12) : .clear).cgColor
      navigationLabel.textColor = isSelectedTab ? .labelColor : .secondaryLabelColor
      navigationLabel.font = .systemFont(ofSize: 13, weight: isSelectedTab ? .medium : .regular)
      navigationIcon.contentTintColor = isSelectedTab ? .systemBlue : .secondaryLabelColor
    }
  }
}
