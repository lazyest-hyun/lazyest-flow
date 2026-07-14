import AppKit
import Foundation
import MacBootstrapCore

enum KeyboardMappingPreset: String, Codable {
  case unchanged
  case windowsToMac
  case legacyDirectF18 = "windowsToMacKorean"

  static let selectableCases: [KeyboardMappingPreset] = [.unchanged, .windowsToMac]

  var title: String {
    switch self {
    case .unchanged:
      return agentText("devices.keyboard.preset.none")
    case .windowsToMac:
      return agentText("devices.keyboard.preset.mac")
    case .legacyDirectF18:
      return agentText("devices.keyboard.preset.mac")
    }
  }
}

private struct KeyboardDeviceProfile: Codable {
  let id: String
  let vendorID: Int
  let productID: Int
  let name: String
  let preset: KeyboardMappingPreset
}

private final class KeyboardProfileStore {
  private let url: URL

  init() {
    let directory = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("MacBootstrapAgent", isDirectory: true)
    url = directory.appendingPathComponent("input-devices.json")
  }

  func profile(for device: InputDeviceDescriptor) -> KeyboardDeviceProfile? {
    load().first { $0.id == device.mappingID }
  }

  func save(_ preset: KeyboardMappingPreset, for device: InputDeviceDescriptor) throws {
    var profiles = load().filter { $0.id != device.mappingID }
    profiles.append(
      KeyboardDeviceProfile(
        id: device.mappingID,
        vendorID: device.vendorID,
        productID: device.productID,
        name: device.name,
        preset: preset
      ))
    try write(profiles)
  }

  func remove(for device: InputDeviceDescriptor) throws {
    try write(load().filter { $0.id != device.mappingID })
  }

  func clear() throws {
    try write([])
  }

  func allProfiles() -> [KeyboardDeviceProfile] {
    load()
  }

  private func load() -> [KeyboardDeviceProfile] {
    guard let data = try? Data(contentsOf: url),
      let profiles = try? JSONDecoder().decode([KeyboardDeviceProfile].self, from: data)
    else {
      return []
    }
    return profiles
  }

  private func write(_ profiles: [KeyboardDeviceProfile]) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let data = try JSONEncoder().encode(profiles)
    try data.write(to: url, options: .atomic)
  }
}

enum KeyboardMappingError: LocalizedError {
  case karabinerMissing
  case configMissing
  case verificationFailed

  var errorDescription: String? {
    switch self {
    case .karabinerMissing:
      return agentText("devices.keyboard.error.karabiner")
    case .configMissing:
      return agentText("devices.keyboard.error.config")
    case .verificationFailed:
      return agentText("devices.keyboard.error.verify")
    }
  }
}

private final class KarabinerKeyboardMapper {
  private let configURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".config/karabiner/karabiner.json")
  private lazy var backupURL = configURL.deletingLastPathComponent()
    .appendingPathComponent("karabiner.json.macbootstrap-backup")

  func applyWindowsLayout(to device: InputDeviceDescriptor) throws {
    try validateKarabiner()
    let current = try Data(contentsOf: configURL)
    try createBackupIfNeeded(from: current)
    let updated = try KarabinerConfigEditor.applyingWindowsLayout(
      to: current,
      vendorID: device.vendorID,
      productID: device.productID
    )
    try updated.write(to: configURL, options: .atomic)
    let written = try Data(contentsOf: configURL)
    guard
      KarabinerConfigEditor.isWindowsLayoutApplied(
        in: written,
        vendorID: device.vendorID,
        productID: device.productID
      )
    else {
      throw KeyboardMappingError.verificationFailed
    }
  }

  func resetWindowsLayout(for device: InputDeviceDescriptor) throws {
    try validateKarabiner()
    let current = try Data(contentsOf: configURL)
    let updated = try KarabinerConfigEditor.resettingWindowsLayout(
      in: current,
      vendorID: device.vendorID,
      productID: device.productID
    )
    try updated.write(to: configURL, options: .atomic)
  }

  func resetAllWindowsLayouts() throws {
    guard FileManager.default.fileExists(atPath: configURL.path) else {
      try? FileManager.default.removeItem(at: backupURL)
      return
    }
    let current = try Data(contentsOf: configURL)
    let updated = try KarabinerConfigEditor.resettingAllWindowsLayouts(in: current)
    try updated.write(to: configURL, options: .atomic)
    try? FileManager.default.removeItem(at: backupURL)
  }

  func isWindowsLayoutApplied(to device: InputDeviceDescriptor) -> Bool {
    guard let data = try? Data(contentsOf: configURL) else { return false }
    return KarabinerConfigEditor.isWindowsLayoutApplied(
      in: data,
      vendorID: device.vendorID,
      productID: device.productID
    )
  }

  private func validateKarabiner() throws {
    guard FileManager.default.fileExists(atPath: "/Applications/Karabiner-Elements.app") else {
      throw KeyboardMappingError.karabinerMissing
    }
    guard FileManager.default.fileExists(atPath: configURL.path) else {
      throw KeyboardMappingError.configMissing
    }
  }

  private func createBackupIfNeeded(from data: Data) throws {
    guard !FileManager.default.fileExists(atPath: backupURL.path) else { return }
    try data.write(to: backupURL, options: .atomic)
  }
}

final class KeyboardMappingController {
  static let shared = KeyboardMappingController()
  private let store = KeyboardProfileStore()
  private let mapper = KarabinerKeyboardMapper()

  func savedPreset(for device: InputDeviceDescriptor) -> KeyboardMappingPreset? {
    guard store.profile(for: device) != nil, mapper.isWindowsLayoutApplied(to: device) else {
      return nil
    }
    return .windowsToMac
  }

  func apply(_ preset: KeyboardMappingPreset, to device: InputDeviceDescriptor) throws {
    guard preset != .unchanged else {
      try reset(device)
      return
    }
    try mapper.applyWindowsLayout(to: device)
    try store.save(.windowsToMac, for: device)
    postChanged()
  }

  func reset(_ device: InputDeviceDescriptor) throws {
    try mapper.resetWindowsLayout(for: device)
    try store.remove(for: device)
    postChanged()
  }

  func resetAll() throws {
    try mapper.resetAllWindowsLayouts()
    try store.clear()
    postChanged()
  }

  func reapplySavedProfiles() {
    let inventory = InputDeviceInventory.shared
    let connected = Dictionary(
      inventory.keyboardCandidates().map { ($0.mappingID, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    for profile in store.allProfiles() {
      guard let device = connected[profile.id] else { continue }
      inventory.confirmKeyboard(device)
      do {
        try mapper.applyWindowsLayout(to: device)
        if profile.preset != .windowsToMac {
          try store.save(.windowsToMac, for: device)
        }
      } catch {
        NSLog(
          "Failed to reapply keyboard mapping for %@: %@", profile.name, error.localizedDescription)
      }
    }
  }

  private func postChanged() {
    NotificationCenter.default.post(name: keyboardMappingDidChangeNotification, object: nil)
  }
}

final class KeyboardDeviceRowView: NSStackView {
  let device: InputDeviceDescriptor
  private let controller: KeyboardMappingController
  private let presetPopup = NSPopUpButton()
  private let statusLabel = NSTextField(labelWithString: "")
  private let actionButton = NSButton()
  var onResult: ((Result<Void, Error>) -> Void)?

  init(device: InputDeviceDescriptor, controller: KeyboardMappingController = .shared) {
    self.device = device
    self.controller = controller
    super.init(frame: .zero)
    buildUI()
    reloadState()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func buildUI() {
    orientation = .horizontal
    alignment = .centerY
    spacing = 10
    edgeInsets = NSEdgeInsets(top: 7, left: 10, bottom: 7, right: 10)
    wantsLayer = true
    layer?.cornerRadius = 8
    layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.35).cgColor
    layer?.borderWidth = 1
    layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.28).cgColor

    let icon = NSImageView(
      image: NSImage(systemSymbolName: "keyboard", accessibilityDescription: device.name)
        ?? NSImage())
    icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 17, weight: .regular)
    icon.contentTintColor = .secondaryLabelColor
    icon.widthAnchor.constraint(equalToConstant: 26).isActive = true
    addArrangedSubview(icon)

    let labels = NSStackView()
    labels.orientation = .vertical
    labels.alignment = .leading
    labels.spacing = 2
    let name = NSTextField(labelWithString: device.name)
    name.font = NSFont.systemFont(ofSize: 13, weight: .medium)
    name.lineBreakMode = .byTruncatingTail
    let detailParts = [
      device.manufacturer,
      device.transport,
      String(format: "VID %04X · PID %04X", device.vendorID, device.productID),
    ].filter { !$0.isEmpty }
    let detail = NSTextField(labelWithString: detailParts.joined(separator: " · "))
    detail.textColor = .secondaryLabelColor
    detail.font = NSFont.systemFont(ofSize: 10)
    labels.addArrangedSubview(name)
    labels.addArrangedSubview(detail)
    labels.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
    addArrangedSubview(labels)
    addArrangedSubview(NSView())

    for preset in KeyboardMappingPreset.selectableCases {
      presetPopup.addItem(withTitle: preset.title)
      presetPopup.lastItem?.representedObject = preset.rawValue
    }
    presetPopup.target = self
    presetPopup.action = #selector(selectionChanged)
    presetPopup.widthAnchor.constraint(equalToConstant: 220).isActive = true
    addArrangedSubview(presetPopup)

    statusLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
    statusLabel.alignment = .center
    statusLabel.widthAnchor.constraint(equalToConstant: 66).isActive = true
    addArrangedSubview(statusLabel)

    actionButton.target = self
    actionButton.action = #selector(performAction)
    actionButton.bezelStyle = .rounded
    actionButton.widthAnchor.constraint(equalToConstant: 72).isActive = true
    actionButton.heightAnchor.constraint(equalToConstant: 30).isActive = true
    addArrangedSubview(actionButton)
  }

  private var selectedPreset: KeyboardMappingPreset {
    guard let rawValue = presetPopup.selectedItem?.representedObject as? String else {
      return .unchanged
    }
    return KeyboardMappingPreset(rawValue: rawValue) ?? .unchanged
  }

  private func reloadState() {
    let saved = controller.savedPreset(for: device)
    select(saved ?? .unchanged)
    refreshControls(saved: saved)
  }

  private func select(_ preset: KeyboardMappingPreset) {
    if let index = presetPopup.itemArray.firstIndex(where: {
      ($0.representedObject as? String) == preset.rawValue
    }) {
      presetPopup.selectItem(at: index)
    }
  }

  @objc private func selectionChanged() {
    refreshControls(saved: controller.savedPreset(for: device))
  }

  private func refreshControls(saved: KeyboardMappingPreset?) {
    let selected = selectedPreset
    if let saved {
      statusLabel.stringValue = agentText("devices.keyboard.status.applied")
      statusLabel.textColor = .systemGreen
      actionButton.title =
        selected == .unchanged || selected == saved
        ? agentText("devices.keyboard.reset")
        : agentText("devices.keyboard.apply")
      actionButton.isEnabled = true
    } else {
      statusLabel.stringValue = agentText("devices.keyboard.status.none")
      statusLabel.textColor = .secondaryLabelColor
      actionButton.title = agentText("devices.keyboard.apply")
      actionButton.isEnabled = selected != .unchanged
    }
  }

  @objc private func performAction() {
    let saved = controller.savedPreset(for: device)
    let selected = selectedPreset
    do {
      if selected == .unchanged || selected == saved {
        try controller.reset(device)
        select(.unchanged)
      } else {
        try controller.apply(selected, to: device)
      }
      refreshControls(saved: controller.savedPreset(for: device))
      onResult?(.success(()))
    } catch {
      statusLabel.stringValue = agentText("status.failed")
      statusLabel.textColor = .systemRed
      onResult?(.failure(error))
    }
  }
}
