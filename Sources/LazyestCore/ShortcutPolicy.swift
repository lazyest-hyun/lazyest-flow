public enum ShortcutPolicy {
  public static func hasGlobalActivationModifier(_ modifiers: [String]) -> Bool {
    let normalized = Set(modifiers.map { $0.lowercased() })
    return !normalized.isDisjoint(with: [
      "ctrl", "control",
      "opt", "option", "alt",
      "cmd", "command",
    ])
  }
}
