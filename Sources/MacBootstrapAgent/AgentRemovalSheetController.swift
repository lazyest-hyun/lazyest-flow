import AppKit

final class AgentRemovalSheetController: NSWindowController {
  private let resetSettingsSwitch = NSSwitch()
  private let resetDockTimingSwitch = NSSwitch()
  private let resetScreenshotLocationSwitch = NSSwitch()
  private let resetKeyboardMappingsSwitch = NSSwitch()
  private var completion: ((AgentRemovalOptions?) -> Void)?

  init() {
    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 540, height: 500),
      styleMask: [.titled],
      backing: .buffered,
      defer: false
    )
    panel.title = agentText("general.remove")
    panel.titleVisibility = .hidden
    panel.titlebarAppearsTransparent = true
    panel.isMovable = false
    panel.isReleasedWhenClosed = false
    super.init(window: panel)
    configureContent(in: panel)
  }

  required init?(coder: NSCoder) {
    nil
  }

  func present(from parent: NSWindow, completion: @escaping (AgentRemovalOptions?) -> Void) {
    self.completion = completion
    parent.beginSheet(window!)
  }

  private func configureContent(in panel: NSPanel) {
    let content = NSView()
    panel.contentView = content

    let root = NSStackView()
    root.translatesAutoresizingMaskIntoConstraints = false
    root.orientation = .vertical
    root.alignment = .width
    root.spacing = 16
    content.addSubview(root)
    NSLayoutConstraint.activate([
      root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
      root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
      root.topAnchor.constraint(equalTo: content.topAnchor, constant: 22),
      root.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
    ])

    root.addArrangedSubview(header())
    root.addArrangedSubview(separator())
    root.addArrangedSubview(
      sectionHeader(
        title: agentText("general.removeSheet.alwaysTitle"),
        detail: agentText("general.removeSheet.alwaysDetail")
      ))
    root.addArrangedSubview(separator())
    root.addArrangedSubview(
      sectionHeader(
        title: agentText("general.removeSheet.resetTitle"),
        detail: agentText("general.removeSheet.resetDetail")
      ))
    root.addArrangedSubview(resetChoices())
    root.addArrangedSubview(separator())
    root.addArrangedSubview(footer())
  }

  private func header() -> NSStackView {
    let row = NSStackView()
    row.orientation = .horizontal
    row.alignment = .top
    row.spacing = 12

    let icon = NSImageView()
    icon.image = NSImage(
      systemSymbolName: "trash.circle.fill", accessibilityDescription: agentText("general.remove"))
    icon.contentTintColor = .systemRed
    icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 30, weight: .medium)
    icon.widthAnchor.constraint(equalToConstant: 34).isActive = true
    icon.heightAnchor.constraint(equalToConstant: 34).isActive = true
    row.addArrangedSubview(icon)

    let labels = NSStackView()
    labels.orientation = .vertical
    labels.alignment = .leading
    labels.spacing = 3
    let title = NSTextField(labelWithString: agentText("general.removeSheet.title"))
    title.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
    let detail = NSTextField(wrappingLabelWithString: agentText("general.removeSheet.detail"))
    detail.font = NSFont.systemFont(ofSize: 12)
    detail.textColor = .secondaryLabelColor
    labels.addArrangedSubview(title)
    labels.addArrangedSubview(detail)
    labels.setContentHuggingPriority(.defaultLow, for: .horizontal)
    row.addArrangedSubview(labels)
    row.addArrangedSubview(NSView())
    return row
  }

  private func resetChoices() -> NSStackView {
    let choices = NSStackView()
    choices.orientation = .vertical
    choices.alignment = .width
    choices.spacing = 0
    choices.addArrangedSubview(
      resetRow(
        title: agentText("general.remove.settings"),
        detail: agentText("general.remove.settingsDetail"),
        toggle: resetSettingsSwitch
      ))
    choices.addArrangedSubview(separator())
    choices.addArrangedSubview(
      resetRow(
        title: agentText("general.remove.dock"),
        detail: agentText("general.remove.dockDetail"),
        toggle: resetDockTimingSwitch
      ))
    choices.addArrangedSubview(separator())
    choices.addArrangedSubview(
      resetRow(
        title: agentText("general.remove.screenshot"),
        detail: agentText("general.remove.screenshotDetail"),
        toggle: resetScreenshotLocationSwitch
      ))
    choices.addArrangedSubview(separator())
    choices.addArrangedSubview(
      resetRow(
        title: agentText("general.remove.keyboard"),
        detail: agentText("general.remove.keyboardDetail"),
        toggle: resetKeyboardMappingsSwitch
      ))
    return choices
  }

  private func sectionHeader(title: String, detail: String) -> NSStackView {
    let row = NSStackView()
    row.orientation = .horizontal
    row.alignment = .top
    row.spacing = 8
    let labels = NSStackView()
    labels.orientation = .vertical
    labels.alignment = .leading
    labels.spacing = 3
    let titleLabel = NSTextField(labelWithString: title)
    titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
    titleLabel.alignment = .left
    let detailLabel = NSTextField(wrappingLabelWithString: detail)
    detailLabel.font = NSFont.systemFont(ofSize: 12)
    detailLabel.textColor = .secondaryLabelColor
    detailLabel.alignment = .left
    labels.addArrangedSubview(titleLabel)
    labels.addArrangedSubview(detailLabel)
    labels.setContentHuggingPriority(.defaultLow, for: .horizontal)
    row.addArrangedSubview(labels)
    row.addArrangedSubview(NSView())
    return row
  }

  private func resetRow(title: String, detail: String, toggle: NSSwitch) -> NSStackView {
    toggle.state = .on
    toggle.setContentHuggingPriority(.required, for: .horizontal)
    let row = NSStackView()
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 12
    row.edgeInsets = NSEdgeInsets(top: 7, left: 0, bottom: 7, right: 0)
    let labels = NSStackView()
    labels.orientation = .vertical
    labels.alignment = .leading
    labels.spacing = 2
    let titleLabel = NSTextField(labelWithString: title)
    titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
    let detailLabel = NSTextField(wrappingLabelWithString: detail)
    detailLabel.font = NSFont.systemFont(ofSize: 11)
    detailLabel.textColor = .secondaryLabelColor
    labels.addArrangedSubview(titleLabel)
    labels.addArrangedSubview(detailLabel)
    row.addArrangedSubview(labels)
    row.addArrangedSubview(NSView())
    row.addArrangedSubview(toggle)
    return row
  }

  private func footer() -> NSStackView {
    let row = NSStackView()
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 8
    let note = NSTextField(
      wrappingLabelWithString: agentText("general.removeSheet.accessibilityNote"))
    note.font = NSFont.systemFont(ofSize: 11)
    note.textColor = .tertiaryLabelColor
    note.setContentHuggingPriority(.defaultLow, for: .horizontal)
    row.addArrangedSubview(note)
    row.addArrangedSubview(NSView())

    let cancel = NSButton(title: agentText("apps.cancel"), target: self, action: #selector(cancel))
    cancel.bezelStyle = .rounded
    cancel.keyEquivalent = "\u{1b}"
    cancel.widthAnchor.constraint(equalToConstant: 76).isActive = true
    row.addArrangedSubview(cancel)

    let remove = NSButton(
      title: agentText("general.removeConfirm"), target: self, action: #selector(confirm))
    remove.bezelStyle = .rounded
    remove.contentTintColor = .systemRed
    remove.widthAnchor.constraint(equalToConstant: 92).isActive = true
    row.addArrangedSubview(remove)
    return row
  }

  private func separator() -> NSBox {
    let box = NSBox()
    box.boxType = .separator
    return box
  }

  @objc private func cancel() {
    finish(with: nil)
  }

  @objc private func confirm() {
    finish(
      with: AgentRemovalOptions(
        removeSettings: resetSettingsSwitch.state == .on,
        resetDockTiming: resetDockTimingSwitch.state == .on,
        resetScreenshotLocation: resetScreenshotLocationSwitch.state == .on,
        resetKeyboardMappings: resetKeyboardMappingsSwitch.state == .on
      ))
  }

  private func finish(with options: AgentRemovalOptions?) {
    guard let sheet = window, let parent = sheet.sheetParent else { return }
    let completion = self.completion
    self.completion = nil
    parent.endSheet(sheet)
    completion?(options)
  }
}
