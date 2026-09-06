import Foundation

// Read-only migration identifiers. New installs and writes use the Lazyest identity.
enum LegacyFlowIdentity {
  static let bundleIdentifier = "com.estaid.mac-bootstrap-agent"
  static let languageKey = "MacBootstrapLanguage"

  static var hasLegacyPreferences: Bool {
    UserDefaults.standard.persistentDomain(forName: bundleIdentifier) != nil
  }

  static func savedLanguageCode() -> String? {
    UserDefaults.standard.string(forKey: languageKey)
      ?? UserDefaults(suiteName: bundleIdentifier)?.string(forKey: languageKey)
  }
}
