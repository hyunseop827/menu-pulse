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

## 화면

<p align="center">
  <img src="menupulse-menubar.png" alt="CPU, RAM, TEMP, DISK를 표시하는 Menu Pulse 메뉴바" width="292">
</p>
<p align="center"><sub>메뉴바 모니터링</sub></p>

<p align="center">
  <img src="menupulse-setting.png" alt="Menu Pulse 지표, 갱신 주기, 로그인 항목 설정 창" width="600">
</p>
<p align="center"><sub>간단한 지표, 갱신 주기 및 로그인 설정</sub></p>

## 다운로드

[최신 DMG 다운로드](https://github.com/hyunseop827/menu-pulse/releases/latest/download/MenuPulse.dmg)

다운로드 파일을 검증하려면 DMG와 체크섬 파일을 같은 폴더에 받은 뒤 아래를 실행하세요.

```zsh
curl -LO https://github.com/hyunseop827/menu-pulse/releases/latest/download/MenuPulse.dmg
curl -LO https://github.com/hyunseop827/menu-pulse/releases/latest/download/SHA256SUMS.txt
shasum -a 256 -c SHA256SUMS.txt
```

`MenuPulse.dmg: OK`가 나오면 배포된 파일과 체크섬이 일치합니다.

현재 빌드는 비용을 낮추기 위해 Developer ID가 아닌 ad-hoc 서명을 사용하며, Apple 공증도 받지 않았습니다.
따라서 서명만으로 배포자 출처를 인증할 수 없고, 처음 실행할 때 macOS 경고가 뜰 수 있습니다.
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
- `TEMP`: 선택 기능, 기본 OFF, 섭씨/화씨, `1초`부터 `60초`
- `DISK`: 선택 기능, 기본 OFF, `1분`부터 `10분`
- CPU/RAM 갱신 주기: `1초`, `3초`, `10초`; 기본값 `3초`
- 새 실행에서는 로그인 시작 여부를 한 번 확인하며, 저장소 설치 스크립트는 바로 활성화
- 확인창이 있는 기본값 초기화와 프로그램 종료, 설정창만 숨기는 닫기

RAM은 macOS 활성 상태 보기의 `Memory Used`에 가깝게, 앱 메모리 + 시스템 고정 메모리 + 압축 메모리 기준으로 계산합니다.

온도는 갱신할 때마다 사용 가능한 IOHID 센서를 모두 비교하고, 실패하면 지원하는 SMC 키를 모두 비교합니다.
그중 가장 뜨거운 유효 센서 값을 `TEMP`로 표시합니다.
기기 조합에 따라 항상 보장되지는 않으며, 읽지 못하면 `TEMP:--°C`처럼 표시됩니다.

새로고침 주기:

```text
CPU + RAM  기본 3초 (1초, 3초, 10초 선택)
TEMP       기본 30초 (1초, 3초, 10초, 30초, 60초 선택)
DISK       기본 5분 (1분, 3분, 5분, 10분 선택)
```

예를 들어 평소에는 기본 3초를 사용합니다. 빌드 중 CPU 변화를 짧게 보고 싶을 때만 1초를 선택합니다.
온도를 자주 읽으면 에너지를 더 사용할 수 있으므로 평소에는 기본 30초가 적합합니다.

## 가볍게 쓰기 위한 의도

MenuPulse는 기능이 많은 모니터링 앱이 아니라, 메뉴바에서 숫자만 작게 확인하는 앱입니다.

- Objective-C/AppKit 기반 네이티브 앱
- Electron, 웹뷰, 그래프 없음
- 히스토리 저장 및 대시보드 없음
- 실행해도 Dock에 아이콘이 뜨지 않음
- 설정으로 킨 값만 읽도록 설정
- 온도 표시를 꺼두면 센서도 읽지 않음
- 단조 시계 기반 one-shot 타이머 하나로 필요한 항목만 갱신
- macOS 기본 로그인 항목 API 사용

### 실측 벤치마크

2026년 9월 1일에 Menu Pulse `1.3.0`을 측정한 결과입니다.

- MacBook Air, Apple M1 8코어
- 메모리 16GB, SSD 256GB
- macOS 26.6.2
- 앱 실행 후 30초 예열
- 시나리오마다 5분 동안 1초 간격으로 300회 측정

| 활성화한 지표 | CPU/RAM | TEMP | DISK | CPU 평균 | CPU 최대 | RSS 평균 | RSS 최대 | Private dirty |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| CPU + RAM (기본값) | 3초 | OFF | OFF | 0.065% | 1.000% | 37.2MB | 37.3MB | 9.8MB |
| TEMP 단독 | OFF | 1초 | OFF | 0.273% | 1.500% | 40.0MB | 40.6MB | 12.4MB |
| DISK 단독 | OFF | OFF | 1분 | 0.000% | 0.100% | 37.4MB | 37.5MB | 9.8MB |
| CPU + RAM + TEMP + DISK (최단 주기) | 1초 | 1초 | 1분 | 0.613% | 2.300% | 38.3MB | 38.3MB | 10.3MB |

- 설치된 앱 크기: 약 660KB
- 배포 DMG 크기: 약 966KB

RSS에는 앱이 사용하는 공유 시스템 프레임워크도 포함됩니다.
예를 들어 기본 설정의 RSS는 37.2MB지만, 앱 전용으로 변경된 메모리에 가까운 Private dirty는 9.8MB였습니다.
CPU 최대값은 지표를 갱신하는 순간의 짧은 상승입니다.
결과는 실행 중인 다른 프로세스와 macOS 캐시 상태에 따라 달라질 수 있습니다.

기본 3초 조건은 CPU 평균 0.2% 이하, Private dirty 12MB 이하 목표를 충족했습니다.
최단 주기 조합은 Private dirty 15MB 이하 목표를 충족했지만, CPU 평균은 0.613%로 목표 0.5%를 넘었습니다.
로컬 프로파일에서는 1초 IOHID 온도 센서 조회가 주된 활성 작업이었습니다. TEMP는 기본 OFF이며, 1초 선택지는 짧게 확인할 때 사용하는 설정입니다.

설치된 앱과 영구 설정을 바꾸지 않고 네 시나리오를 다시 측정하려면 다음을 실행하세요.

```sh
# 기본 CPU/RAM
WARMUP=30 DURATION=300 INTERVAL=1 SHOW_CPU=1 SHOW_RAM=1 SHOW_TEMPERATURE=0 SHOW_DISK=0 CPU_RAM_REFRESH_INTERVAL=3 Scripts/measure.sh

# TEMP 단독
WARMUP=30 DURATION=300 INTERVAL=1 SHOW_CPU=0 SHOW_RAM=0 SHOW_TEMPERATURE=1 SHOW_DISK=0 TEMPERATURE_REFRESH_INTERVAL=1 Scripts/measure.sh

# DISK 단독
WARMUP=30 DURATION=300 INTERVAL=1 SHOW_CPU=0 SHOW_RAM=0 SHOW_TEMPERATURE=0 SHOW_DISK=1 DISK_REFRESH_INTERVAL=60 Scripts/measure.sh

# 최단 주기 조합
WARMUP=30 DURATION=300 INTERVAL=1 SHOW_CPU=1 SHOW_RAM=1 SHOW_TEMPERATURE=1 SHOW_DISK=1 CPU_RAM_REFRESH_INTERVAL=1 TEMPERATURE_REFRESH_INTERVAL=1 DISK_REFRESH_INTERVAL=60 Scripts/measure.sh
```

스크립트는 종료할 때 임시 설정, 원시 프로세스 표본, 앱 로그를 모두 삭제합니다.

## 개인정보와 완전 삭제

Menu Pulse는 네트워크 요청을 보내지 않습니다. 텔레메트리, 오류 보고 SDK, 측정 기록, 지표 로그도 없습니다.

로컬에는 표시 지표, 온도 단위, 세 가지 갱신 주기, 로그인 시작 질문에 한 번 답했는지만 저장합니다. 실제 로그인 항목 상태는 macOS가 관리합니다. macOS가 메뉴바 위치, 로그인 항목 등록, 캐시, 창 상태, OS 자체 충돌 진단 파일을 추가로 저장할 수 있습니다.

두 설치 위치와 Menu Pulse 전용 정보를 모두 지우려면 이 저장소에서 다음을 실행하세요.

```sh
Scripts/uninstall.sh
```

이 스크립트는 `/Applications/Menu Pulse.app`, `~/Applications/Menu Pulse.app`, 현대식 로그인 항목, 구형 LaunchAgent, `dev.hyunseop.MenuPulse` 설정, 캐시, 저장 상태, 전용 로그, 일치하는 macOS 진단 파일을 제거합니다. 진단 파일은 `DiagnosticReports`와 바로 아래 `Retired`에서 `MenuPulse` 또는 정확한 번들 ID 접두사이면서 확장자가 `.ips`, `.crash`, `.diag`, `.hang`, `.spin`인 파일만 삭제합니다. 앱을 삭제하기 전 정확한 번들 ID를 확인합니다.
과거 설치 경로를 확인할 권한이 없으면 잔존 로그인 항목을 성공으로 오인하지 않고 중단합니다.

## 개발 관련

### 프로젝트 구조

```text
Sources/MenuPulse/
  main.m
  MenuPulse.m
  SettingsWindowController.m
  Monitors.m
  RefreshScheduler.m
  SettingsStore.m
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
  analyze.sh
  release.sh
  verify-release.sh

Tests/
  MonitorTests.m
  MemoryUserDefaults.m
  SettingsSchedulerTests.m
  MenuPulseUITests.m
  LifecycleScriptTests.sh
```

### 스크립트

| Script | 용도 |
| --- | --- |
| `Scripts/build-app.sh` | Objective-C 소스를 빌드해서 `build/release/Menu Pulse.app`을 만듭니다. 개발 중 실행 확인에 사용합니다. |
| `Scripts/build-dmg.sh` | 앱을 다시 빌드한 뒤 `dist/MenuPulse.dmg`를 만듭니다. 배포용 파일을 확인할 때 사용합니다. |
| `Scripts/install.sh` | 앱을 `/Applications`에 안전하게 교체하고 정확히 일치하는 중복 앱을 제거한 뒤 로그인 실행을 등록합니다. |
| `Scripts/uninstall.sh` | 두 앱 위치, 로그인 항목, 설정, 캐시, 저장 상태, 전용 로그를 제거합니다. |
| `Scripts/measure.sh` | 격리된 프로세스로 CPU, 메모리, 앱/DMG 크기를 측정합니다. |
| `Scripts/analyze.sh` | 모든 Objective-C 소스에 Clang 정적 분석을 실행합니다. |
| `Scripts/test.sh` | 모니터, 설정/스케줄러, UI/접근성, 설치 수명주기 테스트를 실행합니다. |
| `Scripts/release.sh` | `main == origin/main`을 검증하고 빌드, 태그, 푸시, 게시 대기, 다운로드 검증을 수행합니다. |
| `Scripts/verify-release.sh` | GitHub Release를 다시 받아 SHA-256 체크섬과 DMG를 검증합니다. |
