# 클럽 활동 MVP 설계

작성일: 2026-05-28

## 목적

가입 후 "할 게 없는" 클럽을 동호회 본질(같이 운동)에 맞게 살린다.
가입 → 클럽 파악(소개·멤버) → 모임 일정 참여로 이어지는 흐름을 만든다.

## 현황 (이미 구현됨 — 건드리지 않음)

- 클럽 생성(어드민 승인 워크플로우), 검색/목록, 내 클럽
- 가입 신청 → 클럽장 승인/거절, 가입 취소, 탈퇴 (`club_join_requests`)
- 멤버십 역할/상태 (`club_members.role` = owner/admin/member, `status`)
- 테이블: `clubs`, `club_members`, `club_join_requests`
- Edge Function: `clubs-search`, `clubs-create`, `clubs-join`, `clubs-review-join`, `clubs-approve`
- 화면: `clubs_screen`(목록·검색 탭), `club_create_screen`, 상세는 `_ClubDetailSheet`(바텀시트)

## 범위

### 포함 (MVP)
1. **클럽 상세 전체화면** (`/clubs/:id`) — 기존 바텀시트 대체, 탭: 소개 / 멤버 / 일정
2. **멤버 목록** — 가입 멤버(이름·역할 배지) 노출
3. **모임 일정** — 생성, 공식/번개 구분, 목록(다가오는 모임), 참석/불참 체크 + 참석자 수

### 제외 (후속 과제)
- 게시판/공지사항
- 정원 제한 + 대기자
- 구장 정보 연동 (#14 별도 기획)
- 일정 알림 푸시
- 일정 댓글/채팅

## 데이터 모델 (신규 2테이블)

```sql
create table public.club_events (
  id           uuid primary key default uuid_generate_v7(),
  club_id      uuid not null references public.clubs(id) on delete cascade,
  created_by   uuid not null references auth.users(id),
  type         text not null default 'casual' check (type in ('official','casual')),
  title        text not null,
  description  text,
  location_text text,
  starts_at    timestamptz not null,
  created_at   timestamptz not null default now()
);
create index on public.club_events (club_id, starts_at);

create table public.club_event_attendees (
  id           uuid primary key default uuid_generate_v7(),
  event_id     uuid not null references public.club_events(id) on delete cascade,
  user_id      uuid not null references auth.users(id),
  status       text not null check (status in ('going','not_going')),
  responded_at timestamptz not null default now(),
  unique (event_id, user_id)
);
```

(uuid 생성 함수는 기존 마이그레이션의 `uuid_generate_v7` 규칙을 따른다 — 015/017 참고)

## 권한 규칙 (RLS)

`club_events`
- **SELECT**: 해당 클럽의 활성 멤버(`club_members.status='active'`)만
- **INSERT**: 활성 멤버 누구나. 단 `type='official'`은 **운영진(`role` in ('owner','admin'))만** — `casual`은 모든 멤버
- **UPDATE/DELETE**: 작성자(`created_by`) 또는 운영진

`club_event_attendees`
- **SELECT**: 같은 클럽 멤버 (참석자 명단 공개)
- **INSERT/UPDATE**: 본인(`user_id = auth.uid()`)이고, 해당 이벤트 클럽의 활성 멤버일 때만 (upsert로 참석↔불참 토글)

> 공식 태그 권한 체크는 RLS의 `with check` 절에서 `club_members.role` 조회로 강제한다.
> 기존 `club_members` RLS 재귀 이슈(033) 회피를 위해 `security definer` 헬퍼 함수
> (예: `is_club_admin(club_id, uid)`, `is_club_member(club_id, uid)`)로 분리한다.

## 데이터 접근 방식

기존 `pendingJoinRequests`처럼 **Supabase 클라이언트 직접 쿼리(`.from()`) + RLS 보호**를 기본으로 한다.
별도 Edge Function은 만들지 않는다(MVP 단순화). 공식 태그·멤버십 검증은 전부 RLS가 담당.

`ApiService` 추가 메서드:
- `clubEvents(clubId)` — 다가오는 일정 목록 (참석자 수 포함)
- `createClubEvent(clubId, {type, title, description, locationText, startsAt})`
- `respondEvent(eventId, {going})` — attendees upsert
- `clubMembers(clubId)` — 멤버 목록(이름·역할)

## 화면

### `ClubDetailScreen` (`/clubs/:id`)
- `clubs_screen`의 `_ClubDetailSheet` 진입을 `context.push('/clubs/:id')`로 교체
- 라우터에 `GoRoute(/clubs/:id)` 추가 (기존 `/tournaments/:id` 패턴 참고)
- 상단: 클럽 정보(이름·종목·지역·소개·멤버수·가입/탈퇴 버튼)
- `TabBar`: **소개 / 멤버 / 일정**
  - 소개: description, 연락처/웹사이트 등
  - 멤버: 멤버 목록 (이름·역할 배지, 운영진 상단)
  - 일정: 다가오는 모임 카드 리스트
    - 공식 🔵 / 번개 🟡 배지, 제목·일시·장소
    - **참석/불참 토글** + 참석자 수(`N명 참석`)
    - FAB "모임 만들기" → 입력 폼(제목·일시·장소·종류). 종류=공식은 운영진에게만 노출

## 검증 / 테스트

- RLS 시나리오: 비멤버 일정 조회 차단 / 일반 멤버 공식 생성 거부·번개 허용 / 본인 외 참석 거부
- `flutter analyze` 통과
- 기존 `clubs-*` 패턴·네이밍 준수, `club_members` RLS 재귀(033) 회피 확인
- 멤버/비멤버/운영진 3개 역할로 수동 확인

## 후속 (이 MVP 이후)

- 일정 알림(푸시), 정원/대기자, 게시판/공지, 구장 연동(#14), 일정 댓글
