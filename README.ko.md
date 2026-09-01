# Menu Pulse

<p align="center">
  <img src="Packaging/AppIcon.png" alt="Menu Pulse 아이콘" width="96">
</p>

[English README](README.md)

대시보드나 기록 기능 없이 CPU, 메모리, 온도, 디스크 사용량을 메뉴바에서 확인하는 작은 네이티브 앱입니다.

**Apple Silicon · macOS 13 이상**

## 화면

<p align="center">
  <img src="menupulse-menubar.png" alt="Menu Pulse 메뉴바" width="292">
  <br>
  <img src="menupulse-setting.png" alt="Menu Pulse 설정창" width="480">
</p>

## 다운로드

[최신 DMG 다운로드](https://github.com/hyunseop827/menu-pulse/releases/latest/download/MenuPulse.dmg)

공개된 체크섬으로 다운로드 파일을 검증합니다.

```zsh
curl -LO https://github.com/hyunseop827/menu-pulse/releases/latest/download/MenuPulse.dmg
curl -LO https://github.com/hyunseop827/menu-pulse/releases/latest/download/SHA256SUMS.txt
shasum -a 256 -c SHA256SUMS.txt
```

이 저비용 빌드는 ad-hoc 서명을 사용하며 Apple 공증을 받지 않았습니다. 체크섬 확인 후 앱을 `/Applications`로 옮기고 Finder에서 우클릭하여 `열기`를 선택하세요. 그래도 macOS가 차단한다면 다음을 실행합니다.

```zsh
sudo xattr -dr com.apple.quarantine "/Applications/Menu Pulse.app"
open "/Applications/Menu Pulse.app"
```

## 기능

| 지표 | 기본 상태 | 갱신 주기 |
| --- | --- | --- |
| CPU | ON | 1초, 3초, 10초 — 기본 3초 |
| RAM | ON | CPU 주기 공유 |
| TEMP | OFF | 1초, 3초, 10초, 30초, 60초 — 기본 30초 |
| DISK | OFF | 1분, 3분, 5분, 10분 — 기본 5분 |

TEMP는 섭씨와 화씨를 지원하며 사용 가능한 센서 중 가장 높은 온도를 표시합니다. DISK는 홈 볼륨 사용량을 표시합니다.

설정창에는 로그인 시 시작, 기본값 초기화, 닫기, 프로그램 종료가 있습니다. 초기화와 종료는 확인창을 표시합니다. 앱을 직접 처음 실행하면 로그인 시작 여부를 한 번 묻고, 저장소 설치 스크립트는 자동으로 활성화합니다.

## 가벼움과 개인정보

- Objective-C/AppKit 네이티브 앱; Electron, 웹뷰, 그래프, Dock 아이콘 없음
- 단조 시계 기반 one-shot 타이머 하나로 활성화한 지표만 조회
- 네트워크 요청, 텔레메트리, 오류 보고 SDK, 기록, 지표 로그 없음
- 표시 설정, 갱신 주기, 온도 단위, 로그인 질문 완료 여부만 저장

M1 MacBook Air 16GB RAM, 256GB SSD에서 5분간 측정했습니다.

| 조건 | CPU 평균 | Private dirty |
| --- | ---: | ---: |
| 기본 CPU + RAM, 3초 | 0.065% | 9.8MB |
| 모든 지표 최단 주기 | 0.613% | 10.3MB |

최단 주기 조건은 CPU 목표 0.5%를 넘었지만 Private dirty 목표 15MB 이하는 충족했습니다.
TEMP 1초 설정은 센서 조회가 가장 많으므로 짧게 확인할 때 사용하는 것이 좋습니다.

## 완전 삭제

이 저장소에서 다음을 실행합니다.

```sh
Scripts/uninstall.sh
```

정확한 번들 ID를 검증한 뒤 두 설치 위치, 로그인 항목, 설정, 캐시, 저장 상태, 전용 로그, 일치하는 진단 파일을 제거합니다.

## 개발

```sh
Scripts/build-app.sh   # 앱 빌드
Scripts/test.sh        # 전체 테스트
Scripts/analyze.sh     # Clang 정적 분석
```

## 라이선스

[MIT](LICENSE) — 자유롭게 사용, 수정, 배포할 수 있으며 별도 보증은 제공하지 않습니다.
