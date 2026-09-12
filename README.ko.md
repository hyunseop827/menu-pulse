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

버전별 변경 내용은 [릴리스 노트](https://github.com/hyunseop827/menu-pulse/releases)에서 확인하세요.

공개된 체크섬으로 다운로드 파일을 검증합니다.

```zsh
curl -LO https://github.com/hyunseop827/menu-pulse/releases/latest/download/MenuPulse.dmg
curl -LO https://github.com/hyunseop827/menu-pulse/releases/latest/download/SHA256SUMS.txt
shasum -a 256 -c SHA256SUMS.txt
```

DMG를 열고 앱을 `/Applications`로 복사합니다. 업데이트할 때는 기존 앱을 종료하고 새 DMG의 앱으로 교체합니다. 설치된 앱은 이 저장소 없이 실행됩니다.

앱은 ad-hoc 서명을 사용하며 Apple 공증을 받지 않았습니다. 처음 실행할 때 macOS가 차단하면 실행을 시도한 뒤 **시스템 설정 → 개인정보 보호 및 보안 → 그래도 열기**를 선택하세요. [Apple 안내](https://support.apple.com/ko-kr/guide/mac-help/mh40616/mac)를 참고할 수 있습니다.

## 기능

| 지표 | 기본 상태 | 갱신 주기 |
| --- | --- | --- |
| CPU | ON | 1초, 3초, 10초 — 기본 3초 |
| RAM | ON | CPU 주기 공유 |
| TEMP | OFF | 1초, 3초, 10초, 30초, 60초 — 기본 30초 |
| DISK | OFF | 1분, 3분, 5분, 10분 — 기본 5분 |

TEMP는 섭씨와 화씨를 지원하며 앱에서 읽을 수 있는 센서 중 가장 높은 온도를 표시합니다. Mac 기종과 macOS 버전에 따라 센서를 읽지 못할 수 있으며, 실패하면 `--`를 표시하고 5분 후 재시도합니다. TEMP 상태는 메뉴바 항목에 마우스를 올리면 확인할 수 있습니다. DISK는 홈 볼륨 사용량을 표시합니다.

설정창에서 설치된 버전과 GitHub 최신 릴리스 링크를 확인할 수 있습니다. 처음 실행하면 로그인 시작 여부를 한 번 묻고, 이후 설정에서 변경할 수 있습니다. **기본값 초기화는 지표 설정을 기본값으로 되돌리고 로그인 시 시작을 켭니다.** 초기화와 종료는 확인창을 표시하며, 종료해도 로그인 설정은 유지됩니다.

## 가벼움과 개인정보

- Objective-C/AppKit 네이티브 앱; Electron, 웹뷰, 그래프, Dock 아이콘 없음
- 타이머 하나로 활성화한 지표만 조회하며 화면이 꺼진 동안 정기 조회 중단
- 백그라운드 네트워크 요청, 텔레메트리, 오류 보고 SDK, 기록, 지표 로그 없음; 릴리스 링크는 클릭할 때 브라우저에서 열림
- 표시 설정, 갱신 주기, 온도 단위, 로그인 질문 완료 여부만 저장

아래는 M1 MacBook Air 16GB RAM, 256GB SSD에서 5분간 측정한 과거 기록입니다. 당시 앱 버전과 macOS 버전이 기록되지 않아 참고용으로 남기며, 현재 코드의 측정값은 아닙니다.

| 조건 | CPU 평균 | Private dirty |
| --- | ---: | ---: |
| 기본 CPU + RAM, 3초 | 0.065% | 9.8MB |
| 모든 지표 최단 주기 | 0.613% | 10.3MB |

TEMP 1초 설정은 센서 조회가 가장 많으므로 짧게 확인할 때 사용하는 것이 좋습니다.

## 삭제

앱 설정에서 **로그인 시 시작**을 끄고 **프로그램 종료**를 선택한 뒤, `/Applications/Menu Pulse.app`을 휴지통으로 옮깁니다.

이전 개발 과정에서 등록된 `MenuPulseUITests`나 삭제한 앱이 자동 실행 목록에 남아 있다면 **시스템 설정 → 일반 → 로그인 항목 및 확장 프로그램 → 로그인 시 열기**에서 제거합니다. 저장소 파일을 지우는 것만으로 기존 로그인 등록이 해제되지는 않습니다.

## 개발

```sh
make app      # build/release에 앱 빌드
make check    # 문법·메타데이터·정적 분석·테스트·앱 검증
make dmg      # dist/MenuPulse.dmg와 SHA256SUMS.txt 생성
```

Xcode Command Line Tools가 필요합니다. 빌드·테스트는 앱 설치나 로그인 항목 등록을 하지 않습니다. 테스트 실행 파일은 임시 폴더에서 실행한 뒤 정리합니다.

## 벤치마크

```sh
# 기본값: CPU + RAM 3초마다; 준비 30초 + 측정 5분
Scripts/benchmark.sh

# 모든 지표를 최단 주기로 조회
ALL_METRICS=1 CPU_RAM_REFRESH_INTERVAL=1 TEMPERATURE_REFRESH_INTERVAL=1 \
  DISK_REFRESH_INTERVAL=60 Scripts/benchmark.sh
```

화면을 켠 상태에서 측정하세요. `ps`로 수집한 CPU·RSS의 평균·최댓값과, 가능한 경우 마지막 `vmmap` 조회의 Private dirty를 출력합니다. 결과를 비교할 때는 커밋과 macOS 버전도 기록하세요. 짧게 확인하려면 `WARMUP=0 DURATION=10 Scripts/benchmark.sh`를 사용합니다.

별도 앱 식별자와 임시 빌드·설정을 사용하며, 종료 시 측정 프로세스와 임시 파일을 정리합니다. 설치된 앱의 설정과 로그인 등록을 공유하지 않습니다.

## 라이선스

[MIT](LICENSE) — 자유롭게 사용, 수정, 배포할 수 있으며 별도 보증은 제공하지 않습니다.
