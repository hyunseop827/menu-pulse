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

**Apple Silicon Mac 전용**으로, **핵심 기능** + **적은 리소스 사용량**이 컨셉입니다.
<table>
  <tr>
    <td align="center" width="50%">
      <strong>2행 메뉴바 표시</strong><br><br>
      <img src="menupulse-menu.png" alt="Menu Pulse 2행 메뉴바 표시" width="320">
    </td>
    <td align="center" width="50%">
      <strong>단순한 설정창</strong><br><br>
      <img src="menupulse-setting.png" alt="Menu Pulse 설정창" width="260">
    </td>
  </tr>
</table>

## 다운로드

[최신 DMG 다운로드](https://github.com/hyunseop827/menu-pulse/releases/latest/download/MenuPulse.dmg)

아직 Apple notarization은 안 되어 있어서 처음 실행할 때 macOS 경고가 뜰 수 있습니다.  
macOS가 막으면 아래를 실행하면 됩니다.

```zsh
xattr -dr com.apple.quarantine /Applications/MenuPulse.app
open /Applications/MenuPulse.app
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

온도는 IOHID를 먼저 읽고, 실패하면 SMC를 시도합니다.   
많은 Apple Silicon Mac에서 동작할 수 있지만, macOS 버전이나 기기 조합에 따라 항상 보장되지는 않습니다.  
온도를 읽지 못하면 `TEMP:--°C`처럼 표시됩니다.

기본 새로고침 주기:

```text
CPU  10s
RAM  10s
TEMP 30s
DISK 300s
```

각 항목의 새로고침 시간은 설정에서 따로 바꿀 수 있습니다.

## 가볍게 쓰기 위한 의도

MenuPulse는 기능이 많은 모니터링 앱이 아니라, 메뉴바에서 숫자만 작게 확인하는 앱입니다.

- Objective-C/AppKit 기반 네이티브 앱
- Electron, 웹뷰, 그래프 없음
- 히스토리 저장 및 대시보드 없음
- 실행해도 Dock에 아이콘이 뜨지 않음
- 설정으로 킨 값만 읽도록 설정
- 온도 표시를 꺼두면 센서도 읽지 않음
- 하나의 가벼운 타이머로 필요한 항목만 갱신

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
```

### 스크립트

| Script | 용도 |
| --- | --- |
| `Scripts/build-app.sh` | Objective-C 소스를 빌드해서 `build/release/MenuPulse.app`을 만듭니다. 개발 중 실행 확인에 사용합니다. |
| `Scripts/build-dmg.sh` | 앱을 다시 빌드한 뒤 `dist/MenuPulse.dmg`를 만듭니다. 배포용 파일을 확인할 때 사용합니다. |
| `Scripts/install.sh` | 앱을 `~/Applications`에 설치하고, Mac 로그인 시 자동으로 실행되도록 설정합니다. |
| `Scripts/uninstall.sh` | 설치된 앱과 로그인 자동 실행 설정을 제거합니다. |
| `Scripts/measure.sh` | 앱을 실행한 뒤 CPU, 메모리 사용량, 앱/DMG 크기를 짧게 측정합니다. |
| `Scripts/release.sh` | 버전을 입력하면 `Info.plist` 수정, DMG 빌드, commit, tag, push까지 처리합니다. |
