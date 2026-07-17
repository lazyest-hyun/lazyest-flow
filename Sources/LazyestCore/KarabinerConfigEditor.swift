import Foundation

public enum KarabinerConfigEditorError: LocalizedError {
  case invalidRoot
  case invalidSection(String)
  case selectedProfileMissing

  public var errorDescription: String? {
    switch self {
    case .invalidRoot:
      return "Invalid Karabiner configuration."
    case .invalidSection(let name):
      return "Invalid Karabiner configuration section: \(name)."
    case .selectedProfileMissing:
      return "Selected Karabiner profile not found."
    }
  }
}

public enum KarabinerConfigEditor {
  private static let ownedModifierKeys = [
    "left_option", "left_command", "right_option", "right_command",
  ]
  private static let ownedSimpleMappings = [
    "left_option": "left_command",
    "left_command": "left_option",
    "right_option": "right_command",
    "right_command": "right_option",
  ]

  public static func applyingWindowsLayout(
    to data: Data,
    vendorID: Int,
    productID: Int
  ) throws -> Data {
    var root = try rootObject(from: data)
    var profiles = try profiles(from: root)
    guard let profileIndex = profiles.firstIndex(where: { ($0["selected"] as? Bool) == true })
    else {
      throw KarabinerConfigEditorError.selectedProfileMissing
    }
    var profile = profiles[profileIndex]

    var devices = try objectArray(profile["devices"], section: "profiles[].devices")
    let deviceIndex = devices.firstIndex { matches($0, vendorID: vendorID, productID: productID) }
    var device =
      deviceIndex.map { devices[$0] } ?? [
        "identifiers": [
          "is_keyboard": true,
          "is_pointing_device": false,
          "product_id": productID,
          "vendor_id": vendorID,
        ]
      ]
    var simpleModifications = try objectArray(
      device["simple_modifications"],
      section: "profiles[].devices[].simple_modifications"
    )
    simpleModifications.removeAll { modification in
      guard let source = sourceKey(in: modification) else { return false }
      return ownedModifierKeys.contains(source)
    }
    simpleModifications.append(contentsOf: [
      simpleModification(from: "left_option", to: "left_command"),
      simpleModification(from: "left_command", to: "left_option"),
      simpleModification(from: "right_option", to: "right_command"),
      simpleModification(from: "right_command", to: "right_option"),
    ])
    device["simple_modifications"] = simpleModifications
    if let deviceIndex {
      devices[deviceIndex] = device
    } else {
      devices.append(device)
    }
    profile["devices"] = devices
    profiles[profileIndex] = profile
    root["profiles"] = profiles
    return try encoded(root)
  }

  public static func resettingWindowsLayout(
    in data: Data,
    vendorID: Int,
    productID: Int
  ) throws -> Data {
    var root = try rootObject(from: data)
    var profiles = try profiles(from: root)
    guard let profileIndex = profiles.firstIndex(where: { ($0["selected"] as? Bool) == true })
    else {
      throw KarabinerConfigEditorError.selectedProfileMissing
    }
    var profile = profiles[profileIndex]
    var devices = try objectArray(profile["devices"], section: "profiles[].devices")
    if let deviceIndex = devices.firstIndex(where: {
      matches($0, vendorID: vendorID, productID: productID)
    }) {
      var device = devices[deviceIndex]
      var simpleModifications = try objectArray(
        device["simple_modifications"],
        section: "profiles[].devices[].simple_modifications"
      )
      simpleModifications.removeAll { modification in
        guard let source = sourceKey(in: modification) else { return false }
        return ownedModifierKeys.contains(source)
      }
      device["simple_modifications"] = simpleModifications
      devices[deviceIndex] = device
    }
    profile["devices"] = devices
    profiles[profileIndex] = profile
    root["profiles"] = profiles
    return try encoded(root)
  }

  public static func resettingAllWindowsLayouts(in data: Data) throws -> Data {
    var root = try rootObject(from: data)
    var profiles = try profiles(from: root)
    for profileIndex in profiles.indices {
      var profile = profiles[profileIndex]
      var devices = try objectArray(profile["devices"], section: "profiles[].devices")
      for deviceIndex in devices.indices where hasOwnedDeviceMappings(devices[deviceIndex]) {
        var device = devices[deviceIndex]
        var simpleModifications = try objectArray(
          device["simple_modifications"], section: "profiles[].devices[].simple_modifications")
        simpleModifications.removeAll { modification in
          guard let source = sourceKey(in: modification) else { return false }
          return ownedModifierKeys.contains(source)
        }
        device["simple_modifications"] = simpleModifications
        devices[deviceIndex] = device
      }
      profile["devices"] = devices
      profiles[profileIndex] = profile
    }
    root["profiles"] = profiles
    return try encoded(root)
  }

  public static func isWindowsLayoutApplied(
    in data: Data,
    vendorID: Int,
    productID: Int
  ) -> Bool {
    guard let root = try? rootObject(from: data),
      let profiles = try? profiles(from: root),
      let profile = profiles.first(where: { ($0["selected"] as? Bool) == true }),
      let devices = profile["devices"] as? [[String: Any]],
      let device = devices.first(where: { matches($0, vendorID: vendorID, productID: productID) }),
      let modifications = device["simple_modifications"] as? [[String: Any]]
    else {
      return false
    }
    let expected = ownedSimpleMappings
    var actual: [String: String] = [:]
    for modification in modifications {
      guard let source = sourceKey(in: modification),
        let destination = destinationKey(in: modification)
      else {
        continue
      }
      actual[source] = destination
    }
    return expected.allSatisfy { actual[$0.key] == $0.value }
  }

  private static func hasOwnedDeviceMappings(_ device: [String: Any]) -> Bool {
    guard let modifications = device["simple_modifications"] as? [[String: Any]] else {
      return false
    }
    var actual: [String: String] = [:]
    for modification in modifications {
      guard let source = sourceKey(in: modification),
        let destination = destinationKey(in: modification)
      else {
        continue
      }
      actual[source] = destination
    }
    return ownedSimpleMappings.allSatisfy { actual[$0.key] == $0.value }
  }

  private static func matches(_ device: [String: Any], vendorID: Int, productID: Int) -> Bool {
    guard let identifiers = device["identifiers"] as? [String: Any] else { return false }
    return (identifiers["vendor_id"] as? NSNumber)?.intValue == vendorID
      && (identifiers["product_id"] as? NSNumber)?.intValue == productID
      && (identifiers["is_keyboard"] as? Bool) != false
  }

  private static func simpleModification(from source: String, to destination: String) -> [String:
    Any]
  {
    [
      "from": ["key_code": source],
      "to": [["key_code": destination]],
    ]
  }

  private static func sourceKey(in modification: [String: Any]) -> String? {
    (modification["from"] as? [String: Any])?["key_code"] as? String
  }

  private static func destinationKey(in modification: [String: Any]) -> String? {
    guard let targets = modification["to"] as? [[String: Any]] else { return nil }
    return targets.first?["key_code"] as? String
  }

  private static func rootObject(from data: Data) throws -> [String: Any] {
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw KarabinerConfigEditorError.invalidRoot
    }
    return root
  }

  private static func profiles(from root: [String: Any]) throws -> [[String: Any]] {
    guard let profiles = root["profiles"] as? [[String: Any]] else {
      throw KarabinerConfigEditorError.invalidRoot
    }
    return profiles
  }

  private static func object(_ value: Any?, section: String) throws -> [String: Any] {
    guard let value else { return [:] }
    guard let result = value as? [String: Any] else {
      throw KarabinerConfigEditorError.invalidSection(section)
    }
    return result
  }

  private static func objectArray(_ value: Any?, section: String) throws -> [[String: Any]] {
    guard let value else { return [] }
    guard let result = value as? [[String: Any]] else {
      throw KarabinerConfigEditorError.invalidSection(section)
    }
    return result
  }

  private static func encoded(_ root: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
  }
}
