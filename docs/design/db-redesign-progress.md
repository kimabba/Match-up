# DB 재설계 진행 현황

> 마지막 업데이트: 2026-06-14
> 다음 세션에서 이 파일부터 읽고 이어서 진행

## 설계 순서

```
Layer 0: users                    ✅ 확정
Layer 1: user_sports              ✅ 확정 (현행 유지)
Layer 1: user_tennis_orgs         ✅ 확정 (PK 변경 + 컬럼 정리)
Layer 2: tournaments              ✅ 확정 (공통+확장 분리, JY-59 재검토)
Layer 2: clubs                    ✅ 확정 (meeting_days/monthly_fee/gender 추가)
Layer 3: club_members             ✅ 확정 (권한 boolean 컬럼 3개 추가)
Layer 4: club_events              ✅ 확정 (casual 제거, 운영자만)
Layer 4: club_posts/comments/mentions ✅ 확정 (신규 3개 테이블)
Layer 4: Storage club-posts       ✅ 확정 (1280px 압축, 10MB, 5장)
Layer 5: notifications            ✅ 확정 (통합 테이블, 8종 type)
Layer 6: match_entries, match_rounds ✅ 확정 (대회 참가 + 라운드 상세)
Layer 7: schedule_shares          ✅ 확정 (파트너 자동 + 수동 이벤트 공유)
```

## Layer 0: users — 확정

```sql
users (
  id                uuid PK (= auth.users.id)
  email             text NOT NULL
  name              text NOT NULL          -- 실명 (기존 display_name → name)
  nickname          text                   -- 닉네임 (선택)
  avatar_url        text                   -- 프로필 사진 (서버 저장)
  phone             text                   -- 연락처
  birth_year        int                    -- 출생 연도
  gender            text CHECK (male|female)
  bio               text                   -- 자기소개
  primary_region    text FK → regions      -- 주 활동 지역
  interest_regions  text[] CHECK (max 3)   -- 관심 지역
  role              user_role (user|admin)
  created_at        timestamptz
  updated_at        timestamptz
)
```

변경점: display_name → name, nickname/avatar_url/phone/birth_year/gender/bio/primary_region/interest_regions 추가

## Layer 1: user_sports — 확정 (현행 유지)

```sql
user_sports (
  user_id    uuid FK
  sport      sport (tennis | futsal)
  grade      text
  is_primary boolean
  created_at timestamptz
  PK (user_id, sport)
)
```

종목 전용 프로필(play_style, ntrp 등)은 불필요 — 테니스/풋살 공용이어야 하므로.

## Layer 1: user_tennis_orgs — ✅ 확정

### 핵심 변경: PK `(user_id, org)` → `(user_id, org, division)`
한 사용자가 같은 협회에서 여러 부서(골드부+오픈부 등)에 출전 가능. 부서별 점수/포인트가 다름.

```sql
user_tennis_orgs (
  user_id         uuid         NOT NULL FK
  org             tennis_org   NOT NULL     -- 소속 협회 (gj, kta, kato...)
  division        text         NOT NULL     -- 출전 부서 (골드부, 오픈부...)
  score           numeric(5,1)              -- 등급 점수 (협회별 의미 다름, 통합)
  ranking_points  int                       -- 누적 랭킹 포인트 (KATA 등)
  player_origin   text                      -- 선수 출신 단계 (elementary/middle/high/university/professional/instructor)
  is_primary      boolean      DEFAULT false -- 주 부서 여부
  region_code     text FK → regions         -- 활동 지역
  created_at      timestamptz  DEFAULT now()
  updated_at      timestamptz  DEFAULT now()
  PK (user_id, org, division)
)
```

### 변경 사유
- grade_level 제거 → score로 통합 (KATO 그룹도 숫자 매핑)
- expires_at 제거 → 협회 데이터 크롤로 가져오므로 자체 만료 관리 불필요
- is_player_origin boolean → player_origin text (초등/중등/고등/대학/실업/지도자 단계별)
- score 범위 확대: numeric(3,1) → numeric(5,1) (전북 13점 수용)
- 검증: 10개 패턴 테스트 9 PASS / 1 FAIL(선수출신) → 해결 완료

## 클럽 기능 — 이전 브레인스토밍 확정 사항

| 항목 | 결정 |
|------|------|
| 역할 체계 | owner / manager / member (3단계 + 권한 boolean 컬럼) |
| 권한 저장 | club_members에 can_kick, can_create_event, can_post |
| 멀티 가입 | 무제한 |
| 게시판 | 태그 고정 프리셋 (notice, free, recruit, photo), 시간순 |
| 게시판 공지 | notice 태그는 운영자만 작성 |
| 댓글 | 1단, 멘션으로 대상 지정 |
| 알림 6종 | 공지 + 일정등록 + 멘션 + 댓글 + D-1 리마인더 + 참석변경 |
| 일정 등록 | 운영자만 (casual 타입 제거) |
| 채팅 | Post-MVP (게시판 + 카카오 오픈채팅 링크) |
| 캘린더 연동 | ICS 파일 다운로드 |

## 전체 설계 범위 (3개 도메인)

### 1. 클럽 (기존 확장)
멀티 가입, 역할 체계, 게시판, 일정, 알림

### 2. 친구 일정 (신규)
- 대회 파트너/팀원 간 일정 공유
- 서로 수락한 관계(친구)끼리 캘린더 통합
- 클럽 대항전은 클럽 운영진 생성 → 자동 포함
- 구글/아이폰 캘린더 연동 (ICS)

### 3. 경기 이력 + 랭킹 (핵심 차별화)
- 대회 출전 기록, 스코어, 진출 단계
- 협회별 포인트 수집/저장
- 상대 전적 조회
- 지역/협회 간 포인트 통합 → 등급 조작 방지
- 챗봇/메뉴에서 랭킹·포인트 조회
