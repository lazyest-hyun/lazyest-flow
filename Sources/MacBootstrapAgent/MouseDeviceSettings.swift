import AppKit
import Foundation

enum MouseDeviceMode: String, Codable, CaseIterable {
  case inherit
  case reversed
  case system

  var title: String {
    switch self {
    case .inherit:
      return agentText("devices.mouse.mode.inherit")
    case .reversed:
      return agentText("devices.mouse.mode.reversed")
    case .system:
      return agentText("devices.mouse.mode.system")
    }
  }
}

private struct MouseDeviceProfile: Codable {
  let id: String
  let vendorID: Int
  let productID: Int
  let name: String
  let mode: MouseDeviceMode
}

final class MouseDevicePreferences {
  static let shared = MouseDevicePreferences()
  private let url: URL
  private var profiles: [MouseDeviceProfile]
  private var modesByID: [String: MouseDeviceMode]
  private var reversedOverrideCount: Int

  private init() {
    let directory = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("MacBootstrapAgent", isDirectory: true)
    let profileURL = directory.appendingPathComponent("mouse-devices.json")
    url = profileURL
    if let data = try? Data(contentsOf: profileURL),
      let savedProfiles = try? JSONDecoder().decode([MouseDeviceProfile].self, from: data)
    {
      profiles = savedProfiles
    } else {
      profiles = []
    }
    modesByID = Dictionary(
      profiles.map { ($0.id, $0.mode) },
      uniquingKeysWith: { _, latest in latest }
    )
    reversedOverrideCount = profiles.lazy.filter { $0.mode == .reversed }.count
  }

  func mode(for device: InputDeviceDescriptor) -> MouseDeviceMode {
    modesByID[device.mappingID] ?? .inherit
  }

  func setMode(_ mode: MouseDeviceMode, for device: InputDeviceDescriptor) throws {
    var updatedProfiles = profiles.filter { $0.id != device.mappingID }
    if mode != .inherit {
      updatedProfiles.append(
        MouseDeviceProfile(
          id: device.mappingID,
          vendorID: device.vendorID,
          productID: device.productID,
          name: device.name,
          mode: mode
        ))
    }
    try write(updatedProfiles)
    profiles = updatedProfiles
    if mode == .inherit {
      modesByID.removeValue(forKey: device.mappingID)
    } else {
      modesByID[device.mappingID] = mode
    }
    reversedOverrideCount = updatedProfiles.lazy.filter { $0.mode == .reversed }.count
  }

  func shouldReverse(deviceID: String?, defaultValue: Bool) -> Bool {
    guard let deviceID, let mode = modesByID[deviceID] else {
      return defaultValue
    }
    switch mode {
    case .inherit:
      return defaultValue
    case .reversed:
      return true
    case .system:
      return false
    }
  }

  var hasReversedOverride: Bool {
    reversedOverrideCount > 0
  }

  private func write(_ profiles: [MouseDeviceProfile]) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let data = try JSONEncoder().encode(profiles)
    try data.write(to: url, options: .atomic)
  }
}

final class MouseDeviceRowView: NSStackView {
  private let device: InputDeviceDescriptor
  private let preferences: MouseDevicePreferences
  private let modePopup = NSPopUpButton()
  var onResult: ((Result<Void, Error>) -> Void)?

  init(device: InputDeviceDescriptor, preferences: MouseDevicePreferences = .shared) {
    self.device = device
    self.preferences = preferences
    super.init(frame: .zero)
    buildUI()
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
      image: NSImage(systemSymbolName: "computermouse", accessibilityDescription: device.name)
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
    addArrangedSubview(labels)
    addArrangedSubview(NSView())

    for mode in MouseDeviceMode.allCases {
      modePopup.addItem(withTitle: mode.title)
      modePopup.lastItem?.representedObject = mode.rawValue
    }
    let savedMode = preferences.mode(for: device)
    if let index = modePopup.itemArray.firstIndex(where: {
      ($0.representedObject as? String) == savedMode.rawValue
    }) {
      modePopup.selectItem(at: index)
    }
    modePopup.target = self
    modePopup.action = #selector(changeMouseMode)
    modePopup.widthAnchor.constraint(equalToConstant: 190).isActive = true
    addArrangedSubview(modePopup)
  }

  @objc private func changeMouseMode() {
    guard let rawValue = modePopup.selectedItem?.representedObject as? String,
      let mode = MouseDeviceMode(rawValue: rawValue)
    else { return }
    do {
      try preferences.setMode(mode, for: device)
      onResult?(.success(()))
    } catch {
      onResult?(.failure(error))
    }
  }
}

final class UnclassifiedDeviceRowView: NSStackView {
  private let device: InputDeviceDescriptor
  private let rolePopup = NSPopUpButton()
  var onResult: ((Result<Void, Error>) -> Void)?

  init(device: InputDeviceDescriptor) {
    self.device = device
    super.init(frame: .zero)
    buildUI()
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
    layer?.borderColor = NSColor.systemOrange.withAlphaComponent(0.35).cgColor

    let icon = NSImageView(
      image: NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: device.name)
        ?? NSImage())
    icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 17, weight: .regular)
    icon.contentTintColor = .systemOrange
    icon.widthAnchor.constraint(equalToConstant: 26).isActive = true
    addArrangedSubview(icon)

    let labels = NSStackView()
    labels.orientation = .vertical
    labels.alignment = .leading
    labels.spacing = 2
    let name = NSTextField(labelWithString: device.name)
    name.font = NSFont.systemFont(ofSize: 13, weight: .medium)
    let detail = NSTextField(
      labelWithString: String(
        format: "%@ · VID %04X · PID %04X",
        device.manufacturer,
        device.vendorID,
        device.productID
      ))
    detail.textColor = .secondaryLabelColor
    detail.font = NSFont.systemFont(ofSize: 10)
    labels.addArrangedSubview(name)
    labels.addArrangedSubview(detail)
    addArrangedSubview(labels)
    addArrangedSubview(NSView())

    for role in InputDeviceRole.allCases where role != .ignored {
      rolePopup.addItem(withTitle: role.title)
      rolePopup.lastItem?.representedObject = role.rawValue
    }
    rolePopup.target = self
    rolePopup.action = #selector(assignSelectedRole)
    rolePopup.widthAnchor.constraint(equalToConstant: 170).isActive = true
    addArrangedSubview(rolePopup)
  }

  @objc private func assignSelectedRole() {
    guard let rawValue = rolePopup.selectedItem?.representedObject as? String,
      let role = InputDeviceRole(rawValue: rawValue),
      role != .unknown
    else { return }
    do {
      try InputDeviceInventory.shared.assignRole(role, to: device)
      onResult?(.success(()))
    } catch {
      onResult?(.failure(error))
    }
  }
}
