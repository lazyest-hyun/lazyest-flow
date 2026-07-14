import Foundation
import IOKit.hid
import MacBootstrapCore

let mouseScrollStatusNotification = Notification.Name("MacBootstrapMouseScrollStatusChanged")
let inputDeviceInventoryDidChangeNotification = Notification.Name(
  "MacBootstrapInputDeviceInventoryDidChange")
let keyboardMappingDidChangeNotification = Notification.Name("MacBootstrapKeyboardMappingDidChange")

struct InputDeviceDescriptor: Hashable {
  let id: String
  let name: String
  let manufacturer: String
  let transport: String
  let vendorID: Int
  let productID: Int
  let locationID: Int

  var mappingID: String {
    "\(vendorID):\(productID)"
  }
}

struct ScrollInputContext {
  let source: ScrollSourceKind
  let deviceID: String?
}

enum InputDeviceRole: String, Codable, CaseIterable {
  case unknown
  case mouse
  case keyboard
  case both
  case ignored

  var title: String {
    switch self {
    case .unknown:
      return agentText("devices.role.unknown")
    case .mouse:
      return agentText("devices.role.mouse")
    case .keyboard:
      return agentText("devices.role.keyboard")
    case .both:
      return agentText("devices.role.both")
    case .ignored:
      return agentText("devices.role.ignored")
    }
  }

  func includes(_ observedRole: InputDeviceRole) -> Bool {
    self == observedRole || self == .both
  }
}

private struct InputDeviceRoleProfile: Codable {
  let id: String
  let vendorID: Int
  let productID: Int
  let name: String
  let role: InputDeviceRole
}

private final class InputDeviceRoleStore {
  static let shared = InputDeviceRoleStore()
  private let url: URL
  private var profiles: [InputDeviceRoleProfile]
  private var rolesByID: [String: InputDeviceRole]

  private init() {
    let directory = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("MacBootstrapAgent", isDirectory: true)
    let profileURL = directory.appendingPathComponent("input-device-roles.json")
    url = profileURL
    let savedProfiles: [InputDeviceRoleProfile]
    if let data = try? Data(contentsOf: profileURL),
      let decodedProfiles = try? JSONDecoder().decode([InputDeviceRoleProfile].self, from: data)
    {
      savedProfiles = decodedProfiles
    } else {
      savedProfiles = []
    }
    profiles = savedProfiles
    rolesByID = Dictionary(
      savedProfiles.map { ($0.id, $0.role) },
      uniquingKeysWith: { _, latest in latest }
    )
  }

  func role(for device: InputDeviceDescriptor) -> InputDeviceRole {
    rolesByID[device.mappingID] ?? .unknown
  }

  @discardableResult
  func observe(_ observedRole: InputDeviceRole, for device: InputDeviceDescriptor) -> Bool {
    let current = role(for: device)
    guard current != .ignored else { return false }
    let merged: InputDeviceRole
    switch (current, observedRole) {
    case (.unknown, .mouse), (.mouse, .mouse):
      merged = .mouse
    case (.unknown, .keyboard), (.keyboard, .keyboard):
      merged = .keyboard
    case (.mouse, .keyboard), (.keyboard, .mouse), (.both, _):
      merged = .both
    default:
      merged = observedRole
    }
    guard merged != current else { return false }
    do {
      try set(merged, for: device)
      return true
    } catch {
      NSLog(
        "Failed to persist input device role for %@: %@", device.name, error.localizedDescription)
      return false
    }
  }

  func set(_ role: InputDeviceRole, for device: InputDeviceDescriptor) throws {
    var updatedProfiles = profiles.filter { $0.id != device.mappingID }
    if role != .unknown {
      updatedProfiles.append(
        InputDeviceRoleProfile(
          id: device.mappingID,
          vendorID: device.vendorID,
          productID: device.productID,
          name: device.name,
          role: role
        ))
    }
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let data = try JSONEncoder().encode(updatedProfiles)
    try data.write(to: url, options: .atomic)
    profiles = updatedProfiles
    if role == .unknown {
      rolesByID.removeValue(forKey: device.mappingID)
    } else {
      rolesByID[device.mappingID] = role
    }
  }
}

final class InputDeviceInventory {
  static let shared = InputDeviceInventory()
  private let manager: IOHIDManager
  private let roleStore = InputDeviceRoleStore.shared
  private var deviceRecords: [ObjectIdentifier: DeviceRecord] = [:]
  private var recentScrollInput: (context: ScrollInputContext, timestamp: TimeInterval)?
  private var inventoryNotificationPending = false

  private init() {
    manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDManagerSetDeviceMatching(manager, nil)
    let matchingCallback: IOHIDDeviceCallback = { context, _, _, device in
      guard let context else { return }
      let inventory = Unmanaged<InputDeviceInventory>.fromOpaque(context).takeUnretainedValue()
      inventory.deviceDidConnect(device)
    }
    let removalCallback: IOHIDDeviceCallback = { context, _, _, device in
      guard let context else { return }
      let inventory = Unmanaged<InputDeviceInventory>.fromOpaque(context).takeUnretainedValue()
      inventory.deviceDidDisconnect(device)
    }
    let context = Unmanaged.passUnretained(self).toOpaque()
    IOHIDManagerRegisterDeviceMatchingCallback(manager, matchingCallback, context)
    IOHIDManagerRegisterDeviceRemovalCallback(manager, removalCallback, context)
    // Runtime scroll reversal only needs wheel reports. Keyboard and pointer
    // movement are classified once when their HID devices connect.
    let wheelElements = [
      ["UsagePage": kHIDPage_GenericDesktop, "Usage": 0x38],
      ["UsagePage": kHIDPage_Consumer, "Usage": 0x238],
    ]
    IOHIDManagerSetInputValueMatchingMultiple(manager, wheelElements as CFArray)
    IOHIDManagerRegisterInputValueCallback(
      manager,
      { context, _, _, value in
        guard let context else { return }
        let inventory = Unmanaged<InputDeviceInventory>.fromOpaque(context).takeUnretainedValue()
        inventory.handleInputValue(value)
      }, context)
    IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
    IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
  }

  func externalKeyboards() -> [InputDeviceDescriptor] {
    keyboardCandidates().filter {
      roleStore.role(for: $0) == .keyboard || roleStore.role(for: $0) == .both
    }
  }

  func externalMice() -> [InputDeviceDescriptor] {
    let devices = allDevices().filter { record in
      record.usagePage == kHIDPage_GenericDesktop && record.usage == kHIDUsage_GD_Mouse
        && !record.builtIn && !record.isVirtual && !record.isTrackpad
        && (roleStore.role(for: record.descriptor) == .mouse
          || roleStore.role(for: record.descriptor) == .both)
    }
    .map(\.descriptor)
    let uniqueDevices = Dictionary(
      devices.map { ($0.mappingID, $0) }, uniquingKeysWith: { first, _ in first })
    return uniqueDevices.values.sorted {
      $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
  }

  func keyboardCandidates() -> [InputDeviceDescriptor] {
    let devices = allDevices().filter { record in
      record.usagePage == kHIDPage_GenericDesktop && record.usage == kHIDUsage_GD_Keyboard
        && !record.builtIn && !record.isVirtual
    }
    .map(\.descriptor)
    let uniqueDevices = Dictionary(
      devices.map { ($0.mappingID, $0) }, uniquingKeysWith: { first, _ in first })
    return uniqueDevices.values.sorted {
      $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
  }

  func confirmKeyboard(_ device: InputDeviceDescriptor) {
    if roleStore.observe(.keyboard, for: device) {
      postInventoryChanged()
    }
  }

  func unclassifiedDevices() -> [InputDeviceDescriptor] {
    let devices = keyboardCandidates() + mouseCandidates()
    let uniqueDevices = Dictionary(
      devices.map { ($0.mappingID, $0) }, uniquingKeysWith: { first, _ in first })
    return uniqueDevices.values
      .filter { roleStore.role(for: $0) == .unknown }
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  func assignRole(_ role: InputDeviceRole, to device: InputDeviceDescriptor) throws {
    try roleStore.set(role, for: device)
    postInventoryChanged()
  }

  func recentScrollContext(maxAge: TimeInterval = 0.25) -> ScrollInputContext {
    guard let recentScrollInput,
      ProcessInfo.processInfo.systemUptime - recentScrollInput.timestamp <= maxAge
    else {
      return ScrollInputContext(source: .unknown, deviceID: nil)
    }
    return recentScrollInput.context
  }

  private struct DeviceRecord {
    let descriptor: InputDeviceDescriptor
    let usagePage: Int
    let usage: Int
    let builtIn: Bool
    let isVirtual: Bool
    let isTrackpad: Bool
  }

  private func allDevices() -> [DeviceRecord] {
    let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
    let connectedKeys = Set(devices.map(ObjectIdentifier.init))
    deviceRecords = deviceRecords.filter { connectedKeys.contains($0.key) }
    return devices.map(cachedDeviceRecord)
  }

  private func mouseCandidates() -> [InputDeviceDescriptor] {
    allDevices().filter { record in
      record.usagePage == kHIDPage_GenericDesktop && record.usage == kHIDUsage_GD_Mouse
        && !record.builtIn && !record.isVirtual && !record.isTrackpad
    }
    .map(\.descriptor)
  }

  private func cachedDeviceRecord(_ device: IOHIDDevice) -> DeviceRecord {
    let key = ObjectIdentifier(device)
    if let cached = deviceRecords[key] {
      return cached
    }
    let record = makeDeviceRecord(device)
    deviceRecords[key] = record
    return record
  }

  private func makeDeviceRecord(_ device: IOHIDDevice) -> DeviceRecord {
    let name =
      stringProperty(device, key: kIOHIDProductKey as CFString) ?? agentText("devices.unknown")
    let manufacturer = stringProperty(device, key: kIOHIDManufacturerKey as CFString) ?? ""
    let transport = stringProperty(device, key: kIOHIDTransportKey as CFString) ?? ""
    let vendorID = intProperty(device, key: kIOHIDVendorIDKey as CFString)
    let productID = intProperty(device, key: kIOHIDProductIDKey as CFString)
    let locationID = intProperty(device, key: kIOHIDLocationIDKey as CFString)
    let usagePage = intProperty(device, key: kIOHIDPrimaryUsagePageKey as CFString)
    let usage = intProperty(device, key: kIOHIDPrimaryUsageKey as CFString)
    let builtIn = boolProperty(device, key: "Built-In" as CFString)
    let normalizedIdentity = "\(manufacturer) \(name)".lowercased()
    let isVirtual =
      normalizedIdentity.contains("karabiner") || normalizedIdentity.contains("virtualhid")
      || normalizedIdentity.contains("pqrs")
    let isTrackpad = InputDeviceRolePolicy.isTrackpad(identity: normalizedIdentity)
    let id = [String(vendorID), String(productID), transport, name].joined(separator: ":")
    return DeviceRecord(
      descriptor: InputDeviceDescriptor(
        id: id,
        name: name,
        manufacturer: manufacturer,
        transport: transport,
        vendorID: vendorID,
        productID: productID,
        locationID: locationID
      ),
      usagePage: usagePage,
      usage: usage,
      builtIn: builtIn,
      isVirtual: isVirtual,
      isTrackpad: isTrackpad
    )
  }

  private func deviceDidConnect(_ device: IOHIDDevice) {
    let record = cachedDeviceRecord(device)
    classifyConnectedDevice(record)
    postInventoryChanged()
  }

  private func deviceDidDisconnect(_ device: IOHIDDevice) {
    deviceRecords.removeValue(forKey: ObjectIdentifier(device))
    postInventoryChanged()
  }

  private func handleInputValue(_ value: IOHIDValue) {
    guard IOHIDValueGetIntegerValue(value) != 0 else { return }
    let element = IOHIDValueGetElement(value)
    let record = cachedDeviceRecord(IOHIDElementGetDevice(element))
    let elementUsagePage = Int(IOHIDElementGetUsagePage(element))
    let elementUsage = Int(IOHIDElementGetUsage(element))
    let isWheel = InputDeviceRolePolicy.isWheelElement(
      usagePage: elementUsagePage,
      usage: elementUsage
    )
    guard isWheel else { return }
    let source: ScrollSourceKind
    if record.isTrackpad || record.builtIn || record.usagePage == kHIDPage_Digitizer {
      source = .trackpad
    } else if record.usagePage == kHIDPage_GenericDesktop,
      record.usage == kHIDUsage_GD_Mouse,
      !record.isVirtual
    {
      source = .mouse
    } else {
      source = .unknown
    }
    recentScrollInput = (
      ScrollInputContext(
        source: source, deviceID: source == .mouse ? record.descriptor.mappingID : nil),
      ProcessInfo.processInfo.systemUptime
    )
  }

  private func classifyConnectedDevice(_ record: DeviceRecord) {
    guard !record.builtIn, !record.isVirtual else { return }
    if record.usagePage == kHIDPage_GenericDesktop,
      record.usage == kHIDUsage_GD_Keyboard
    {
      _ = roleStore.observe(.keyboard, for: record.descriptor)
    } else if record.usagePage == kHIDPage_GenericDesktop,
      record.usage == kHIDUsage_GD_Mouse,
      !record.isTrackpad
    {
      _ = roleStore.observe(.mouse, for: record.descriptor)
    }
  }

  private func intProperty(_ device: IOHIDDevice, key: CFString) -> Int {
    (IOHIDDeviceGetProperty(device, key) as? NSNumber)?.intValue ?? 0
  }

  private func boolProperty(_ device: IOHIDDevice, key: CFString) -> Bool {
    (IOHIDDeviceGetProperty(device, key) as? NSNumber)?.boolValue ?? false
  }

  private func stringProperty(_ device: IOHIDDevice, key: CFString) -> String? {
    IOHIDDeviceGetProperty(device, key) as? String
  }

  private func postInventoryChanged() {
    guard !inventoryNotificationPending else { return }
    inventoryNotificationPending = true
    DispatchQueue.main.async {
      self.inventoryNotificationPending = false
      NotificationCenter.default.post(name: inputDeviceInventoryDidChangeNotification, object: nil)
    }
  }

  deinit {
    IOHIDManagerUnscheduleFromRunLoop(
      manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
    IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
  }
}
