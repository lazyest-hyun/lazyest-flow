public enum ShortcutPolicy {
  public static func hasGlobalActivationModifier(_ modifiers: [String]) -> Bool {
    let normalized = Set(modifiers.map { $0.lowercased() })
    return !normalized.isDisjoint(with: [
      "ctrl", "control",
      "opt", "option", "alt",
      "cmd", "command",
    ])
  }

  public static func keyCode(for key: String) -> UInt32? {
    let map: [String: UInt32] = [
      "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
      "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
      "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
      "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
      "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37,
      "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44,
      "n": 45, "m": 46, ".": 47, "`": 50, "space": 49, "escape": 53,
      "ㅁ": 0, "ㄴ": 1, "ㅇ": 2, "ㄹ": 3, "ㅗ": 4, "ㅎ": 5, "ㅋ": 6, "ㅌ": 7,
      "ㅊ": 8, "ㅍ": 9, "ㅠ": 11, "ㅂ": 12, "ㅈ": 13, "ㄷ": 14, "ㄱ": 15,
      "ㅛ": 16, "ㅅ": 17, "ㅐ": 31, "ㅕ": 32, "ㅑ": 34, "ㅔ": 35,
      "ㅣ": 37, "ㅓ": 38, "ㅏ": 40, "ㅜ": 45, "ㅡ": 46,
    ]
    return map[key]
  }

  public static func keyName(for keyCode: UInt32) -> String? {
    let map: [UInt32: String] = [
      0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x",
      8: "c", 9: "v", 11: "b", 12: "q", 13: "w", 14: "e", 15: "r",
      16: "y", 17: "t", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
      23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
      30: "]", 31: "o", 32: "u", 33: "[", 34: "i", 35: "p", 37: "l",
      38: "j", 39: "'", 40: "k", 41: ";", 42: "\\", 43: ",", 44: "/",
      45: "n", 46: "m", 47: ".", 49: "space", 50: "`", 53: "escape",
    ]
    return map[keyCode]
  }
}
