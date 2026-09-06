import AppKit
import Foundation
import LazyestCore

enum KeyboardMappingPreset: String, Codable {
  case unchanged
  case windowsToMac
  case legacyDirectF18 = "windowsToMacKorean"

  static let selectableCases: [KeyboardMappingPreset] = [.unchanged, .windowsToMac]

  var title: String {
    switch self {
    case .unchanged:
      return flowText("devices.keyboard.preset.none")
    case .windowsToMac:
      return flowText("devices.keyboard.preset.mac")
    case .legacyDirectF18:
      return flowText("devices.keyboard.preset.mac")
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
      .appendingPathComponent("Lazyest Flow", isDirectory: true)
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
  case conflictingModifierMapping

  var errorDescription: String? {
    switch self {
    case .karabinerMissing:
      return flowText("devices.keyboard.error.karabiner")
    case .configMissing:
      return flowText("devices.keyboard.error.config")
    case .verificationFailed:
      return flowText("devices.keyboard.error.verify")
    case .conflictingModifierMapping:
      return flowText("devices.keyboard.error.conflict")
    }
  }
}

private final class KarabinerKeyboardMapper {
  private let configURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".config/karabiner/karabiner.json")
  private lazy var backupURL = configURL.deletingLastPathComponent()
    .appendingPathComponent("karabiner.json.lazyest-flow-backup")

  func applyWindowsLayout(to device: InputDeviceDescriptor) throws {
    try validateKarabiner()
    let current = try Data(contentsOf: configURL)
    guard
      !KarabinerConfigEditor.isWindowsLayoutApplied(
        in: current, vendorID: device.vendorID, productID: device.productID
      )
    else { return }
    let updated: Data
    do {
      updated = try KarabinerConfigEditor.applyingWindowsLayout(
        to: current,
        vendorID: device.vendorID,
        productID: device.productID
      )
    } catch KarabinerConfigEditorError.conflictingModifierMapping {
      throw KeyboardMappingError.conflictingModifierMapping
    }
    try createBackupIfNeeded(from: current)
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
    guard FileManager.default.fileExists(atPath: configURL.path) else { return }
    let current = try Data(contentsOf: configURL)
    let updated = try KarabinerConfigEditor.resettingWindowsLayout(
      in: current,
      vendorID: device.vendorID,
      productID: device.productID
    )
    try updated.write(to: configURL, options: .atomic)
  }

  func resetAllWindowsLayouts(devices: [(vendorID: Int, productID: Int)]) throws {
    guard FileManager.default.fileExists(atPath: configURL.path) else {
      try? FileManager.default.removeItem(at: backupURL)
      return
    }
    let current = try Data(contentsOf: configURL)
    let updated = try KarabinerConfigEditor.resettingAllWindowsLayouts(
      in: current, devices: devices)
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
    guard let profile = store.profile(for: device), profile.preset != .unchanged,
      mapper.isWindowsLayoutApplied(to: device)
    else {
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
    guard let profile = store.profile(for: device), profile.preset != .unchanged else { return }
    try mapper.resetWindowsLayout(for: device)
    try store.remove(for: device)
    postChanged()
  }

  func resetAll() throws {
    try mapper.resetAllWindowsLayouts(
      devices: store.allProfiles().filter { $0.preset != .unchanged }
        .map { (vendorID: $0.vendorID, productID: $0.productID) }
    )
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
      guard profile.preset != .unchanged, let device = connected[profile.id] else { continue }
      let role = inventory.role(for: device)
      guard role != .mouse, role != .ignored else { continue }
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

final class KeyboardDeviceRowView: AdaptiveCardStackView {
  let device: InputDeviceDescriptor
  private let controller: KeyboardMappingController?
  private let presetPopup = NSPopUpButton()
  private let statusLabel = NSTextField(labelWithString: "")
  private let actionButton = NSButton()
  var onResult: ((Result<Void, Error>) -> Void)?

  init(
    device: InputDeviceDescriptor,
    controller: KeyboardMappingController? = nil,
    previewMode: Bool = false
  ) {
    self.device = device
    self.controller = previewMode ? nil : (controller ?? .shared)
    super.init(frame: .zero)
    buildUI()
    reloadState()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func buildUI() {
    orientation = .vertical
    alignment = .leading
    spacing = 8
    edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)

    let icon = NSImageView(
      image: NSImage(systemSymbolName: "keyboard", accessibilityDescription: device.name)
        ?? NSImage())
    icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 17, weight: .regular)
    icon.contentTintColor = .secondaryLabelColor
    icon.widthAnchor.constraint(equalToConstant: 24).isActive = true

    let labels = NSStackView()
    labels.orientation = .vertical
    labels.alignment = .leading
    labels.spacing = 2
    let name = NSTextField(labelWithString: device.name)
    name.font = NSFont.systemFont(ofSize: 13, weight: .medium)
    name.lineBreakMode = .byTruncatingTail
    name.maximumNumberOfLines = 1
    name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    let detailParts = [
      device.manufacturer,
      device.transport,
      String(format: "VID %04X / PID %04X", device.vendorID, device.productID),
    ].filter { !$0.isEmpty }
    name.toolTip = ([device.name] + detailParts).joined(separator: "\n")
    labels.addArrangedSubview(name)
    labels.addArrangedSubview(statusLabel)
    labels.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    let roleButton = DeviceRoleMenuButton(device: device, previewMode: controller == nil)
    roleButton.onResult = { [weak self] result in self?.onResult?(result) }
    let header = NSStackView(views: [icon, labels, NSView(), roleButton])
    header.orientation = .horizontal
    header.alignment = .centerY
    header.spacing = 8
    addArrangedSubview(header)
    header.widthAnchor.constraint(equalTo: widthAnchor, constant: -24).isActive = true

    for preset in KeyboardMappingPreset.selectableCases {
      presetPopup.addItem(withTitle: preset.title)
      presetPopup.lastItem?.representedObject = preset.rawValue
    }
    presetPopup.target = self
    presetPopup.action = #selector(selectionChanged)
    presetPopup.controlSize = .regular
    presetPopup.font = NSFont.systemFont(ofSize: 13)
    presetPopup.widthAnchor.constraint(equalToConstant: 240).isActive = true
    presetPopup.heightAnchor.constraint(equalToConstant: 32).isActive = true
    presetPopup.setAccessibilityLabel("\(device.name) \(flowText("devices.keyboard.layout"))")
    presetPopup.isEnabled = controller != nil

    statusLabel.font = NSFont.systemFont(ofSize: 11)
    statusLabel.alignment = .left
    statusLabel.lineBreakMode = .byTruncatingTail

    actionButton.target = self
    actionButton.action = #selector(performAction)
    actionButton.bezelStyle = .rounded
    actionButton.controlSize = .regular
    actionButton.font = NSFont.systemFont(ofSize: 13)
    actionButton.widthAnchor.constraint(equalToConstant: 72).isActive = true
    actionButton.heightAnchor.constraint(equalToConstant: 32).isActive = true

    let layoutLabel = NSTextField(labelWithString: flowText("devices.keyboard.layout"))
    layoutLabel.font = NSFont.systemFont(ofSize: 11)
    layoutLabel.textColor = .secondaryLabelColor
    let controls = NSStackView(views: [layoutLabel, NSView(), presetPopup, actionButton])
    controls.orientation = .horizontal
    controls.alignment = .centerY
    controls.spacing = 8
    addArrangedSubview(controls)
    controls.widthAnchor.constraint(equalTo: widthAnchor, constant: -24).isActive = true
  }

  private var selectedPreset: KeyboardMappingPreset {
    guard let rawValue = presetPopup.selectedItem?.representedObject as? String else {
      return .unchanged
    }
    return KeyboardMappingPreset(rawValue: rawValue) ?? .unchanged
  }

  private func reloadState() {
    let saved = controller?.savedPreset(for: device)
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
    refreshControls(saved: controller?.savedPreset(for: device))
  }

  private func refreshControls(saved: KeyboardMappingPreset?) {
    let selected = selectedPreset
    if let saved {
      statusLabel.stringValue = flowText("devices.keyboard.status.applied")
      statusLabel.textColor = .systemBlue
      actionButton.title =
        selected == .unchanged || selected == saved
        ? flowText("devices.keyboard.reset")
        : flowText("devices.keyboard.apply")
      actionButton.isEnabled = true
    } else {
      statusLabel.stringValue = flowText("devices.keyboard.status.none")
      statusLabel.textColor = .secondaryLabelColor
      actionButton.title = flowText("devices.keyboard.apply")
      actionButton.isEnabled = controller != nil && selected != .unchanged
    }
  }

  @objc private func performAction() {
    guard let controller else { return }
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
      statusLabel.stringValue = flowText("status.failed")
      statusLabel.textColor = .systemRed
      onResult?(.failure(error))
    }
  }
}
