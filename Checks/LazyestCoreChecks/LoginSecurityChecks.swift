import Foundation
import LazyestCore

func loginSecurityFailures() -> [String] {
  var failures: [String] = []
  func expect(_ value: Bool, _ message: String) {
    if !value { failures.append("Login security: " + message) }
  }
  let help = """
    Usage: sysadminctl
    -autologin set -userName <user name> [-password <user password>] || off || status (interactive || -adminUser <administrator user name> -adminPassword <administrator password>)
    -screenLock <status || immediate || off || seconds> -password <password>
    Pass '-' instead of password in commands above to request prompt.
    Use '-' or 'interactive' to get the authentication string interactively.
    """
  let caps = LoginToolCapabilities.detect(help: help, exitCode: 0)
  expect(caps.startup && caps.wake, "documented local help not detected")
  expect(LoginToolCapabilities.detect(help: help, exitCode: 1) == .unknown, "failed help trusted")
  expect(
    LoginToolCapabilities.detect(help: help, exitCode: 0, timedOut: true) == .unknown,
    "timed-out help trusted")
  expect(
    LoginToolCapabilities.detect(help: "autologin screenLock", exitCode: 0) == .unknown,
    "partial capability names trusted")
  let changed = help.replacingOccurrences(of: "-password <password>", with: "-token <token>")
  expect(
    !LoginToolCapabilities.detect(help: changed, exitCode: 0).wake,
    "changed password contract accepted")
  expect(
    LoginToolCapabilities.detect(help: "### Error: denied\n" + help, exitCode: 0) == .unknown,
    "help with an error was accepted")
  expect(LoginConsoleIdentity(userName: "root", uid: 0) == nil, "root identity accepted")
  for user in ["loginwindow", "_mbsetupuser", "a;echo x", "--password", "a\n", "a b", ""] {
    expect(
      LoginConsoleIdentity(userName: user, uid: 501) == nil, "unsafe/session identity accepted")
  }
  let identity = LoginConsoleIdentity(userName: "fixture", uid: 501)!
  let initial = LoginSecuritySnapshot(
    identity: identity, capabilities: caps, fileVault: .off, startup: .user("fixture"),
    wake: .seconds(0))
  func snapshot(
    identity: LoginConsoleIdentity? = identity,
    fileVault: AutomaticLoginPolicy.FileVaultState = .off,
    startup: StartupLoginObservation = .off, wake: WakeLoginObservation = .seconds(0)
  ) -> LoginSecuritySnapshot {
    LoginSecuritySnapshot(
      identity: identity, capabilities: caps, fileVault: fileVault, startup: startup, wake: wake)
  }
  let prefix = "2026-10-11 11:05:26.577 sysadminctl[56587:31154236] "
  expect(
    LoginToolStatusParser.startup(
      LoginToolResult(exitCode: 0, stderr: prefix + "Automatic login is OFF.\n")) == .off,
    "stderr NSLog off not parsed")
  expect(
    LoginToolStatusParser.startup(
      LoginToolResult(exitCode: 0, stdout: "Automatic login user: fixture\n")) == .user("fixture"),
    "startup account not parsed")
  expect(
    LoginToolStatusParser.startup(
      LoginToolResult(
        exitCode: 0, stderr: "Automatic login is disabled because FileVault is enabled.\n"))
      == .blockedByFileVault,
    "FileVault-specific observation not parsed")
  let observedError =
    prefix + "### Error:-69807 File:/AppleInternal/... Line:56\n"
    + prefix + "Automatic login is OFF.\n"
  expect(
    LoginToolStatusParser.startup(LoginToolResult(exitCode: 0, stderr: observedError)) == .unknown,
    "actual error plus OFF was trusted")
  for text in [
    "", "Error: denied\nAutomatic login is OFF.", "Automatic login is OFF.\nwarning",
    "Automatic login user: --password", "Automatic login is OFF.\nAutomatic login is OFF.",
  ] {
    expect(
      LoginToolStatusParser.startup(LoginToolResult(exitCode: 0, stderr: text)) == .unknown,
      "ambiguous startup result trusted")
  }
  expect(
    LoginToolStatusParser.startup(LoginToolResult(exitCode: 1, stderr: "Automatic login is OFF."))
      == .unknown,
    "nonzero startup result trusted")
  expect(
    LoginToolStatusParser.startup(
      LoginToolResult(exitCode: 0, stdout: "Automatic login is OFF.", timedOut: true)) == .unknown,
    "timed-out startup result trusted")
  for (text, expected) in [
    ("screenLock is off", WakeLoginObservation.off),
    ("screenLock delay is immediate", .seconds(0)),
    ("screenLock delay is 60 seconds", .seconds(60)),
  ] {
    expect(
      LoginToolStatusParser.wake(LoginToolResult(exitCode: 0, stderr: prefix + text)) == expected,
      "documented wake result not parsed")
  }
  for text in [
    "screenLock delay is -1 seconds", "screenLock delay is 1.5 seconds",
    "screenLock delay is 60 seconds\n### Error: 1", "screenLock is off\nDone.",
  ] {
    expect(
      LoginToolStatusParser.wake(LoginToolResult(exitCode: 0, stderr: text)) == .unknown,
      "invalid wake output trusted")
  }
  for changedPrompt in ["", "Pass '*' instead of password in commands above to request prompt."] {
    let declaration = "Pass '-' instead of password in commands above to request prompt."
    let changedCaps = LoginToolCapabilities.detect(
      help: help.replacingOccurrences(of: declaration, with: changedPrompt), exitCode: 0)
    expect(
      changedCaps.startup && changedCaps.wake, "missing prompt disabled read-only status support")
    expect(
      !changedCaps.startupPasswordPrompt && !changedCaps.wakePasswordPrompt,
      "missing/changed prompt declaration enabled password-dependent plans")
    let limited = LoginSecuritySnapshot(
      identity: identity, capabilities: changedCaps, fileVault: .off,
      startup: .off, wake: .seconds(0))
    expect(
      LoginSecurityCommandPlan.make(action: .startupOff, snapshot: limited) != nil,
      "startup off unnecessarily required a password prompt")
    expect(
      LoginSecurityCommandPlan.make(action: .startupCurrentUser, snapshot: limited) == nil,
      "startup enable accepted an unverified prompt contract")
    expect(
      LoginSecurityCommandPlan.make(action: .wake(.off), snapshot: limited) == nil,
      "wake mutation accepted an unverified prompt contract")
  }
  let otherAccount = snapshot(startup: .user("other"))
  let offScope = LoginSecurityConfirmationScope(
    action: .startupOff, snapshot: otherAccount, actor: identity)
  expect(
    offScope.actingUser == identity && offScope.affected == .machineAutomaticLogin(.user("other")),
    "machine-wide startup off misidentified the acting user as the affected account")
  let unknownScope = LoginSecurityConfirmationScope(
    action: .startupOff, snapshot: snapshot(startup: .unknown), actor: identity)
  expect(
    unknownScope.affected == .machineAutomaticLogin(.unknown),
    "unknown affected auto-login account was replaced with console user")
  expect(
    LoginSecurityConfirmationScope(
      action: .startupCurrentUser, snapshot: otherAccount, actor: identity
    ).affected == .account("fixture"),
    "startup enable did not identify the requested target account")

  final class MockSnapshotSource: LoginSecuritySnapshotSource {
    let help: String
    let identity: LoginConsoleIdentity
    var startup = "Automatic login user: fixture"
    var seconds = 0
    var changedConsole = false
    var events: [String] = []
    var identityReads = 0
    init(help: String, identity: LoginConsoleIdentity) {
      self.help = help
      self.identity = identity
    }
    func consoleIdentity() -> LoginConsoleIdentity? {
      events.append("console")
      identityReads += 1
      return changedConsole && identityReads % 2 == 0
        ? LoginConsoleIdentity(userName: "other", uid: 502) : identity
    }
    func read(_ command: LoginSecurityReadCommand) -> LoginToolResult {
      switch command {
      case .help:
        events.append("help")
        return LoginToolResult(exitCode: 0, stderr: help)
      case .fileVaultStatus:
        events.append("vault")
        return LoginToolResult(exitCode: 1, stdout: "false\n")
      case .startupStatus:
        events.append("startup")
        return LoginToolResult(exitCode: 0, stderr: startup)
      case .wakeStatus:
        events.append("wake")
        return LoginToolResult(
          exitCode: 0,
          stderr: seconds == 0
            ? "screenLock delay is immediate" : "screenLock delay is \(seconds) seconds")
      }
    }
  }
  let source = MockSnapshotSource(help: help, identity: identity)
  let firstFresh = LoginSecuritySnapshotProvider.freshSnapshot(using: source)
  source.startup = "Automatic login is OFF."
  source.seconds = 60
  let secondFresh = LoginSecuritySnapshotProvider.freshSnapshot(using: source)
  expect(
    firstFresh.startup == .user("fixture") && firstFresh.wake == .seconds(0)
      && secondFresh.startup == .off && secondFresh.wake == .seconds(60),
    "fresh provider reused cached OS observations")
  expect(
    source.events == [
      "console", "help", "vault", "startup", "wake", "console",
      "console", "help", "vault", "startup", "wake", "console",
    ], "fresh provider did not query each OS source every time")
  source.changedConsole = true
  expect(
    LoginSecuritySnapshotProvider.freshSnapshot(using: source).identity == nil,
    "session change during OS reads was accepted")
  for command in LoginSecurityReadCommand.allCases {
    expect(
      command.arguments == ["-help"] || command.arguments == ["-autologin", "status"]
        || command.arguments == ["-screenLock", "status"] || command.arguments == ["isactive"],
      "fresh provider command allowlist permits a security mutation")
  }
  final class FreshMockRunner: LoginSecurityActionRunner {
    let source: MockSnapshotSource
    var changeDuringAuth = false
    var mutateOnApply = true
    var applies = 0
    init(_ source: MockSnapshotSource) { self.source = source }
    func authenticationTransportVerified(for plan: LoginSecurityCommandPlan) -> Bool { true }
    func currentSnapshot() -> LoginSecuritySnapshot {
      LoginSecuritySnapshotProvider.freshSnapshot(using: source)
    }
    func authenticate(_ plan: LoginSecurityCommandPlan) -> LoginSecurityAuthenticationResult {
      if changeDuringAuth { source.seconds = 60 }
      return .authorized
    }
    func apply(_ plan: LoginSecurityCommandPlan) -> LoginSecurityApplyResult {
      applies += 1
      if mutateOnApply { source.startup = "Automatic login is OFF." }
      return .finished
    }
  }
  let liveSource = MockSnapshotSource(help: help, identity: identity)
  let freshRunner = FreshMockRunner(liveSource)
  var freshSession = LoginSecurityChangeSession()
  freshSession.choose(
    .startupOff, snapshot: LoginSecuritySnapshotProvider.freshSnapshot(using: liveSource))
  liveSource.events = []
  freshSession.confirm(using: freshRunner)
  expect(
    freshSession.phase == .applied && freshRunner.applies == 1 && liveSource.events.count == 18,
    "pre-auth/pre-apply/readback did not each obtain fresh OS reads")
  for changeAfterAuth in [false, true] {
    let changedSource = MockSnapshotSource(help: help, identity: identity)
    let runner = FreshMockRunner(changedSource)
    runner.changeDuringAuth = changeAfterAuth
    freshSession.choose(
      .startupOff, snapshot: LoginSecuritySnapshotProvider.freshSnapshot(using: changedSource))
    if !changeAfterAuth { changedSource.seconds = 60 }
    freshSession.confirm(using: runner)
    expect(
      freshSession.phase == .failed(.contextChanged) && runner.applies == 0,
      "fresh OS change before/after auth did not prevent application")
  }
  let mismatchSource = MockSnapshotSource(help: help, identity: identity)
  let noWriteRunner = FreshMockRunner(mismatchSource)
  noWriteRunner.mutateOnApply = false
  freshSession.choose(
    .startupOff, snapshot: LoginSecuritySnapshotProvider.freshSnapshot(using: mismatchSource))
  mismatchSource.events = []
  freshSession.confirm(using: noWriteRunner)
  expect(
    freshSession.phase == .failed(.readbackMismatch) && mismatchSource.events.count == 18,
    "unchanged fresh readback was silently replaced with the desired setting")
  let off = LoginSecurityCommandPlan.make(action: .startupOff, snapshot: initial)!
  expect(
    off.executable == "/usr/sbin/sysadminctl"
      && off.arguments == ["interactive", "-autologin", "off"],
    "startup off command changed")
  let on = LoginSecurityCommandPlan.make(action: .startupCurrentUser, snapshot: initial)!
  expect(
    on.arguments == ["interactive", "-autologin", "set", "-userName", "fixture", "-password", "-"],
    "startup on not bound to console account")
  expect(
    LoginSecurityCommandPlan.make(action: .startupCurrentUser, snapshot: snapshot(fileVault: .on))
      == nil,
    "FileVault on did not block enable plan")
  expect(
    LoginSecurityCommandPlan.make(
      action: .startupCurrentUser, snapshot: snapshot(fileVault: .unknown)) == nil,
    "unknown FileVault permitted enable plan")
  expect(
    LoginSecurityCommandPlan.make(action: .startupOff, snapshot: snapshot(identity: nil)) == nil,
    "missing console identity accepted")
  for delay in WakePasswordDelay.allCases {
    let wake = LoginSecurityCommandPlan.make(
      action: .wake(delay), snapshot: snapshot(fileVault: .on))!
    expect(
      wake.arguments == ["interactive", "-screenLock", delay.rawValue, "-password", "-"],
      "wake command not allowlisted or unnecessarily FileVault blocked")
  }
  expect(WakePasswordDelay(rawValue: "-force") == nil, "arbitrary setting accepted")
  expect(
    !off.matches(snapshot(identity: LoginConsoleIdentity(userName: "other", uid: 502))),
    "different console account accepted as successful readback")

  final class MockRunner: LoginSecurityActionRunner {
    var transportVerified = true
    var allowedAction: LoginSecurityAction?
    func authenticationTransportVerified(for plan: LoginSecurityCommandPlan) -> Bool {
      transportVerified && (allowedAction == nil || allowedAction == plan.action)
    }
    var snapshots: [LoginSecuritySnapshot]
    var authentication: LoginSecurityAuthenticationResult = .authorized
    var applied: LoginSecurityApplyResult = .finished
    var events: [String] = []
    init(_ snapshots: [LoginSecuritySnapshot]) { self.snapshots = snapshots }
    func currentSnapshot() -> LoginSecuritySnapshot {
      events.append("read")
      return snapshots.count > 1 ? snapshots.removeFirst() : snapshots[0]
    }
    func authenticate(_ plan: LoginSecurityCommandPlan) -> LoginSecurityAuthenticationResult {
      events.append("authenticate")
      return authentication
    }
    func apply(_ plan: LoginSecurityCommandPlan) -> LoginSecurityApplyResult {
      events.append("apply")
      return applied
    }
  }
  var session = LoginSecurityChangeSession()
  let successful = MockRunner([initial, initial, snapshot()])
  session.confirm(using: successful)
  expect(successful.events.isEmpty, "unconfirmed action executed")
  session.choose(.startupOff, snapshot: initial)
  expect(session.phase == .awaitingConfirmation, "choice did not await confirmation")
  var phases: [LoginSecurityPhase] = []
  session.confirm(using: successful) { phases.append($0) }
  expect(session.phase == .applied, "matching readback not completed")
  expect(phases == [.authenticating, .applying, .verifying, .applied], "phase order changed")
  expect(
    successful.events == ["read", "authenticate", "read", "apply", "read"],
    "confirmation/session/readback checks missing")
  session.confirm(using: successful)
  expect(successful.events.count == 5, "completed mutation retried")

  session.choose(.startupOff, snapshot: initial)
  session.cancel()
  session.confirm(using: successful)
  expect(session.phase == .cancelled && successful.events.count == 5, "cancelled choice executed")
  let gated = MockRunner([initial])
  gated.transportVerified = false
  session.choose(.startupOff, snapshot: initial)
  session.confirm(using: gated)
  expect(
    session.phase == .failed(.authenticationTransportUnverified) && gated.events == ["read"],
    "unverified auth transport invoked a prompt or write")
  for (auth, expected) in [
    (LoginSecurityAuthenticationResult.cancelled, LoginSecurityPhase.cancelled),
    (.denied, .failed(.denied)),
  ] {
    let runner = MockRunner([initial])
    runner.authentication = auth
    session.choose(.startupOff, snapshot: initial)
    session.confirm(using: runner)
    expect(
      session.phase == expected && !runner.events.contains("apply"),
      "cancelled/denied auth applied a change")
  }
  for (apply, expected) in [
    (LoginSecurityApplyResult.failed, LoginSecurityPhase.failed(.commandFailed)),
    (.timedOut, .failed(.outcomeUnknown)),
  ] {
    let runner = MockRunner([initial])
    runner.applied = apply
    session.choose(.startupOff, snapshot: initial)
    session.confirm(using: runner)
    session.confirm(using: runner)
    expect(
      session.phase == expected && runner.events.filter { $0 == "apply" }.count == 1
        && runner.events.last == "read",
      "failed/uncertain mutation retried or called successful")
  }
  for snapshots in [[snapshot()], [initial, snapshot()]] {
    let changed = MockRunner(snapshots)
    session.choose(.startupOff, snapshot: initial)
    session.confirm(using: changed)
    expect(
      session.phase == .failed(.contextChanged) && !changed.events.contains("apply"),
      "changed context before/after authentication applied")
  }
  let perActionGate = MockRunner([initial])
  perActionGate.allowedAction = .startupOff
  session.choose(.wake(.off), snapshot: initial)
  session.confirm(using: perActionGate)
  expect(
    session.phase == .failed(.authenticationTransportUnverified)
      && !perActionGate.events.contains("authenticate"),
    "one action's auth validation unlocked another")
  for delay in WakePasswordDelay.allCases {
    let result: WakeLoginObservation =
      delay == .off ? .off : .seconds(delay == .immediate ? 0 : Int(delay.rawValue)!)
    let runner = MockRunner([initial, initial, snapshot(wake: result)])
    session.choose(.wake(delay), snapshot: initial)
    session.confirm(using: runner)
    expect(session.phase == .applied, "wake readback did not match allowlisted delay")
  }
  let startupInitial = snapshot(startup: .off)
  let onRunner = MockRunner([startupInitial, startupInitial, initial])
  session.choose(.startupCurrentUser, snapshot: startupInitial)
  session.confirm(using: onRunner)
  expect(session.phase == .applied, "current-user startup readback not completed")
  let mismatch = MockRunner([initial, initial, initial])
  session.choose(.startupOff, snapshot: initial)
  session.confirm(using: mismatch)
  expect(session.phase == .failed(.readbackMismatch), "exit success treated as applied")
  return failures
}
