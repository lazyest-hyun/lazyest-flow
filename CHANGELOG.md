# Changelog

## 1.0.0 - 2026-07-18

- Explained which features require Accessibility permission and which work without it.
- Added Developer ID signing, notarization, Gatekeeper verification, and SHA-256 release packaging.

## 0.5.0 - 2026-07-17

- Rebranded the menu bar app, Swift package, executables, and source modules as Lazyest Flow.
- Migrated the legacy MacBootstrapAgent app and Application Support directory during installation.
- Preserved the bundle identifier, helper labels, signing identity fallback, and login-item maintenance keys so existing permissions and runtime settings continue to work.

## 0.4.13 - 2026-07-15

- Improved light-mode contrast for tabs and cards while keeping colors adaptive when the system appearance changes.
- Separated connected mouse and keyboard rows, defaulted ambiguous receivers to the mouse section, and added an in-row device type switch.
- Aligned Input Devices headings with the other tabs and made the device page scroll when its content grows.
- Limited keyboard presets to device-specific Windows-to-Mac modifier mapping; global F18 input switching remains owned by Setup.
- Preserved the macOS floating screenshot thumbnail while copying completed captures to the clipboard.

## 0.4.12 - 2026-07-15

- Stopped activating every window of the previously foreground application when hiding a hotkey target, preventing unrelated Chrome windows from covering visible apps on other displays.

## 0.4.11 - 2026-07-15

- Made app hotkeys hide only their target application, including visible background apps, while preserving the current foreground app.
- Used the target application's accessibility hidden state for reliable Electron app toggles and excluded hidden registered apps from foreground handoff.
- Made the global hide shortcut keep every registered app hidden and activate the first visible unregistered application.

## 0.4.10 - 2026-07-14

- Moved the language selector from the global footer into the General tab alongside the login-start setting.

## 0.4.9 - 2026-07-14

- Reduced always-on HID work to wheel reports only. Standard external keyboards and mice are classified when their device connects; composite receivers remain explicitly classifiable in the input-device UI.
- Reduced Dock placement fallback verification from five seconds to fifteen seconds while retaining immediate display-change recovery and the real-time Dock trigger filter.

## 0.4.8 - 2026-07-14

- Added an opt-in Fast Dock Response toggle. Enabling sets no reveal delay and a 0.15-second animation; disabling deletes only those Dock overrides and restores macOS defaults.
- Displayed whether Dock timing is using macOS defaults, the Flow fast setting, or an existing user-defined value without changing it on launch.

## 0.4.7 - 2026-07-14

- Preserved Control-wheel gestures so browser zoom and macOS accessibility zoom pass through without mouse-scroll reversal.

## 0.4.6 - 2026-07-13

- Read the physical lid state from the dedicated IOPM clamshell message instead of racing the registry property update.
- Replaced the removed `CGSession` lock executable on current macOS with the native Control-Command-Q lock shortcut while retaining older macOS compatibility.
- Stopped reporting a successful lid-close action when the lock request itself fails.

## 0.4.5 - 2026-07-13

- Replaced the opaque `/usr/bin/open` LaunchAgent with the native `SMAppService.mainApp` login item so LazyestFlow appears by name in System Settings.
- Migrated an enabled legacy login registration only after native registration succeeds and preserved the setting across source updates.
- Detected the macOS login-item launch Apple event so automatic startup remains menu-bar-only while a manual app launch still opens Settings.

## 0.4.4 - 2026-07-13

- Added an opt-in Start at Login setting that launches the installed Flow in the menu bar after macOS login without opening its settings window.
- Added verified, user-scoped LaunchAgent registration with no keep-alive restart loop, no shell evaluation, and no administrator permission requirement.
- Preserved the login-start choice across source updates and removed it when the Flow is uninstalled.

## 0.4.3 - 2026-07-13

- Extended sleep prevention to closed-lid operation through a narrowly scoped, administrator-installed helper that does not require an Apple Team ID.
- Added a fixed-layout power scope control for power-only or battery operation, with automatic low-battery and thermal safety pauses.
- Added an optional lid-close action that immediately locks the session and turns off displays while background work remains awake.
- Added live power/helper state in the settings window without inserting or removing rows as state changes.
- Pinned privileged XPC calls to the installing console user, current Flow path, bundle identifier, valid running code, and installation-time CDHash.
- Added a 90-second helper watchdog, root-only ownership marker, safe update refresh, and removal that restores only the sleep state owned by the Flow.

## 0.4.2 - 2026-07-13

- Released the settings window and its notification observers when closed instead of retaining the full UI tree for the life of the menu-bar process.
- Made screenshot monitoring event-driven in normal operation, with a low-frequency fallback scan instead of full directory enumeration every two seconds.
- Retried incomplete screenshot files directly without repeatedly enumerating the screenshot directory.
- Read screenshot provenance from the file's metadata attribute before falling back to Spotlight metadata.
- Kept the Dock blocking tap dormant away from secondary-display Dock edges, then armed it inside a wide approach zone with immediate edge recovery for fast cursor jumps.
- Preferred the lower-level HID event tap and retained a session-event fallback for systems where HID tap creation is unavailable.
- Kept mouse-event work to cached region checks, recovered disabled taps, and automatically restored the configured display if periodic verification detects Dock drift.
- Cached static HID device metadata and role lookups instead of rebuilding device descriptions for every input value.
- Cached per-mouse scroll modes so wheel events no longer scan the persisted profile list.
- Ensured an enabled Dock pin restores the configured display when the agent starts and finds the Dock elsewhere, while reporting active state only for a valid event tap.
- Required the real Dock location to match the selected display before settings or menu state can report anchoring as active.
- Kept Dock detection working when macOS redacts window titles, and synchronized the settings badge with the controller's typed runtime state instead of stale notification text.

## 0.4.1 - 2026-07-13

- Cached Dock target and edge geometry so mouse-move handling performs allocation-free region checks.
- Kept the Dock event tap disabled outside cached 120-point activation bands and used low-frequency cursor proximity checks to activate it only near blocked edges.
- Coalesced repeated Dock-blocked status updates instead of scheduling work for every edge event.
- Reduced Dock permission and orientation polling from two seconds to five seconds.
- Moved screenshot validation and optional format conversion off the main thread.
- Avoided full pixel decoding for PNG screenshots and bounded compatibility conversion for large images.
- Limited screenshot tracking to new files from the most recent two minutes.
- Reduced maximum accepted screenshot payloads to 64 MB encoded and 50 megapixels.

## 0.4.0 - 2026-07-13

- Added synchronized menu-bar toggles for app hotkeys, screenshot clipboard copy, sleep prevention, and Dock pinning.
- Distinguished requested-but-unavailable runtime features from active features in menu state.
- Reworked Dock pinning around one persistent event tap, cached display geometry, runtime recovery, and bottom, left, and right Dock edges.
- Made enabling Dock pinning relocate the Dock to the selected display before protecting that display.
- Stabilized app-hotkey row controls and made long bundle identifiers keep their most useful trailing text visible.
- Consolidated runtime setting persistence and extracted its menu-state policy into the checked core module.
- Verified the sleep assertion lifecycle and settings/menu synchronization against the installed app.
- Split the monolithic agent source into focused environment, configuration, UI, runtime, device, and support files.
- Removed unreachable text-shortcut code and obsolete runtime settings.
- Restricted packaging destinations, removed external binary substitution, and made source builds authoritative.
- Required macOS screenshot provenance and bounded image bytes, pixels, frames, and retries before clipboard publication.
- Rejected modifierless global hotkeys and exposed requested/runtime state mismatches.
- Made Dock relocation cancellable and retained failed sleep-assertion releases for retry.
- Preserved Karabiner configuration structure and removed the owned global F18 rule after the last mapped keyboard is reset.
- Added portable Core regression checks, formatter enforcement, and macOS CI.

## 0.3.0 - 2026-07-13

- Added an Input Devices tab with one policy for reversing every conventional wheel mouse while preserving continuous trackpad scrolling.
- Added opt-in per-device external keyboard presets with apply/reset controls and reconnect persistence.
- Fixed high-resolution mouse wheels being mistaken for trackpads and prevented linked scroll fields from cancelling the reversal.
- Classified composite receivers by observed key and pointer input, and excluded external Magic Trackpads from mouse-wheel reversal.
- Added per-mouse direction modes with a default for newly connected mice.
- Persisted detected device roles and added an explicit classification fallback for receivers whose keyboard activity is unavailable.
- Replaced ineffective per-device `hidutil` keyboard writes with verified Karabiner device mappings and migrated right Command to F18 into the Complex Modifications stage.
- Extracted reusable event-tap lifecycle management and a tested scroll-policy core module.
- Kept both new capabilities disabled and non-mutating on fresh installs.

## 0.2.2 - 2026-07-10

- Combined screenshot file watching and immediate clipboard copy into one switch.

## 0.2.1 - 2026-07-10

- Made every app-hotkey row use the full list width regardless of app name or bundle ID length.

## 0.2.0 - 2026-07-10

- Split LazyestFlow into its own repository and Swift package.
- Added configurable app hotkeys, screenshot clipboard copy, sleep prevention, and Dock pinning.
- Kept fresh installs inert with no default hotkeys or enabled runtime features.
- Added Korean and English UI.
