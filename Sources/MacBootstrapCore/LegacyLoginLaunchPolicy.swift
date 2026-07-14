import Foundation

public enum LegacyLoginLaunchPolicy {
  public static let label = "com.estaid.mac-bootstrap-agent.login"
  public static let installedAppPath = "/Applications/MacBootstrapAgent.app"
  public static let installedAgentExecutablePath =
    "\(installedAppPath)/Contents/MacOS/MacBootstrapAgent"
  public static let openerPath = "/usr/bin/open"
  public static let loginArgument = "--login-launch"

  public static var propertyList: [String: Any] {
    [
      "Label": label,
      "ProgramArguments": [
        openerPath,
        "-g",
        installedAppPath,
        "--args",
        loginArgument,
      ],
      "RunAtLoad": true,
      "LimitLoadToSessionType": "Aqua",
      "ProcessType": "Interactive",
    ]
  }

  public static func isManagedPropertyList(_ value: Any) -> Bool {
    guard let dictionary = value as? [String: Any] else { return false }
    let expectedKeys: Set<String> = [
      "Label",
      "ProgramArguments",
      "RunAtLoad",
      "LimitLoadToSessionType",
      "ProcessType",
    ]
    guard Set(dictionary.keys) == expectedKeys else { return false }
    guard dictionary["Label"] as? String == label else { return false }
    guard
      dictionary["ProgramArguments"] as? [String]
        == propertyList["ProgramArguments"] as? [String]
    else { return false }
    guard dictionary["RunAtLoad"] as? Bool == true else { return false }
    guard dictionary["LimitLoadToSessionType"] as? String == "Aqua" else { return false }
    return dictionary["ProcessType"] as? String == "Interactive"
  }
}
