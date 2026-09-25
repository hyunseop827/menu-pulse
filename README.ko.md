# Menu Pulse

<p align="center">
  <img src="Packaging/AppIcon.png" alt="Menu Pulse 아이콘" width="96">
</p>

[English README](README.md)

CPU와 RAM 사용량을 Mac 메뉴바에서 한눈에 확인하는 작은 앱입니다. 온도와 디스크 사용량은 필요할 때 켤 수 있습니다.

<p align="center">
  <img src="menupulse-menubar.png" alt="Menu Pulse 기본 CPU·RAM 표시" width="88">
</p>

## 다운로드

**[최신 DMG 다운로드](https://github.com/hyunseop827/menu-pulse/releases/latest/download/MenuPulse.dmg)** · 무료 · Apple Silicon · macOS 13 이상

DMG를 열고 **Menu Pulse**를 **응용 프로그램**으로 드래그합니다. 업데이트할 때는 기존 앱을 종료하고 새 DMG의 앱으로 교체합니다. 앱을 사용하기 위해 이 저장소를 내려받거나 보관할 필요는 없습니다.

**앱은 ad-hoc 서명을 사용하며 Apple 공증을 받지 않았습니다.** 처음 실행할 때 macOS가 차단하면 실행을 시도한 뒤 **시스템 설정 → 개인정보 보호 및 보안 → 그래도 열기**를 선택하세요. [Apple 안내](https://support.apple.com/ko-kr/guide/mac-help/mh40616/mac)를 참고할 수 있습니다.

버전별 변경 내용은 [릴리스 노트](https://github.com/hyunseop827/menu-pulse/releases)에서 확인하세요.

<details>
<summary>다운로드 체크섬 검증</summary>

```zsh
curl -LO https://github.com/hyunseop827/menu-pulse/releases/latest/download/MenuPulse.dmg
curl -LO https://github.com/hyunseop827/menu-pulse/releases/latest/download/SHA256SUMS.txt
shasum -a 256 -c SHA256SUMS.txt
```

</details>

## 기능

| 지표 | 기본 상태 | 갱신 주기 |
| --- | --- | --- |
| CPU | ON | 1초, 3초, 10초 — 기본 3초 |
| RAM | ON | CPU 주기 공유 |
| TEMP | OFF | 1초, 3초, 10초, 30초, 60초 — 기본 30초 |
| DISK | OFF | 1분, 3분, 5분, 10분 — 기본 5분 |

지표를 한두 개 켜면 한 줄에 하나씩 표시합니다. 세 개 이상이면 CPU·RAM은 왼쪽, TEMP·DISK는 오른쪽 열에 표시합니다.

<p align="center">
  <img src="menupulse-menubar-all.png" alt="Menu Pulse의 CPU·RAM·TEMP·DISK 표시" width="169">
</p>

TEMP는 섭씨와 화씨를 지원하며 앱에서 읽을 수 있는 부품 센서 중 가장 높은 온도를 표시합니다. 배터리와 보정용 센서는 제외합니다. Mac 기종과 macOS 버전에 따라 센서를 읽지 못할 수 있으며, 실패하면 `--`를 표시하고 5분마다 재시도합니다. DISK는 홈 볼륨 사용량을 표시하며, Finder와 같이 시스템이 비울 수 있는 공간도 사용 가능한 공간으로 계산합니다. 남은 디스크 공간과 TEMP 상태 같은 자세한 내용은 메뉴바 항목에 마우스를 올리면 확인할 수 있습니다.

메뉴바 항목을 클릭하면 설정창이 열리며, 설치된 버전과 GitHub 최신 릴리스 링크를 확인할 수 있습니다. 설정창은 **⌘W** 또는 **Esc**로 닫을 수 있고, 다시 열면 마지막 위치에 표시됩니다. 처음 실행하면 로그인 시작 여부를 한 번 묻고, 이후 설정에서 변경할 수 있습니다. **기본값 초기화는 지표 설정을 기본값으로 되돌리고 로그인 시 시작을 켭니다.** 초기화와 종료는 확인창을 표시하며, 종료해도 로그인 설정은 유지됩니다.

<details>
<summary>설정 화면 보기</summary>

<p align="center">
  <img src="menupulse-setting.png" alt="Menu Pulse 설정창" width="480">
</p>

</details>

## 자원 사용과 개인정보

- Objective-C/AppKit 네이티브 앱; Electron, 웹뷰, 그래프, Dock 아이콘 없음
- 타이머 하나로 활성화한 지표만 조회하며 화면이 꺼져 있거나 다른 사용자 세션이 활성화된 동안 정기 조회 중단
- 백그라운드 네트워크 요청, 텔레메트리, 오류 보고 SDK, 기록, 지표 로그 없음; 릴리스 링크는 클릭할 때 브라우저에서 열림
- 표시 설정, 갱신 주기, 온도 단위, 설정창과 메뉴바 항목 위치, 로그인 질문 완료 여부만 저장

자원 사용량은 Mac 기종, macOS 버전, 활성화한 지표와 갱신 주기에 따라 달라집니다. TEMP 1초 설정은 센서 조회가 가장 많으므로 짧게 확인할 때 사용하는 것이 좋습니다. 특정 체크아웃의 측정 조건과 결과를 남기려면 [벤치마크](#벤치마크)를 참고하세요.

## 삭제

앱 설정에서 **로그인 시 시작**을 끄고 **프로그램 종료**를 선택한 뒤, `/Applications/Menu Pulse.app`을 휴지통으로 옮깁니다.

## 개발

```sh
make app      # build/release에 앱 빌드
make check    # 문법·메타데이터·정적 분석·테스트·앱 검증
make dmg      # dist/MenuPulse.dmg와 SHA256SUMS.txt 생성
```

Xcode Command Line Tools가 필요합니다. 빌드·테스트는 앱 설치나 로그인 항목 등록을 하지 않습니다. 테스트 실행 파일은 임시 폴더에서 실행한 뒤 정리합니다.

<details>
<summary>이전 개발 빌드의 로그인 항목 정리</summary>

이전 개발 과정에서 등록된 `MenuPulseUITests`나 삭제한 앱이 자동 실행 목록에 남아 있다면 **시스템 설정 → 일반 → 로그인 항목 및 확장 프로그램 → 로그인 시 열기**에서 제거합니다. 저장소 파일을 지우는 것만으로 기존 로그인 등록이 해제되지는 않습니다.

</details>

## 벤치마크

Xcode Command Line Tools가 필요합니다. 현재 체크아웃을 별도 앱 식별자로 빌드해 측정하며, 다운로드한 릴리스 DMG를 직접 측정하지는 않습니다.

```sh
# 기본값: CPU + RAM 3초마다; 준비 30초 + 측정 5분
Scripts/benchmark.sh

# 모든 지표를 최단 주기로 조회
ALL_METRICS=1 CPU_RAM_REFRESH_INTERVAL=1 TEMPERATURE_REFRESH_INTERVAL=1 \
  DISK_REFRESH_INTERVAL=60 Scripts/benchmark.sh
```

화면을 켠 상태에서 측정하세요. 실행할 때마다 새 `build/benchmarks/run-…/` 폴더에 측정 조건과 원자료를 저장합니다.

- `report.txt`: 빌드·기기·측정 조건과 결과 요약
- `samples.txt`: `ps`로 수집한 CPU·RSS 표본
- `vmmap.txt`: 마지막 메모리 조회 결과, 조회 가능한 경우 저장
- `app.log`: 측정한 앱의 출력

저장할 상위 폴더는 `RESULTS_DIR`로 바꿀 수 있습니다. 스크립트가 실행되는지만 짧게 확인하려면 `WARMUP=0 DURATION=10 Scripts/benchmark.sh`를 사용하고, 비교할 때는 충분한 시간 동안 반복 측정하세요.

CPU 결과는 `ps` 값을 요약한 것입니다. 이 값은 최대 1분의 감쇠 평균이며, 서로 독립적인 1초 구간 측정값은 아닙니다. RSS와 Private dirty는 서로 다른 메모리 지표로 MiB 단위로 구분해 표시하며, Private dirty는 총 메모리 사용량이 아닙니다. 같은 기기·macOS·활성 지표·갱신 주기에서 얻은 결과끼리 비교하세요.

종료 시 임시 빌드·설정과 측정 프로세스는 정리하고 결과는 보존합니다. 설치된 앱의 설정과 로그인 등록은 공유하지 않습니다.

## 라이선스

[MIT](LICENSE) — 자유롭게 사용, 수정, 배포할 수 있으며 별도 보증은 제공하지 않습니다.
