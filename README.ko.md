# Menu Pulse

<p align="center">
  <img src="Packaging/AppIcon.png" alt="Menu Pulse icon" width="96">
</p>

[English README](README.md)

풀 모니터링 대시보드가 아니라, 메뉴바에서 필요한 값만 작게 보는 앱입니다.

기본은 `CPU`와 `RAM`만 보여주고, 원하면 `TEMP` (온도)와 `DISK` (저장공간)을 추가할 수 있습니다.

```text
CPU: 12%    TEMP: 52°C
RAM: 63%    DISK: 87%
```

**macOS 13 이상 Apple Silicon Mac 전용**으로, **핵심 기능** + **적은 리소스 사용량**이 컨셉입니다.

## 다운로드

[최신 DMG 다운로드](https://github.com/hyunseop827/menu-pulse/releases/latest/download/MenuPulse.dmg)

다운로드 파일을 검증하려면 DMG와 체크섬 파일을 같은 폴더에 받은 뒤 아래를 실행하세요.

```zsh
curl -LO https://github.com/hyunseop827/menu-pulse/releases/latest/download/MenuPulse.dmg
curl -LO https://github.com/hyunseop827/menu-pulse/releases/latest/download/SHA256SUMS.txt
shasum -a 256 -c SHA256SUMS.txt
```

`MenuPulse.dmg: OK`가 나오면 배포된 파일과 체크섬이 일치합니다.

아직 Apple notarization은 안 되어 있어서 처음 실행할 때 macOS 경고가 뜰 수 있습니다.
먼저 앱을 `/Applications`로 옮긴 뒤 Finder에서 우클릭하여 `열기`를 선택하세요.
그래도 macOS가 막고 체크섬 검증이 성공했다면 아래를 실행할 수 있습니다.

```zsh
sudo xattr -dr com.apple.quarantine "/Applications/Menu Pulse.app"
open "/Applications/Menu Pulse.app"
```

## 라이선스

MIT 라이선스입니다.

자유롭게 사용, 수정, 배포할 수 있습니다. 대신 앱은 있는 그대로 제공되며, 사용 중 생기는 문제에 대한 보증은 없습니다.

자세한 내용은 [LICENSE](LICENSE)를 확인하세요.

## 기능

- `CPU`: 기본 ON
- `RAM`: 기본 ON
- `TEMP`: 선택 기능, 기본 OFF, 섭씨/화씨 지원
- `DISK`: 선택 기능, 기본 OFF

RAM은 macOS 활성 상태 보기의 `Memory Used`에 가깝게, 앱 메모리 + 시스템 고정 메모리 + 압축 메모리 기준으로 계산합니다.

온도는 갱신할 때마다 사용 가능한 IOHID 센서를 모두 비교하고, 실패하면 지원하는 SMC 키를 모두 비교합니다.
그중 가장 뜨거운 유효 센서 값을 `TEMP`로 표시합니다.
기기 조합에 따라 항상 보장되지는 않으며, 읽지 못하면 `TEMP:--°C`처럼 표시됩니다.

기본 새로고침 주기:

```text
CPU  10s
RAM  10s
TEMP 30s
DISK 300s
```

새로고침 주기는 가벼운 동작을 위해 고정되어 있습니다.

## 가볍게 쓰기 위한 의도

MenuPulse는 기능이 많은 모니터링 앱이 아니라, 메뉴바에서 숫자만 작게 확인하는 앱입니다.

- Objective-C/AppKit 기반 네이티브 앱
- Electron, 웹뷰, 그래프 없음
- 히스토리 저장 및 대시보드 없음
- 실행해도 Dock에 아이콘이 뜨지 않음
- 설정으로 킨 값만 읽도록 설정
- 온도 표시를 꺼두면 센서도 읽지 않음
- 하나의 가벼운 타이머로 필요한 항목만 갱신
- macOS 기본 로그인 항목 API 사용

벤치 마크를 해보고 싶다면 다음을 실행하세요.

```sh
Scripts/measure.sh
```

## 개발 관련

### 프로젝트 구조

```text
Sources/MenuPulse/
  main.m
  MenuPulse.m
  Monitors.m
  TemperatureReader.m
  LoginItemManager.m

Packaging/
  Info.plist
  AppIcon.icns

Scripts/
  build-app.sh
  build-dmg.sh
  install.sh
  uninstall.sh
  measure.sh
  release.sh

Tests/
  MonitorTests.m
```

### 스크립트

| Script | 용도 |
| --- | --- |
| `Scripts/build-app.sh` | Objective-C 소스를 빌드해서 `build/release/Menu Pulse.app`을 만듭니다. 개발 중 실행 확인에 사용합니다. |
| `Scripts/build-dmg.sh` | 앱을 다시 빌드한 뒤 `dist/MenuPulse.dmg`를 만듭니다. 배포용 파일을 확인할 때 사용합니다. |
| `Scripts/install.sh` | 앱을 `~/Applications`에 설치하고 로그인 실행을 등록합니다. macOS 승인이 필요할 수 있습니다. |
| `Scripts/uninstall.sh` | 설치된 앱과 로그인 자동 실행 설정을 제거합니다. |
| `Scripts/measure.sh` | 앱을 실행한 뒤 CPU, 메모리 사용량, 앱/DMG 크기를 짧게 측정합니다. |
| `Scripts/test.sh` | 모니터 값 범위, CPU 초기화, Mach host port reference 누수를 검사합니다. |
| `Scripts/release.sh` | 버전을 입력하면 `Info.plist` 수정, DMG 빌드, commit, tag, push까지 처리합니다. |
