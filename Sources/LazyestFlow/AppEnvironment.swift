import Foundation

let dockPinStatusNotification = Notification.Name("LazyestFlowDockPinStatusChanged")

enum DockPinStatus: String {
  case off = "dock.status.off"
  case active = "dock.status.active"
  case relocating = "dock.status.relocating"
  case blocked = "dock.status.blocked"
  case moveFailed = "dock.status.moveFailed"
  case needsPermission = "dock.status.needsPermission"
  case failed = "dock.status.failed"

  var localizedText: String {
    flowText(rawValue)
  }
}

enum FlowLanguage: String {
  case automatic = "auto"
  case english = "en"
  case korean = "ko"
}

func flowSharedLanguageConfigPath() -> URL {
  let base =
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(
      "Library/Application Support", isDirectory: true)
  return base.appendingPathComponent("Lazyest Flow", isDirectory: true).appendingPathComponent(
    "language.conf")
}

func flowSavedLanguageCode() -> String {
  if let preview = flowPreviewLanguage { return preview.rawValue }
  let path = flowSharedLanguageConfigPath()
  if let value = try? String(contentsOf: path, encoding: .utf8).trimmingCharacters(
    in: .whitespacesAndNewlines),
    !value.isEmpty
  {
    return value
  }
  return UserDefaults.standard.string(forKey: "LazyestFlowLanguage")
    ?? LegacyFlowIdentity.savedLanguageCode()
    ?? FlowLanguage.automatic.rawValue
}

func saveFlowLanguageCode(_ code: String) throws {
  guard FlowLanguage(rawValue: code) != nil else { return }
  let path = flowSharedLanguageConfigPath()
  try FileManager.default.createDirectory(
    at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
  try code.write(to: path, atomically: true, encoding: .utf8)
  UserDefaults.standard.set(code, forKey: "LazyestFlowLanguage")
}

var flowPreviewLanguage: FlowLanguage?

func flowLanguage() -> FlowLanguage {
  if let preview = flowPreviewLanguage { return preview }
  let selected = FlowLanguage(rawValue: flowSavedLanguageCode()) ?? .automatic
  if selected != .automatic {
    return selected
  }
  let preferred = Locale.preferredLanguages.first?.lowercased() ?? ""
  return preferred.hasPrefix("ko") ? .korean : .english
}

private let koreanAgentStrings: [String: String] = [
  "title": "Lazyest Flow",
  "tab.general": "일반",
  "tab.apps": "앱 단축키",
  "tab.screenshots": "스크린샷",
  "tab.keepAwake": "슬립모드 방지",
  "tab.dockPin": "Dock 고정",
  "tab.inputDevices": "입력 장치",
  "general.title": "일반",
  "general.detail": "Flow의 시작 방식을 설정합니다.",
  "general.loginLaunch": "로그인 시 자동 실행",
  "general.loginLaunchDetail":
    "Mac에 로그인하면 설정 창 없이 메뉴 막대에서 시작하며 시스템 설정의 로그인 항목에도 표시됩니다.",
  "general.permissions": "권한 안내",
  "general.permissionsDetail":
    "즉시 스크린샷, 앱 단축키, 마우스 스크롤, 덮개 잠금, Dock 고정만 손쉬운 사용 권한을 사용합니다. 슬립모드 방지와 기본 설정은 이 권한 없이 사용할 수 있습니다.",
  "general.permissionsOpen": "권한 설정",
  "general.status.approval": "승인 필요",
  "general.status.review": "자동 실행 확인",
  "general.upgradeLoginHelp": "이전 앱의 로그인 항목은 macOS에서 직접 관리합니다. 업데이트 후 자동 실행을 원하면 이 스위치를 켜세요.",
  "general.status.repair": "복구 필요",
  "general.status.install": "앱 설치 필요",
  "general.remove": "Flow 제거",
  "general.removeDetail": "앱을 제거하고 초기화 범위를 고릅니다.",
  "general.removeConfirmTitle": "Flow를 제거할까요?",
  "general.removeConfirmDetail":
    "로그인 자동 실행과 전원 보조 도구는 항상 제거합니다. 초기화할 항목을 고르세요. 접근성 허용은 macOS에서 직접 관리합니다.",
  "general.removeConfirm": "제거",
  "general.removeProgress": "제거 중",
  "general.remove.settings": "Flow 설정 및 단축키 초기화",
  "general.remove.dock": "Dock 반응을 macOS 기본값으로 초기화",
  "general.remove.screenshot": "스크린샷 저장 위치를 macOS 기본값으로 초기화",
  "general.remove.keyboard": "Flow가 적용한 Karabiner 키보드 매핑 해제",
  "general.remove.settingsDetail": "다음 설치에서도 유지할 Flow 설정과 앱 단축키",
  "general.remove.dockDetail": "Flow가 적용한 Dock 자동 숨김 반응 시간",
  "general.remove.screenshotDetail": "현재 스크린샷 저장 위치를 macOS 기본값으로 변경",
  "general.remove.keyboardDetail": "Flow가 추가한 장치별 Option/Command 매핑",
  "general.removeSheet.title": "Flow 제거",
  "general.removeSheet.detail": "앱은 제거하고, 필요한 항목만 선택해 초기화할 수 있습니다.",
  "general.removeSheet.alwaysTitle": "항상 제거됨",
  "general.removeSheet.alwaysDetail": "Lazyest Flow 앱, 로그인 시 자동 실행, 전원 보조 도구",
  "general.removeSheet.resetTitle": "추가로 초기화",
  "general.removeSheet.resetDetail": "기본값은 완전 제거입니다. 유지할 항목은 해당 토글을 끄세요.",
  "general.removeSheet.accessibilityNote": "접근성 허용은 macOS에서 관리되어 그대로 남습니다.",
  "apps.hint": "단축키로 앱을 숨기거나 다시 표시합니다. 실행 중이 아니면 앱을 엽니다.",
  "apps.enabled": "앱 단축키 사용",
  "apps.hideAll": "등록 앱 모두 숨기기",
  "apps.hideAllDetail": "실행 중이며 화면에 떠 있는 등록 앱만 한 번에 숨깁니다.",
  "apps.hideAllSet": "설정",
  "apps.hideAllClear": "해제",
  "apps.countSuffix": "개 앱",
  "apps.name": "이름",
  "apps.bundle": "번들 ID",
  "apps.shortcut": "단축키",
  "apps.add": "앱 추가",
  "apps.addRunning": "앱 추가",
  "apps.editTitle": "앱 단축키 추가",
  "apps.editRow": "변경",
  "apps.applyRow": "적용",
  "apps.editName": "이름",
  "apps.editBundle": "번들 ID",
  "apps.editShortcut": "단축키",
  "apps.editShortcutHint": "단축키를 직접 누르세요",
  "apps.capturing": "단축키 입력 중",
  "apps.captured": "캡처됨",
  "apps.cancel": "취소",
  "apps.remove": "삭제",
  "devices.title": "입력 장치",
  "devices.detail": "마우스 정책과 직접 적용한 키보드 매핑은 장치를 다시 연결해도 유지됩니다.",
  "devices.mouse.title": "마우스",
  "devices.mouse.reverse": "새 마우스도 세로 스크롤 반전",
  "devices.mouse.reverseDetail": "감지된 마우스의 개별 설정이 우선하며 내장·Magic Trackpad는 제외됩니다.",
  "devices.mouse.identify": "분류된 외장 마우스가 없습니다.",
  "devices.mouse.mode.inherit": "새 마우스 기본값 따름",
  "devices.mouse.mode.reversed": "세로 스크롤 반전",
  "devices.mouse.mode.system": "macOS 기본 방향",
  "devices.role.unknown": "장치 종류 선택",
  "devices.role.mouse": "마우스로 사용",
  "devices.role.keyboard": "키보드로 사용",
  "devices.role.both": "키보드와 마우스",
  "devices.role.ignored": "무시",
  "devices.role.change": "장치 유형 변경",
  "devices.mouse.status.off": "꺼짐",
  "devices.mouse.status.active": "마우스별 설정 적용 중",
  "devices.mouse.status.needsPermission": "Accessibility 권한 미적용",
  "devices.mouse.status.failed": "스크롤 이벤트 감시 시작 실패",
  "devices.keyboard.title": "키보드",
  "devices.keyboard.detail": "Windows 키보드의 Option/Command 조작키를 Mac 배열로 바꿉니다.",
  "devices.keyboard.empty": "분류된 외장 키보드가 없습니다.",
  "devices.keyboard.preset.none": "변경 없음",
  "devices.keyboard.preset.mac": "Windows → Mac 조작키",
  "devices.keyboard.status.none": "설정 없음",
  "devices.keyboard.status.applied": "적용됨",
  "devices.keyboard.apply": "적용",
  "devices.keyboard.reset": "초기화",
  "devices.keyboard.error.conflict": "Karabiner에서 이 키보드의 기존 보조 키 매핑을 해제한 뒤 적용하세요.",
  "devices.keyboard.error.karabiner": "Karabiner-Elements가 필요합니다.",
  "devices.keyboard.error.config": "Karabiner 설정 파일을 찾을 수 없습니다.",
  "devices.keyboard.error.verify": "Karabiner 키 매핑 검증에 실패했습니다.",
  "devices.unknown": "알 수 없는 장치",
  "screenshots.title": "스크린샷",
  "screenshots.detail": "⌘⇧3/4로 복사하고, Control을 함께 누르면 파일로 저장합니다.",
  "screenshots.folder": "저장 폴더",
  "screenshots.choose": "변경",
  "screenshots.open": "폴더 열기",
  "screenshots.copy": "스크린샷을 클립보드로",
  "screenshots.copyDetail": "⌘⇧3/4는 클립보드로 복사하고, ⌃⌘⇧3/4는 파일 저장과 macOS 네이티브 프리뷰를 사용합니다.",
  "state.on": "켜짐",
  "state.off": "꺼짐",
  "keep.title": "슬립모드 방지",
  "keep.detail": "덮개를 닫으면 화면을 끄고 작업을 계속합니다.",
  "keep.prevent": "슬립모드 방지 사용",
  "keep.powerScope": "적용 범위",
  "keep.powerScopeDetail": "배터리 20% 이하 또는 심한 발열 시 자동으로 중지합니다. 직접 잠자려면 먼저 슬립모드 방지를 끄세요.",
  "keep.powerOnly": "전원 연결 시만",
  "keep.includeBattery": "배터리 포함",
  "keep.lockOnLid": "덮개를 닫으면 즉시 잠금",
  "keep.lockOnLidDetail": "화면은 항상 꺼집니다. 이 옵션을 켜면 잠금도 함께 적용합니다.",
  "keep.sleepOnKoreanLid": "한국어 입력 중에는 덮개 잠자기",
  "keep.sleepOnKoreanLidDetail":
    "macOS 기본 한국어 입력 소스를 선택했을 때만 덮개 잠자기를 허용합니다. 구름 등 외부 입력기의 내부 한/A 상태는 macOS가 공개하지 않아 지원하지 않습니다.",
  "keep.status.off": "꺼짐",
  "keep.status.activating": "시작 중",
  "keep.status.active": "실행 중",
  "keep.status.waitingPower": "전원 연결 대기 중",
  "keep.status.lowBattery": "배터리 부족으로 일시 정지",
  "keep.status.thermal": "발열 보호로 일시 정지",
  "keep.status.helperApproval": "관리자 보조 도구 설치 필요",
  "keep.status.helperUnavailable": "슬립 방지 시작 실패",
  "keep.helperUnavailableHelp": "다른 잠자기 관리 앱이 사용 중일 수 있습니다. 덮개 제어는 한 앱에서만 켜세요.",
  "keep.power.ac": "전원 연결",
  "keep.power.battery": "배터리",
  "keep.power.batteryPercent": "배터리 %d%%",
  "dock.title": "Dock 고정",
  "dock.detail": "켜면 선택한 모니터로 Dock을 한 번 옮긴 뒤 다른 모니터에서 호출되지 않게 유지합니다.",
  "dock.checkbox": "Dock 고정 사용",
  "dock.display": "고정할 모니터",
  "dock.timing": "빠른 Dock 반응",
  "dock.timingDetail": "켜면 즉시 표시하고 빠르게 숨깁니다. 끄면 macOS 기본값으로 초기화합니다.",
  "dock.timing.systemDefault": "macOS 기본값",
  "dock.timing.fast": "빠른 반응",
  "dock.timing.custom": "사용자 지정",
  "dock.permission": "권한 설정",
  "dock.status.off": "꺼짐",
  "dock.status.active": "실행 중",
  "dock.status.relocating": "Dock 이동 중",
  "dock.status.blocked": "다른 모니터 Dock 호출 차단됨",
  "dock.status.moveFailed": "Dock 이동 실패",
  "dock.status.needsPermission": "Accessibility 권한 미적용",
  "dock.status.failed": "이벤트 감시 시작 실패",
  "footer.reload": "설정 다시 불러오기",
  "language.label": "언어",
  "language.auto": "자동",
  "language.korean": "한국어",
  "language.english": "English",
  "footer.save": "저장",
  "status.saved": "자동 저장됨",
  "status.loaded": "설정 불러옴",
  "status.failed": "저장 실패",
  "menu.settings": "설정 열기",
  "menu.appHotkeys": "앱 단축키",
  "menu.screenshotClipboard": "스크린샷 클립보드 복사",
  "screenshots.status.off": "꺼짐",
  "screenshots.status.needsPermission": "Accessibility 권한 필요",
  "screenshots.status.active": "사용 중",
  "screenshots.status.failed": "다시 로드 필요",
  "menu.keepAwake": "슬립모드 방지",
  "menu.dockPin": "Dock 고정",
  "menu.reload": "다시 불러오기",
  "menu.quit": "종료",
]

private let englishAgentStrings: [String: String] = [
  "title": "Lazyest Flow",
  "tab.general": "General",
  "tab.apps": "App Hotkeys",
  "tab.screenshots": "Screenshots",
  "tab.keepAwake": "Prevent Sleep",
  "tab.dockPin": "Dock Pin",
  "tab.inputDevices": "Input Devices",
  "general.title": "General",
  "general.detail": "Choose how the Flow starts.",
  "general.loginLaunch": "Start at login",
  "general.loginLaunchDetail":
    "Starts in the menu bar without opening Settings and appears in System Settings Login Items.",
  "general.permissions": "Permissions",
  "general.permissionsDetail":
    "Only instant screenshots, app hotkeys, mouse scrolling, lid lock, and Dock pin use Accessibility permission. Prevent Sleep and basic settings work without it.",
  "general.permissionsOpen": "Open Settings",
  "general.status.approval": "Approval required",
  "general.status.review": "Check login setting",
  "general.upgradeLoginHelp":
    "macOS manages the previous app’s login item. Turn this switch on to start the updated app at login.",
  "general.status.repair": "Needs repair",
  "general.status.install": "Install app first",
  "general.remove": "Remove Flow",
  "general.removeDetail": "Remove the app and choose what to reset.",
  "general.removeConfirmTitle": "Remove Flow?",
  "general.removeConfirmDetail":
    "Start at login and the power helper are always removed. Choose what to reset. Accessibility permission is managed in macOS.",
  "general.removeConfirm": "Remove",
  "general.removeProgress": "Removing",
  "general.remove.settings": "Reset Flow settings and hotkeys",
  "general.remove.dock": "Reset Dock response to macOS defaults",
  "general.remove.screenshot": "Reset screenshot location to macOS defaults",
  "general.remove.keyboard": "Remove Flow-applied Karabiner keyboard mappings",
  "general.remove.settingsDetail": "Flow settings and app hotkeys to keep for a future install",
  "general.remove.dockDetail": "Dock auto-hide response time changed by the Flow",
  "general.remove.screenshotDetail":
    "Return the current screenshot save location to macOS defaults",
  "general.remove.keyboardDetail": "Per-device Option/Command mappings added by the Flow",
  "general.removeSheet.title": "Remove Flow",
  "general.removeSheet.detail": "Remove the app, then reset only the items you choose.",
  "general.removeSheet.alwaysTitle": "Always removed",
  "general.removeSheet.alwaysDetail": "Lazyest Flow, Start at Login, and the power helper",
  "general.removeSheet.resetTitle": "Also reset",
  "general.removeSheet.resetDetail":
    "Complete removal is selected by default. Turn off anything you want to keep.",
  "general.removeSheet.accessibilityNote": "Accessibility permission stays managed by macOS.",
  "apps.hint": "Use a hotkey to hide or restore an app. The app opens when it is not running.",
  "apps.enabled": "Enable app hotkeys",
  "apps.hideAll": "Hide all registered apps",
  "apps.hideAllDetail": "Hides only registered apps that are running with visible windows.",
  "apps.hideAllSet": "Set",
  "apps.hideAllClear": "Clear",
  "apps.countSuffix": " apps",
  "apps.name": "Name",
  "apps.bundle": "Bundle ID",
  "apps.shortcut": "Shortcut",
  "apps.add": "Add App",
  "apps.addRunning": "Add App",
  "apps.editTitle": "Add App Hotkey",
  "apps.editRow": "Change",
  "apps.applyRow": "Apply",
  "apps.editName": "Name",
  "apps.editBundle": "Bundle ID",
  "apps.editShortcut": "Shortcut",
  "apps.editShortcutHint": "Press the shortcut",
  "apps.capturing": "Capturing shortcut",
  "apps.captured": "Captured",
  "apps.cancel": "Cancel",
  "apps.remove": "Remove",
  "devices.title": "Input Devices",
  "devices.detail":
    "Mouse policy and keyboard mappings you explicitly apply persist after reconnecting devices.",
  "devices.mouse.title": "Mouse",
  "devices.mouse.reverse": "Reverse new mice by default",
  "devices.mouse.reverseDetail":
    "Per-device settings take priority; built-in and Magic Trackpads are excluded.",
  "devices.mouse.identify": "No classified external mouse is connected.",
  "devices.mouse.mode.inherit": "Follow new-mouse default",
  "devices.mouse.mode.reversed": "Reverse vertical scrolling",
  "devices.mouse.mode.system": "macOS default direction",
  "devices.role.unknown": "Choose device type",
  "devices.role.mouse": "Use as mouse",
  "devices.role.keyboard": "Use as keyboard",
  "devices.role.both": "Keyboard and mouse",
  "devices.role.ignored": "Ignore",
  "devices.role.change": "Change device type",
  "devices.mouse.status.off": "Off",
  "devices.mouse.status.active": "Per-device settings active",
  "devices.mouse.status.needsPermission": "Accessibility permission not applied",
  "devices.mouse.status.failed": "Failed to start scroll event monitor",
  "devices.keyboard.title": "Keyboard",
  "devices.keyboard.detail": "Maps a Windows keyboard's Option/Command modifiers to Mac layout.",
  "devices.keyboard.empty": "No classified external keyboard is connected.",
  "devices.keyboard.preset.none": "No changes",
  "devices.keyboard.preset.mac": "Windows → Mac modifiers",
  "devices.keyboard.status.none": "Not set",
  "devices.keyboard.status.applied": "Applied",
  "devices.keyboard.apply": "Apply",
  "devices.keyboard.reset": "Reset",
  "devices.keyboard.error.conflict":
    "Remove this keyboard’s existing modifier mappings in Karabiner, then try again.",
  "devices.keyboard.error.karabiner": "Karabiner-Elements is required.",
  "devices.keyboard.error.config": "Karabiner configuration was not found.",
  "devices.keyboard.error.verify": "Failed to verify the Karabiner key mapping.",
  "devices.unknown": "Unknown device",
  "screenshots.title": "Screenshots",
  "screenshots.detail":
    "Swap the standard shortcuts with their Control variants for clipboard-first capture.",
  "screenshots.folder": "Save folder",
  "screenshots.choose": "Change",
  "screenshots.open": "Open folder",
  "screenshots.copy": "Copy screenshots to clipboard",
  "screenshots.copyDetail":
    "⌘⇧3/4 copies to the clipboard; ⌃⌘⇧3/4 saves a file and uses the native macOS preview.",
  "state.on": "On",
  "state.off": "Off",
  "keep.title": "Prevent Sleep",
  "keep.detail":
    "Keep work running with the lid closed and the display off.",
  "keep.prevent": "Prevent Sleep",
  "keep.powerScope": "Power Scope",
  "keep.powerScopeDetail":
    "Stops at 20% battery or high temperature. Turn Prevent Sleep off before putting the Mac to sleep manually.",
  "keep.powerOnly": "Power only",
  "keep.includeBattery": "Include battery",
  "keep.lockOnLid": "Lock immediately when lid closes",
  "keep.lockOnLidDetail":
    "The display always turns off on lid close. Enable this to lock the Mac as well.",
  "keep.sleepOnKoreanLid": "Allow lid sleep with Korean input",
  "keep.sleepOnKoreanLidDetail":
    "Applies to Apple Korean input sources. Third-party input methods such as Gureum do not expose their internal Korean/A state and are not supported.",
  "keep.status.off": "Off",
  "keep.status.activating": "Starting",
  "keep.status.active": "Active",
  "keep.status.waitingPower": "Waiting for power",
  "keep.status.lowBattery": "Paused for low battery",
  "keep.status.thermal": "Paused for thermal safety",
  "keep.status.helperApproval": "Administrator helper installation required",
  "keep.status.helperUnavailable": "Unable to start sleep prevention",
  "keep.helperUnavailableHelp":
    "Another sleep-control app may be active. Use one lid controller at a time.",
  "keep.power.ac": "Power connected",
  "keep.power.battery": "Battery",
  "keep.power.batteryPercent": "Battery %d%%",
  "dock.title": "Dock Pin",
  "dock.detail":
    "When enabled, moves the Dock to the selected display once and prevents it from being summoned elsewhere.",
  "dock.checkbox": "Keep Dock on display",
  "dock.display": "Pinned display",
  "dock.timing": "Fast Dock response",
  "dock.timingDetail": "Shows immediately and hides faster. Turn it off to restore macOS defaults.",
  "dock.timing.systemDefault": "macOS default",
  "dock.timing.fast": "Fast response",
  "dock.timing.custom": "Custom",
  "dock.permission": "Permission Settings",
  "dock.status.off": "Off",
  "dock.status.active": "Active",
  "dock.status.relocating": "Moving Dock",
  "dock.status.blocked": "Blocked Dock on another display",
  "dock.status.moveFailed": "Dock move failed",
  "dock.status.needsPermission": "Accessibility permission not applied",
  "dock.status.failed": "Failed to start event monitor",
  "footer.reload": "Reload Settings",
  "language.label": "Language",
  "language.auto": "Automatic",
  "language.korean": "한국어",
  "language.english": "English",
  "footer.save": "Save",
  "status.saved": "Saved automatically",
  "status.loaded": "Settings loaded",
  "status.failed": "Save failed",
  "menu.settings": "Open Settings",
  "menu.appHotkeys": "App Hotkeys",
  "menu.screenshotClipboard": "Copy Screenshots",
  "screenshots.status.off": "Off",
  "screenshots.status.needsPermission": "Accessibility permission required",
  "screenshots.status.active": "Active",
  "screenshots.status.failed": "Reload required",
  "menu.keepAwake": "Prevent Sleep",
  "menu.dockPin": "Dock Pin",
  "menu.reload": "Reload",
  "menu.quit": "Quit",
]

func flowText(_ key: String) -> String {
  let strings = flowLanguage() == .korean ? koreanAgentStrings : englishAgentStrings
  return strings[key] ?? englishAgentStrings[key] ?? key
}
