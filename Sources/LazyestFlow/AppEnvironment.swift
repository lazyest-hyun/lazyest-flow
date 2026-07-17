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
  let path = flowSharedLanguageConfigPath()
  if let value = try? String(contentsOf: path, encoding: .utf8).trimmingCharacters(
    in: .whitespacesAndNewlines),
    !value.isEmpty
  {
    return value
  }
  return UserDefaults.standard.string(forKey: "MacBootstrapLanguage")
    ?? FlowLanguage.automatic.rawValue
}

func saveFlowLanguageCode(_ code: String) throws {
  guard FlowLanguage(rawValue: code) != nil else { return }
  let path = flowSharedLanguageConfigPath()
  try FileManager.default.createDirectory(
    at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
  try code.write(to: path, atomically: true, encoding: .utf8)
  UserDefaults.standard.set(code, forKey: "MacBootstrapLanguage")
}

func flowLanguage() -> FlowLanguage {
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
  "general.status.approval": "승인 필요",
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
  "devices.keyboard.error.karabiner": "Karabiner-Elements가 필요합니다.",
  "devices.keyboard.error.config": "Karabiner 설정 파일을 찾을 수 없습니다.",
  "devices.keyboard.error.verify": "Karabiner 키 매핑 검증에 실패했습니다.",
  "devices.unknown": "알 수 없는 장치",
  "screenshots.title": "스크린샷",
  "screenshots.detail": "기본 스크린샷 단축키는 그대로 사용합니다. 파일은 현재 macOS 저장 위치에 남고 같은 이미지가 클립보드에도 복사됩니다.",
  "screenshots.folder": "저장 폴더",
  "screenshots.choose": "변경",
  "screenshots.open": "폴더 열기",
  "screenshots.copy": "파일 저장 + 클립보드 복사",
  "screenshots.copyDetail": "떠 있는 썸네일은 유지하고, 캡처 이후 즉시 클립보드에도 복사합니다.",
  "state.on": "켜짐",
  "state.off": "꺼짐",
  "keep.title": "슬립모드 방지",
  "keep.detail": "잠금 화면, 디스플레이 꺼짐, 덮개 닫힘 상태에서도 원격 작업을 계속합니다.",
  "keep.prevent": "슬립모드 방지 사용",
  "keep.approve": "보조 도구 설치",
  "keep.powerScope": "적용 범위",
  "keep.powerScopeDetail": "배터리 20% 이하에서는 안전을 위해 자동으로 중지합니다.",
  "keep.powerOnly": "전원 연결 시만",
  "keep.includeBattery": "배터리 포함",
  "keep.lockOnLid": "덮개를 닫으면 즉시 잠금",
  "keep.lockOnLidDetail": "덮개를 감지하면 로그인 화면으로 전환하고 디스플레이를 끕니다.",
  "keep.status.off": "꺼짐",
  "keep.status.activating": "시작 중",
  "keep.status.active": "실행 중",
  "keep.status.waitingPower": "전원 연결 대기 중",
  "keep.status.lowBattery": "배터리 부족으로 일시 정지",
  "keep.status.thermal": "발열 보호로 일시 정지",
  "keep.status.helperApproval": "관리자 보조 도구 설치 필요",
  "keep.status.helperUnavailable": "보조 도구 연결 실패 · 다시 설치 필요",
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
  "general.status.approval": "Approval required",
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
  "devices.keyboard.error.karabiner": "Karabiner-Elements is required.",
  "devices.keyboard.error.config": "Karabiner configuration was not found.",
  "devices.keyboard.error.verify": "Failed to verify the Karabiner key mapping.",
  "devices.unknown": "Unknown device",
  "screenshots.title": "Screenshots",
  "screenshots.detail":
    "Keep using the standard screenshot shortcuts. The file stays in the current macOS save location and the same image is copied to the clipboard.",
  "screenshots.folder": "Save folder",
  "screenshots.choose": "Change",
  "screenshots.open": "Open folder",
  "screenshots.copy": "Save file + copy to clipboard",
  "screenshots.copyDetail": "Keeps the floating thumbnail and copies to the clipboard immediately after capture.",
  "state.on": "On",
  "state.off": "Off",
  "keep.title": "Prevent Sleep",
  "keep.detail":
    "Keeps remote work running while locked, with the display off, or with the lid closed.",
  "keep.prevent": "Prevent Sleep",
  "keep.approve": "Install helper",
  "keep.powerScope": "Power Scope",
  "keep.powerScopeDetail": "Stops automatically at 20% battery to protect the Mac.",
  "keep.powerOnly": "Power only",
  "keep.includeBattery": "Include battery",
  "keep.lockOnLid": "Lock immediately when lid closes",
  "keep.lockOnLidDetail":
    "Switches to the login screen and turns displays off when the lid closes.",
  "keep.status.off": "Off",
  "keep.status.activating": "Starting",
  "keep.status.active": "Active",
  "keep.status.waitingPower": "Waiting for power",
  "keep.status.lowBattery": "Paused for low battery",
  "keep.status.thermal": "Paused for thermal safety",
  "keep.status.helperApproval": "Administrator helper installation required",
  "keep.status.helperUnavailable": "Helper connection failed · reinstall required",
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
  "menu.screenshotClipboard": "Copy Screenshots to Clipboard",
  "menu.keepAwake": "Prevent Sleep",
  "menu.dockPin": "Dock Pin",
  "menu.reload": "Reload",
  "menu.quit": "Quit",
]

func flowText(_ key: String) -> String {
  let strings = flowLanguage() == .korean ? koreanAgentStrings : englishAgentStrings
  return strings[key] ?? englishAgentStrings[key] ?? key
}
