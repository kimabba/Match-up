# Web Admin / App User Separation Design

## Summary

Flutter Web 빌드를 어드민 전용 대시보드로 사용하고, 모바일 앱은 일반 사용자 전용으로 분리한다.

## Motivation

- 스토어 심사에 어드민 기능 노출 방지
- 어드민 작업(대회 승인, 크롤 현황, 데이터 편집)은 PC 브라우저가 적합
- 앱 UX를 사용자 동선에만 집중

## Design Decisions

| 결정 | 선택 | 대안 |
|------|------|------|
| 분리 방식 | 라우터 분기 (방식 A) | _MainShell 내부 분기, 별도 엔트리포인트 |
| 웹 레이아웃 | 사이드바 + 탑바 조합 | 사이드바만, 탑 네비게이션 |
| 비어드민 웹 접속 | 로그인 화면 + "관리자 권한 필요" 안내 | 읽기 전용 허용, 앱 다운로드 랜딩 |
| 랜딩페이지 | 지금은 로그인 화면만 (스토어 출시 후 제작) | 즉시 랜딩페이지 제작 |
| 추가 기능 | 기존 5탭 + 대회 수기 편집 | 5탭 그대로, 사용자 관리 포함 |

## Step 1: Web Build Unblock (JY-21)

### Problem

`notifications.dart`가 `dart:io`의 `Platform.isIOS/isAndroid`를 사용.
`main.dart`에서 무조건 import되어 `flutter build web` 컴파일 실패.

### Solution

speed_gun과 동일한 conditional import 패턴:

```
app/lib/services/
  notifications.dart       (기존 모바일 구현, dart:io 유지)
  notifications_web.dart   (신규 no-op stub, dart:io 없음)
```

`main.dart`에서:

```dart
import 'services/notifications.dart'
    if (dart.library.html) 'services/notifications_web.dart';
```

`notifications_web.dart`는 동일 함수 시그니처로 no-op 반환 (웹에서 FCM 불필요).

## Step 2: Router Branching

### Web Redirect Flow

```
비로그인          -> /login
로그인 + 비어드민  -> /no-access ("관리자 권한 필요" + 로그아웃)
로그인 + 어드민    -> /admin (AdminShell)
```

### App Redirect Flow

기존 그대로 유지 (변경 없음).

### Route Tree Changes

```
// 웹 전용
/no-access          -> NoAccessScreen

// /admin을 ShellRoute 밖으로 이동, AdminShell로 감싸기
AdminShellRoute:
  /admin             -> 대시보드 (크롤 현황 요약)
  /admin/drafts      -> Draft 승인
  /admin/sources     -> 크롤 소스
  /admin/clubs       -> 클럽 승인
  /admin/kb          -> 지식베이스
  /admin/edit/:id    -> 대회 수기 편집 (신규)
```

기존 AdminScreen의 5탭 위젯을 개별 라우트에서 재사용.

## Step 3: AdminShell Layout

```
+--------------------------------------------------+
|  Match-up Admin              [ssfak] [로그아웃]    |  <- TopBar
+----------+---------------------------------------+
| 대시보드  |                                       |
| Draft    |         콘텐츠 영역                     |
| 크롤소스  |      (각 라우트의 위젯)                  |
| 클럽승인  |                                       |
| 지식베이스 |                                       |
| 대회편집  |                                       |
+----------+---------------------------------------+
```

- `Scaffold` + `Row`: 왼쪽 `NavigationRail` 또는 커스텀 사이드바, 오른쪽 `Expanded(child: child)`
- 사이드바 너비: 고정 220px
- 반응형 불필요 (어드민은 PC 전용)

## Step 4: Tournament Edit Screen

`/admin/edit/:id` 라우트. tournaments 테이블 직접 수정.

### Editable Fields

- description
- location
- application_deadline
- eligible_grades (division_codes 선택 UI)
- status (draft/published)

### Behavior

- Supabase client로 직접 update (service_role 불필요, RLS admin 정책 활용)
- 저장 시 `embedding = null` 설정하여 embed-pending이 재임베딩
- 크롤러 재크롤 시 덮어쓰기 방지: description이 수동 편집되었으면 크롤러가 skip

### Crawl Overwrite Protection

`upsertTournament`의 기존 로직 활용:
- 파서가 `description = undefined` 반환 시 기존 값 유지 (이미 구현됨)
- 구조화된 description(파서 생성)과 수동 편집 description 구분 필요 시,
  `manual_edit` boolean 컬럼 추가 검토 (MVP에서는 파서가 항상 description을 반환하므로 불필요할 수 있음)

## File Changes

### New Files (4)

| File | Role |
|------|------|
| `app/lib/services/notifications_web.dart` | FCM no-op stub for web |
| `app/lib/screens/admin/admin_shell.dart` | Sidebar + TopBar layout |
| `app/lib/screens/admin/no_access_screen.dart` | Non-admin web access notice |
| `app/lib/screens/admin/tournament_edit_screen.dart` | Tournament manual edit |

### Modified Files (3)

| File | Change |
|------|--------|
| `app/lib/main.dart` | notifications conditional import |
| `app/lib/router.dart` | Web/app route branching, /admin/* subroutes, /no-access |
| `app/lib/screens/admin/admin_screen.dart` | Extract tab widgets for reuse in AdminShell |

### Unchanged

- App user flows (Bottom Nav, all existing screens)
- Edge Functions / DB schema
- Existing providers

## Error Handling

- Web admin session expiry -> redirect `/login`
- Tournament edit save failure -> SnackBar error, retry possible

## Success Criteria

- `flutter build web` succeeds
- Web browser: login -> admin dashboard displayed
- Web browser: non-admin login -> no-access screen
- Mobile app: no behavioral changes (existing flows unaffected)
