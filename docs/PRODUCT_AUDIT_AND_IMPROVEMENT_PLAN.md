# PathShelf 제품 감사 및 개선 계획

- 감사 기준일: 2026-08-11
- 대상 버전: 감사 시작 시점의 `main` 기준선과 본 문서에 기록한 현재 개선 작업 트리
- 범위: 제품 포지셔닝, Swift/AppKit 아키텍처, 파일 접근 안전성, 테스트/운영 준비도, 네이티브 UI/접근성, 공개 경쟁 제품
- 근거 원칙: 코드와 공식 공개 자료로 확인한 사실과 제품 제안을 구분한다.

## 1. 한눈에 보는 결론

PathShelf는 **전역 단축키나 메뉴 막대에서 즉시 여는 로컬 전용 파일 패널**이다. Finder를 대체하거나 디스크 전체를 인덱싱하기보다 사용자가 명시적으로 선택한 위치를 빠르게 다시 여는 데 집중한다.

현재 MVP는 다음 기반이 강하다.

- Swift/AppKit 네이티브 구현
- 명확한 모듈 경계와 의존성 주입
- 보안 범위 bookmark와 상태 복구
- 휴지통 중심의 안전한 파일 작업
- 백엔드, 텔레메트리, 제3자 런타임 의존성 없음
- 실행 가능한 계약 테스트와 네이티브 smoke probe

반면 제품 완성도를 가로막는 핵심 문제도 분명하다.

1. 감사 기준선에는 큰 폴더에서 현재 목록을 즉시 좁힐 방법이 없었다. 현재 개선 작업 트리에서는 inline filter로 해결됐다.
2. path bar 이동이 Up 이동과 동일한 허용 루트 경계를 보장하지 않는다.
3. Favorite group 삭제가 두 저장소를 하나의 트랜잭션으로 다루지 않는다.
4. 첫 실행과 손상된 설정 복구가 사용자에게 명확히 드러나지 않는다.
5. 네이티브 닫기, 키보드, VoiceOver, loading/status 피드백이 일부 경로에서 일관되지 않다.
6. smoke/performance 검증 일부가 고정 시간과 로그 휴리스틱에 의존한다.

이번 개선의 첫 구현 단위인 **현재 위치 inline filter/search**는 현재 작업 트리에 완료됐다. 경쟁 제품 조사에서 공통으로 확인된 “즉시 접근” 수요를 직접 해결하면서, PathShelf의 강점인 명시적 위치·로컬 전용·비인덱싱 모델을 유지한다.

> 상태 표기: 4장의 문제 진술은 감사 시작 시점의 기준선 발견을 보존한다. 각 항목의 현재 해결 여부는 본문과 11장에서 별도로 표시한다.

## 2. 제품 특징

### 핵심 사용 흐름

1. 전역 단축키 또는 메뉴 막대 아이콘으로 패널을 연다.
2. Favorites 그룹 또는 현재 경로를 사용해 폴더를 탐색한다.
3. 파일을 열고, Quick Look으로 미리 보고, Finder에서 표시하거나 파일 작업을 수행한다.
4. Settings에서 패널 위치, 단축키, 기본 위치, 표시 열, 파일 접근을 구성한다.

근거:

- MVP 범위와 기능: `README.md:21-32`
- 로컬 전용 및 안전 기본값: `README.md:3-19`
- 제외 범위: `README.md:198`
- 주 화면과 계층: `DESIGN.md:7-48`

### 기술 구조

`Package.swift:23-84`는 다음 경계를 분리한다.

- `FileAccess`: bookmark, 열거, 보안 범위, 가시 디렉터리/볼륨 상태
- `FileOperations`: 복사, 이동, 교체, 휴지통, workspace action
- `PanelFeature`: 탐색 상태, Favorites, 정렬, 선택, preview 계약
- `SettingsFeature`: 설정 저장, 단축키, import/export
- `PreviewFeature`: thumbnail과 Quick Look 계약
- `AppShell`: AppKit 창, 테이블, 메뉴, Settings, 상태 표현
- 계약 실행기: `ContractTests`, `ServiceContractTests`, `PanelContractTests`, `EventContractTests`

`Sources/PanelFeature/FileBrowserModel.swift:125-165`는 파일 열거, bookmark, 저장소, 파일 작업, monitor, volume observer, preview를 주입받는다. 이 구조 덕분에 AppKit UI와 도메인 동작을 분리해 검증할 수 있다.

## 3. 장점

### 3.1 좁고 일관된 제품 포지셔닝

PathShelf는 Finder 대체, 원격 파일 관리자, 전체 디스크 검색기가 아니다. 사용자가 허용한 위치를 빠르게 다시 여는 패널이라는 역할이 분명하다.

이 범위는 다음 신뢰 이점으로 연결된다.

- 백엔드/계정 없이 작동
- 텔레메트리 없음
- 전체 디스크 인덱싱 없음
- Accessibility 또는 Screen Recording 권한 없이 전역 단축키 등록
- 외부 폴더는 security-scoped bookmark로 명시적 접근

### 3.2 모듈 경계와 테스트 가능성

앱 셸이 기능 모듈을 조립하고, 상태가 인터페이스를 통해 주입된다. UI를 띄우지 않아도 저장, 정렬, 탐색, 파일 작업, 이벤트 수명주기를 계약 테스트로 검증할 수 있다.

기준선 결과:

```text
ContractTests: 63 passed, 0 failed
ServiceContractTests: 15 passed, 0 failed
PanelContractTests: 24 passed, 0 failed
EventContractTests: 19 passed, 0 failed
```

자세한 실행 증거: `.omo/evidence/pathshelf-improvement/baseline/README.md`

### 3.3 안전한 파일 작업 기본값

- 디렉터리 열거는 cancellation-aware이며 detached 작업으로 수행된다: `Sources/FileAccess/DirectoryEnumerator.swift:33-55`
- 삭제는 영구 삭제가 아니라 Trash adapter를 사용한다: `Sources/FileOperations/FileOperationService.swift:315-321`
- 교체 중 부분 실패를 명시적으로 보고한다: `Sources/FileOperations/FileOperationService.swift:478-507`
- 충돌 기본 정책은 skip이며 테스트로 고정되어 있다.

### 3.4 bookmark 수명주기 처리

`Sources/FileAccess/SecurityScopedBookmarkService.swift:114-169`는 stale bookmark, 접근 불가, 권한 거부, 보안 범위 시작/종료를 구분한다. Favorites를 단순 문자열 경로로만 저장하는 도구보다 외부 위치 상태를 더 정확히 표현한다.

### 3.5 이벤트/teardown 계약

`Sources/EventContractTests/main.swift:9-27`은 monitor 교체, stale generation, burst coalescing, close 후 callback, volume event, teardown을 다룬다. smoke도 observer, timer, post-close callback이 0인지 검사한다.

### 3.6 기존 UI의 기본 계층은 타당함

- native `NSSplitView`
- sidebar material과 source-list Favorites
- 정렬 가능한 table header
- 중앙 empty/error 상태
- native `NSPathControl`
- 하단 path/status bar
- native Settings toolbar

기준선 실제 렌더: `.omo/evidence/pathshelf-improvement/baseline/panel-native-red.png`

파일 목록이 주 정보이고 Favorites와 상태가 보조 정보라는 기본 방향은 `DESIGN.md:34-48`과 일치한다.

## 4. 단점과 부족한 부분

심각도는 사용자 데이터/권한 경계, 복구 가능성, 핵심 작업 빈도, 접근성 순으로 평가했다.

### P1. path bar가 활성 허용 루트 밖으로 이동할 수 있음

확인된 코드 경계 차이다.

- `navigateUp()`은 활성 saved-location root를 넘지 못하게 한다: `Sources/PanelFeature/FileBrowserModel.swift:290-301`
- `navigateToPathBarLocation()`은 같은 경계 확인 없이 scope 전환을 시도한다: `:272-277`
- 대상이 어떤 saved location에도 속하지 않으면 helper가 성공으로 처리한다: `:939-952`
- 이후 현재 scope를 닫고 바깥 위치로 이동할 수 있다: `:1038-1049`

영향: 동일한 UI 안에서 Up과 path component 클릭이 서로 다른 접근 경계를 가진다.

개선: Up, path bar, history, 직접 folder activation이 하나의 `NavigationAccessPolicy`를 사용하게 한다.

검증: saved root의 상위 path component를 누르는 계약 테스트가 이동 거부와 기존 상태 보존을 확인해야 한다.

### P1. Favorite group 삭제가 두 저장소에 걸쳐 원자적이지 않음

`FileBrowserModel.removeFavoriteGroup()`은 saved locations와 favorite groups를 순서대로 저장한다. 두 번째 저장이 실패하면 첫 번째 저장을 되돌리지만 rollback 오류는 `try?`로 버린다: `Sources/PanelFeature/FileBrowserModel.swift:478-499`.

각 JSON 파일은 개별적으로 atomic write를 사용하지만, 두 파일을 묶은 트랜잭션은 아니다: `Sources/FileAccess/BookmarkStore.swift:34-48,78-84`.

영향: 실패 시 재실행 후 그룹과 Favorite 배치가 서로 모순될 수 있다.

개선 선택지:

1. settings/Favorites/groups를 하나의 versioned configuration 문서로 통합
2. journal 또는 two-phase commit과 결합 rollback 오류 도입

### P1/P2. 첫 실행과 손상된 설정 복구가 불명확함

- README는 first-run guidance를 언급한다: `README.md:31`
- 일반 시작은 패널을 열고, Settings 자동 노출은 smoke 경로에만 있다: `Sources/AppShell/PathShelfApp.swift:43-80`
- 설정 파일이 없으면 기본값을 저장하지만, 다른 load 오류도 사용자 안내 없이 기본값으로 바뀐다: `Sources/SettingsFeature/InvocationController.swift:386-394`
- decode 오류는 `SettingsStore.swift:24-30`에서 발생한다.

필요한 상태:

- 진짜 첫 실행
- 정상 기본값
- 이전 버전 migration
- malformed/corrupt 설정
- 복구 완료 또는 복구 실패

손상 파일은 보존/이름 변경하고 Settings에서 복구 결과와 다음 행동을 보여야 한다.

### P1. 현재 폴더를 빠르게 좁힐 검색/필터가 없음 — 기준선 발견, 현재 해결

기준선 AppKit 렌더와 smoke의 `toolbarControlCount=0`에서 확인된다. 항목이 100개 이상인 기존 스크린샷에서도 사용자는 정렬이나 스크롤만 사용할 수 있다.

영향:

- 정확한 이름 일부를 알아도 목록을 훑어야 함
- Favorites로 위치를 줄인 뒤에도 큰 폴더의 retrieval 비용이 큼
- Raycast/Alfred가 제공하는 즉시 query 기대에 못 미침

개선 원칙:

- 현재 로드된 위치 안에서만 filter
- 인덱싱 없음
- 파일명 중심, locale-aware 대소문자 비구분 비교
- 원본 directory snapshot을 보존해 query를 지우면 즉시 복원
- result count와 no-result 상태 표시
- Esc 또는 clear button으로 원래 목록 복원

현재 상태: 모델 snapshot/filter 계약, native `NSSearchField`, result count, no-result 상태, Command-F, Escape clear, 접근성 probe, fresh AppKit 캡처까지 구현·검증됐다.

### P1. 네이티브 닫기와 키보드 접근 경로가 일관되지 않음

- `FloatingPanelController.hide()`는 `prepareForHide()`, Quick Look 종료, model teardown, visibility 동기화를 수행한다.
- panel은 `.closable`이지만 red close button을 같은 경로로 보내는 delegate가 없다.
- `KeyHandlingTableView`는 Return을 소비하지만 handler가 nil이면 `super`로 전달하지 않는다: `Sources/AppShell/PanelSupportViews.swift:191-203`
- file table만 Return handler가 있고 Favorites sidebar에는 없다: `Sources/AppShell/PanelContentView+Setup.swift:6-11`

개선: red close, Escape, Command-W를 idempotent teardown으로 통합하고 sidebar Return으로 선택 Favorite을 연다.

### P1/P2. custom row의 VoiceOver 의미가 불완전함

- disclosure button은 빈 title과 tooltip만 가진다: `Sources/AppShell/SavedLocationTableDataSource.swift:88-105`
- unavailable Favorite만 결합 accessibility label을 가진다: `:156-194`
- healthy Favorite, group expanded/collapsed 상태, custom file row의 명시적 이름/값이 부족하다.

개선: group/disclosure/Favorite/file row 각각의 role, label, value, expanded state, availability를 노출한다.

### P2. loading과 status 피드백이 약함

- model은 loading을 추적하지만 AppShell은 loading 동안 state view를 숨긴다: `Sources/AppShell/PanelContentView+Refresh.swift:23-27`
- footer는 긴 오류를 tail truncate한다.
- panel과 Settings의 일부 성공/실패 경로는 기존 announcement helper를 우회한다.

개선: `Loading…`과 native progress를 기존 state view에 표시하고, 모든 결과를 tooltip+VoiceOver announcement가 있는 한 helper로 보낸다.

### P2. Favorites 첫 사용 발견성이 낮음

빈 sidebar에는 눈에 보이는 Add Favorite/New Group action이 없다. 이 action은 빈 영역 context menu에만 있다.

개선: Favorites가 비어 있을 때만 작은 `+` 또는 action row를 보이고, 내용이 생기면 시각적 잡음을 줄인다.

### P2. Settings 상태와 반응형 레이아웃이 부족함

- Apply Changes가 항상 활성
- 저장되지 않은 변경과 저장 상태를 구분하지 않음
- 닫을 때 discard 확인 없음
- modifier 4개를 한 줄에 강제해 `Command`가 `Com…`으로 잘림
- 고정 pane 폭과 비스크롤 구조가 큰 글자에서 취약함

실제 근거: `docs/images/settings-shortcut.png`

개선:

- clean일 때 Apply 비활성
- dirty close 시 native discard 확인
- modifier를 2열/2행 또는 wrapping layout으로 변경
- standard text style과 scroll/content-driven size 사용

### P2. smoke/performance 검증이 timing과 휴리스틱에 의존함

- `BuildSupport/smoke-launch.sh`는 fixed wait, process liveness, log marker를 사용한다.
- Quick Look probe는 200ms sleep을 사용한다.
- smoke 경로에서 초기 load와 smoke action load가 중복될 여지가 있다.

개선: panel/preview readiness event를 구독하고 cancellation 완료를 await한 뒤 teardown을 검사한다.

### P2. observer lifecycle 외부 API의 동시 호출 계약이 불분명함

`VisibleDirectoryMonitor.replaceRoot/stop`과 `VolumeEventObserver.start/stop`은 내부 상태를 잠그지만 외부 stream stop/start 구간 전체를 serialize하지 않는다.

현재 model의 main-actor 사용은 위험을 낮추지만, API가 thread-safe처럼 보이는 만큼 barrier-controlled concurrent test 또는 actor/locked state machine이 필요하다.

## 5. 경쟁 제품과 기회

모든 링크는 2026-08-11에 공식 공개 페이지에서 확인했다. “기회”는 PathShelf에 대한 분석이며 경쟁사가 직접 인정한 결함이 아니다.

| 제품 | 공식 근거 | 확인된 핵심 기능 | PathShelf에 주는 신호 |
|---|---|---|---|
| [Raycast](https://manual.raycast.com/file-search) | Raycast Manual | filename/path 검색, metadata, recent files, Finder action, Home/Applications 인덱싱 | 전체 디스크 검색보다 명시적 위치 안의 live filter로 차별화 |
| [Alfred](https://www.alfredapp.com/help/workflows/inputs/file-filter/) | Alfred Help | file type/location scope, query field, sort, keyword/hotkey, result limit | workflow 설정 없이 열린 폴더를 바로 좁히는 경험이 기회 |
| [Default Folder X](https://www.stclairsoft.com/DefaultFolderX/) | 제품 페이지와 [FAQ](https://www.stclairsoft.com/DefaultFolderX/faq.html) | hierarchical folder, recent/favorite, Quick Search, Open/Save dialog 연동 | 독립 패널과 비침습 권한 모델을 유지 |
| [Dropover](https://dropoverapp.com/) | 제품 페이지와 [FAQ](https://dropoverapp.com/faq) | keyboard/recent/pinned/menu-bar temporary shelf | 즉시 열고 임시로 모으는 흐름은 후속 기회. 무료 모드의 3초 지연 없이 예측 가능해야 함 |
| [Yoink](https://eternalstorms.at/yoink/mac/) | 공식 제품 페이지 | drag-in, 자유 이동, drag-out, Quick Action/Share/Handoff/Terminal 연동 | 작은 native extension point가 가치 있음. iOS 연속성은 별도 앱 필요 |
| [Unclutter](https://unclutterapp.com/panels/files/) | Files 페이지와 [공식 sync FAQ](https://unclutterapp.com/blog/2022/06/02/faq-how-to-change-storage-folder-for-unclutter-files-and-notes-sync-between-devices/) | 상단 gesture로 여는 temporary file drop zone | drop shelf 수요 확인. sync FAQ는 2022년 자료라 현재성은 약함 |
| [ForkLift](https://binarynights.com/) | 공식 제품 페이지 | dual pane, remote/cloud, archive, remote edit, search/filter | connector breadth와 dual pane은 성숙 시장. PathShelf의 첫 차별점으로는 부적합 |
| [Path Finder](https://cocoatech.com/product/path-finder-10/) | 공식 legacy 페이지 | macOS file manager | 페이지가 `NOT AVAILABLE FOR PURCHASE – OLD VERSION`으로 표시됨. 현재 기능 주장은 제외하고 유지보수/문서 신뢰만 참고 |
| [QSpace](https://qspace.awehunt.com/en-us/) | 공식 제품 페이지 | archive browsing, FTP/SFTP/WebDAV/cloud/S3 등 | 원격/다중 pane은 기대 기능이지만 현재 local-only 범위와 충돌 |

## 6. 추가 기회 우선순위

평가 축:

- 사용자 가치: 자주 발생하는 핵심 작업 시간을 줄이는가
- 차별화: 이미 강한 경쟁 분야를 그대로 따라 하지 않는가
- 구현 적합도: 현재 모듈과 신뢰 모델을 유지하는가
- 위험: 권한, 데이터 일관성, 새로운 상태 복잡도를 얼마나 만드는가

점수는 5점 만점이며 상대 비교다.

| 순위 | 기회 | 사용자 가치 | 차별화 | 구현 적합도 | 위험 | 결정 |
|---:|---|---:|---:|---:|---:|---|
| 1 | 현재 위치 inline filter/search | 5 | 4 | 5 | 1 | 이번 개선에서 구현 |
| 2 | Favorites first-use action + keyboard/VoiceOver | 4 | 4 | 5 | 1 | 근접 UI 개선 후보 |
| 3 | path navigation authorization 통합 | 5 | 3 | 5 | 2 | 최우선 correctness 후속 |
| 4 | startup/corrupt-settings recovery | 4 | 4 | 4 | 2 | 다음 제품 완성도 단계 |
| 5 | temporary drag shelf | 4 | 4 | 2 | 4 | 별도 discovery/설계 후 |
| 6 | command/action palette | 3 | 3 | 3 | 2 | search 사용 데이터 후 |
| 7 | remote/cloud connectors | 3 | 1 | 1 | 5 | 현재 범위에서 제외 |
| 8 | built-in cross-device sync | 3 | 2 | 1 | 5 | local-only 원칙과 충돌, 제외 |

## 7. 개선 계획

### 단계 A — 즉시 탐색성과 명료성 (완료)

목표: 현재 폴더에서 원하는 파일을 1~2초 안에 좁힌다.

작업:

1. `FileBrowserModel`에 원본 directory item snapshot과 filter query를 둔다.
2. query 변경 시 filename을 locale-aware, case-insensitive 방식으로 filter한다.
3. 정렬은 filter 후에도 기존 sort order를 유지한다.
4. query를 지우면 원본 목록과 유효한 선택을 복원한다.
5. panel 상단에 native search field를 배치한다.
6. 결과 수와 no-result state를 표시한다.
7. search field, clear action, result feedback에 accessibility label/value를 제공한다.
8. 계약 테스트와 smoke probe로 filter/clear/회귀를 검증한다.

완료 조건:

- query가 일치 항목만 보임
- clear가 전체 항목을 즉시 복원
- empty directory와 no-match가 서로 다른 상태
- directory navigation/refresh 후 query 정책이 일관됨
- 기존 정렬, 선택, 탐색 계약이 유지됨

### 단계 B — 접근성과 상태 피드백

목표: pointer 없이 핵심 흐름을 완료하고 상태를 즉시 이해한다.

작업:

- sidebar Return activation
- disclosure expanded/collapsed accessibility
- healthy/unavailable Favorite row label
- visible loading state
- panel/Settings status helper 통합
- shortcut modifier wrapping
- native close/Escape/Command-W teardown 통합

### 단계 C — correctness와 복구

목표: 권한과 영속성 실패가 사용자 상태를 깨뜨리지 않게 한다.

작업:

- 하나의 navigation authorization policy
- path bar/history/direct activation 경계 테스트
- Favorite group delete transaction
- corrupt settings 보존과 recovery UI
- first-run state와 normal default 분리

### 단계 D — 검증 신뢰성

목표: 시간 운에 의존하지 않는 단일 실행 검증.

작업:

- readiness signal 기반 smoke
- Quick Look event await
- observer stop 완료 await
- barrier-controlled lifecycle concurrency tests
- smoke fixture와 결과 artifact cleanup 자동 검증

### 단계 E — 새 제품 행동 탐색

temporary drag shelf는 별도 설계가 필요하다.

검토할 질문:

- 영구 Favorites와 임시 shelf의 mental model을 어떻게 분리할지
- drag source/destination과 sandbox 권한을 어떻게 표현할지
- 재실행 후 shelf를 복원할지
- Finder/Share extension을 추가할 가치가 있는지
- local-only 원칙을 유지하면서 연속성을 어떻게 제공할지

이 단계는 inline filter와 correctness/accessibility 개선의 실제 사용 결과를 본 뒤 결정한다.

## 8. UI 방향

목표는 “새로운 장식”이 아니라 **더 빠른 시각 해석**이다.

### 유지할 것

- Finder와 유사한 native table/sidebar 어휘
- file list가 가장 큰 면적을 차지하는 계층
- macOS semantic colors/material
- 28pt row density
- path bar와 concise status
- 시스템 symbol과 표준 focus ring

### 바꿀 것

- 검색을 file list 바로 위 한 줄에 배치
- search field는 과도한 hero 요소가 아니라 compact native control로 유지
- 검색 중 `n of m` 결과를 한 위치에서 보여 줌
- no-result는 magnifying glass symbol, 짧은 제목, clear 안내로 표현
- loading/empty/error/no-result를 같은 state primitive로 구분
- opacity가 낮은 장식, 불필요한 card, gradient, animation은 추가하지 않음
- keyboard와 VoiceOver 상태를 시각 상태와 같은 수준으로 구현

### 시각적 성공 기준

- 1초 안에 현재 위치, 검색 상태, 결과 수를 식별
- 파일명 열이 항상 최우선
- sidebar, list, footer가 서로 경쟁하지 않음
- minimum window에서도 검색, Name, path, status가 잘리지 않음
- dark mode, Increase Contrast, larger text에서도 의미가 유지됨

## 9. 검증 계획

### 자동 계약

```sh
swift run PanelContractTests
bash BuildSupport/test.sh
```

추가 시나리오:

- `filterQueryNarrowsVisibleItems`
- `clearingFilterRestoresDirectoryItems`
- query 중 정렬/선택 회귀
- directory 변경 시 query 상태

### 빌드와 native smoke

```sh
bash BuildSupport/build-app.sh
bash BuildSupport/smoke-launch.sh
```

필수 machine-readable 상태:

- search control ready
- filter narrows fixture
- clear restores fixture
- no-result state ready
- accessibility labels ready
- observer/timer/post-close callback 0

### 실제 표면

현재 세션은 WindowServer 외부 캡처 권한을 제공하지 않아 `screencapture`가 전면 검정으로 실패했다. 대신 같은 실행 AppKit 프로세스의 `NSView.cacheDisplay` smoke-only hook으로 fresh PNG를 생성한다.

캡처 대상:

- panel resting state
- active query
- no-result state
- cleared query
- Settings General/Shortcut/Browser/Access

각 캡처는 source 변경 이후 다시 생성하고, PNG signature와 dimensions를 확인한 뒤 독립 visual QA에 전달한다.

## 10. 범위 밖 결정

이번 개선에서 하지 않는다.

- 백엔드 sync
- 계정/인증
- 원격/cloud connector
- 영구 삭제
- 전체 디스크 content index
- Finder 대체 multi-pane
- 새 제3자 런타임 의존성
- 장식 목적 animation

이 결정은 구현을 작게 만들기 위한 임시 생략이 아니라 PathShelf의 현재 제품 원칙을 지키기 위한 우선순위다.

## 11. 현재 개선 상태

2026-08-11 기준:

- 단계 A inline filter/search: 완료
- filter/clear/loading 계약: `PanelContractTests` 27/27 PASS
- native search/no-result/loading/clear surface: smoke PASS
- Command-F와 Escape clear: 실제 AppKit key event probe PASS
- 검색·result status·no-result state 접근성 값: smoke PASS
- Shortcut modifier `NSGridView`: full-label/column-alignment capture PASS
- Settings Access 용어: `Choose Accessible Folder…`, `Show This App in Finder`로 `DESIGN.md`와 일치
- 남은 P1/P2 항목: path authorization 통합, Favorite transaction, startup recovery, timing 기반 smoke 제거
