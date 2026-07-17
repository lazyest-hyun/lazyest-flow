# Lazyest Flow

한국어 사용자를 위한 상시 실행 macOS 메뉴 막대 앱입니다. 일회성 초기 설정 도구인 [Lazyest Setup](https://github.com/hyunn515/lazyest-setup)과 독립적으로 설치하고 업데이트합니다.

이 저장소는 빌드된 앱이나 자동 업데이트를 배포하지 않습니다. 사용자는 소스를 확인한 뒤 자신의 Mac에서 직접 빌드합니다.

## AI Agent 설치

사용자가 **설치**를 명시적으로 요청했다면, 추가 조사나 dry-run 없이 아래 한 명령으로 설치하고 실행합니다.

```sh
(workdir="$(mktemp -d)" && trap 'rm -rf "$workdir"' EXIT && git clone --depth 1 --quiet https://github.com/hyunn515/lazyest-flow.git "$workdir" && "$workdir/bootstrap.sh" install && open "/Applications/Lazyest Flow.app")
```

- 최신 소스만 얕게 받아 현재 Mac에서 빌드하고 `/Applications/Lazyest Flow.app`에 설치한 뒤 임시 소스와 빌드 산출물을 제거합니다.
- 외부 바이너리, Gatekeeper 우회, Homebrew, 기본 기능 활성화는 사용하지 않습니다.
- Swift 도구 모음이 없으면 `xcode-select --install`로 macOS 설치 확인을 열고, 사용자가 승인한 뒤 위 명령을 다시 실행합니다.
- 메뉴 막대 앱이라 실행 중 Dock 아이콘은 숨지만 Finder와 Dock의 응용 프로그램 스택에는 표시됩니다.

## 기능

- 사용자가 등록한 앱을 단축키로 숨기기, 다시 표시하기, 실행하기
- 등록된 실행 앱 전체를 한 단축키로 숨기기. 앱 단축키 사용이 켜져 있을 때만 동작하며 기본 단축키는 없음
- 선택하면 Mac 로그인 시 설정 창 없이 메뉴 막대에서 자동 실행
- macOS가 실제 화면 캡처로 표시한 이미지에 한해 파일로 남기면서 클립보드에도 복사
- 화면 잠금과 디스플레이 꺼짐을 허용하면서 시스템 잠자기 방지. 전원 연결 시만 또는 배터리 포함 선택 가능
- 덮개를 닫아도 작업을 유지하고, 선택하면 덮개를 닫는 즉시 로그인 화면으로 전환
- 메뉴 막대에서 앱 단축키, 스크린샷 복사, 슬립모드 방지, Dock 고정을 즉시 켜고 끄기
- Dock을 선택한 모니터로 옮긴 뒤 해당 모니터에 고정. 하단, 왼쪽, 오른쪽 Dock 지원
- Dock 탭에서 자동 숨김 Dock의 반응 시간을 빠르게 적용하거나 macOS 기본값으로 초기화
- 실제 입력으로 식별된 마우스별로 `기본값 따름 / 세로 반전 / macOS 기본 방향`을 선택하고 내장·Magic Trackpad 스크롤은 유지
- 외장 키보드별 Option/Command 배열 변환. Flow는 장치별 조작키만 바꾸며, F18 한/영 전환은 Setup이 관리하는 Karabiner Complex 규칙을 그대로 사용
- 한국어와 영어 UI

새 설치에서는 로그인 자동 실행을 포함한 모든 기능이 꺼져 있고 기본 앱 단축키도 없습니다.

## 수동 설치

macOS 13 이상과 Swift 도구 모음이 필요합니다.

```sh
git clone https://github.com/hyunn515/lazyest-flow.git
cd lazyest-flow
./bootstrap.sh audit
./bootstrap.sh install
open "/Applications/Lazyest Flow.app"
```

`install`은 현재 체크아웃의 Swift 소스를 항상 새로 빌드한 뒤 `/Applications`에 복사합니다. 외부 바이너리를 받아오거나 실행하지 않으며, 앱을 자동 실행하거나 기능을 자동으로 켜지 않고 기존 사용자 설정도 덮어쓰지 않습니다.

설치 후 Flow의 `일반` 탭에서 `로그인 시 자동 실행`을 켜면 다음 macOS 로그인부터 설정 창 없이 메뉴 막대에서 시작합니다. macOS 네이티브 로그인 항목으로 등록되므로 `시스템 설정 > 일반 > 로그인 항목 및 확장 프로그램 > 로그인 시 열기`에서 `Lazyest Flow` 이름으로 확인하고 제어할 수 있습니다. 관리자 인증은 필요하지 않으며, Flow에서 `종료`를 선택하면 다음 로그인 전까지 임의로 다시 실행하지 않습니다.

빌드 스크립트는 `MacBootstrap Local Code Signing` 인증서가 있으면 자동으로 사용하고, 없으면 hardened runtime을 포함한 ad-hoc 서명으로 돌아갑니다. 어느 쪽이든 Apple Developer Program이나 Team ID 없이 모든 기능을 사용할 수 있습니다. 별도의 로컬 인증서를 쓰려면 이름을 지정할 수 있습니다.

```sh
MAC_BOOTSTRAP_AGENT_CODESIGN_IDENTITY="Your Local Code Signing Identity" ./bootstrap.sh install
```

슬립모드 방지를 처음 켜면 macOS 관리자 인증 창이 한 번 표시됩니다. 인증하면 현재 콘솔 사용자, Flow 경로와 코드 해시만 허용하는 최소 root helper가 고정 시스템 경로에 설치되며, 평소 실행에는 비밀번호가 필요하지 않습니다. helper가 설치된 상태에서 소스를 새로 빌드해 업데이트하면 새 코드 해시를 고정하기 위해 관리자 인증을 한 번 다시 요청합니다.

## 슬립모드 방지 정책

- 기능이 켜져 있는 동안 잠금 화면과 디스플레이 자동 꺼짐은 유지하지만 시스템 잠자기는 막습니다.
- `전원 연결 시만`은 배터리로 전환하면 자동으로 중지하고, `배터리 포함`은 전원 없이도 계속 실행합니다.
- 배터리 포함 상태에서도 잔량 20% 이하 또는 심각한 발열 상태에서는 자동으로 중지합니다.
- `덮개를 닫으면 즉시 잠금`은 별도 선택 사항입니다. 켜면 덮개 닫힘을 감지해 로그인 화면으로 전환하고 디스플레이를 끄지만 백그라운드 작업은 유지합니다.
- Flow가 비정상 종료되거나 heartbeat가 끊기면 helper가 90초 안에 자신이 켠 잠자기 방지를 해제합니다.

## 명령어

```sh
./bootstrap.sh help
./bootstrap.sh version
./bootstrap.sh audit
./bootstrap.sh build [--dry-run]
./bootstrap.sh install [--dry-run]
./bootstrap.sh uninstall [--dry-run]
```

런타임 설정은 `~/Library/Application Support/Lazyest Flow/`에 저장됩니다. 로그인 자동 실행은 macOS `SMAppService`가 관리하며 업데이트 시 보존되고 앱 제거 시 해제됩니다. `승인 필요`가 표시되면 시스템 설정의 로그인 항목에서 Lazyest Flow를 허용하면 됩니다. 메뉴의 체크는 실제 실행 중인 기능을 뜻하며, 요청 상태와 실제 런타임 상태가 다르면 혼합 상태로 표시됩니다. 복합 USB 수신기는 실제 키 입력과 포인터 입력으로 키보드·마우스를 구분하고 역할을 기억합니다. 자동 식별되지 않는 수신기는 입력 장치 탭에서 한 번 직접 종류를 선택할 수 있습니다. 키보드 매핑은 Karabiner의 장치별 Simple Modifications와 전역 Complex Modification을 사용하며, 구조가 올바른 JSON을 보존해 쓴 뒤 실제 매핑 검증에 성공한 경우에만 `적용됨`으로 표시됩니다. 앱 단축키, 마우스 스크롤 반전, 덮개 즉시 잠금, Dock 고정에는 Accessibility 권한이 필요합니다.

일반 탭의 `Flow 제거`는 앱, 로그인 자동 실행과 전원 보조 도구를 제거합니다. 확인창에서 Flow 데이터, Dock 반응, 스크린샷 저장 위치, Flow가 적용한 Karabiner 매핑을 각각 초기화할지 선택합니다. 접근성 허용은 macOS에서 직접 관리합니다.

## 구조

- `Sources/LazyestFlow`: 메뉴, 설정 UI, 런타임 컨트롤러와 macOS 연동
- `Sources/LazyestPowerHelper`: 설치 시 고정한 Flow 코드 해시의 요청만 받는 최소 권한 잠자기 helper
- `Sources/LazyestCore`: 부작용 없는 정책과 구조화된 Karabiner 편집
- `Checks/LazyestCoreChecks`: 전체 Xcode 없이 실행 가능한 회귀 체크
- `scripts`: 빌드, 제한된 앱 패키징, 설치와 제거

## 개발

```sh
swift run LazyestCoreChecks
xcrun swift-format lint --recursive Sources Checks Package.swift
./bootstrap.sh build
./scripts/package-app.sh "$PWD/dist/Lazyest Flow.app"
```

SwiftPM으로 빌드한 앱 번들은 `dist/Lazyest Flow.app`에 생성됩니다.

## 보안

취약점은 공개 이슈 대신 [보안 정책](SECURITY.md)의 비공개 제보 경로를 이용해 주세요.

## License

[The Unlicense](UNLICENSE)
