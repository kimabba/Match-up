-- 025_futsal_tournament_fields.sql
-- 풋살 대회 특유 필드 추가
--
-- 리서치 근거 (2026-05-22):
--   - 풋살은 팀 단위 참가 (per_team 기본)
--   - 인제(人制) 구분: 5인제(FIFA공식)/6인제(동호인 다수)/7인제 혼재
--   - 부서가 실력 × 성별 × 연령 3축 조합
--     예: "남자30대부 상급", "여성부", "혼성 일반부"
--     현재 eligible_grades(beginner/intermediate/advanced)로는 성별·연령축 표현 불가
--   - 모집 팀 수 상한(team_count_max) + 현재 접수 수(team_count_current)로 마감 여부 판단
--   - 구장 타입: 실내(마루/우레탄) vs 실외(인조잔디) — 검색 필터로 활용
--
-- 모든 컬럼은 nullable:
--   - 테니스 기존 데이터에 영향 없음
--   - 풋살 크롤러가 파악 가능한 정보만 채움

-- =========================
-- futsal_org enum
-- =========================
do $$
begin
  if not exists (select 1 from pg_type where typname = 'futsal_org') then
    create type public.futsal_org as enum (
      'kfl',          -- 한국풋살연맹 (Korea Futsal League)
      'kfa_futsal',   -- 대한풋살협회 (Korea Futsal Association)
      'kfa',          -- 대한축구협회 (KFA) — 주최 대회
      'sleague',      -- 생활체육서울시민리그 S리그
      'gg_futsal',    -- 경기도풋살연합회
      'local'         -- 지역 연합회/클럽 자체 주최
    );
  end if;
end $$;

-- =========================
-- tournaments 풋살 컬럼 추가
-- =========================

-- 인제(人制): 코트 위 선수 수 (골키퍼 포함)
-- 5인제 = FIFA 공식 / 6인제 = 동호인 최다 / 7인제 = 일부 생활체육
alter table public.tournaments
  add column if not exists player_count integer
    check (player_count in (5, 6, 7, 8));

-- 성별 부서: male(남자부) / female(여자부) / mixed(혼성부) / null(제한 없음)
alter table public.tournaments
  add column if not exists division_gender text
    check (division_gender in ('male', 'female', 'mixed'));

-- 연령/자격 부서
--   adult    : 성인 일반부 (기본)
--   youth    : 유소년 (U-12/U-15 등)
--   elementary: 초등부
--   senior   : 시니어 (40대+, 50대+ 등)
--   workplace : 직장인부
--   open     : 제한 없음 (오픈부)
alter table public.tournaments
  add column if not exists division_age_group text
    check (division_age_group in ('adult', 'youth', 'elementary', 'senior', 'workplace', 'open'));

-- 모집 팀 수 상한 (예: 30팀, 64팀) — 마감 여부 판단에 사용
alter table public.tournaments
  add column if not exists team_count_max integer;

-- 현재 참가 접수 팀 수 (크롤러가 파악 가능한 경우에만 갱신)
alter table public.tournaments
  add column if not exists team_count_current integer;

-- 팀 최소 등록 선수 수 (예: 7명 이상 필수)
alter table public.tournaments
  add column if not exists roster_min integer;

-- 팀 최대 등록 선수 수 (예: 최대 15명)
alter table public.tournaments
  add column if not exists roster_max integer;

-- 구장 타입: indoor(실내 마루/우레탄) / outdoor(실외 인조잔디)
alter table public.tournaments
  add column if not exists venue_type text
    check (venue_type in ('indoor', 'outdoor'));

-- 구장 표면
alter table public.tournaments
  add column if not exists surface_type text
    check (surface_type in ('artificial_turf', 'wood_floor', 'urethane', 'concrete'));

-- 경기 방식 (구조화)
--   group_knockout  : 조별 리그 후 토너먼트 (가장 흔함)
--   round_robin     : 리그 방식 (승점제)
--   knockout_only   : 단판 토너먼트
--   league          : 시즌 리그제
alter table public.tournaments
  add column if not exists match_format text
    check (match_format in ('group_knockout', 'round_robin', 'knockout_only', 'league'));

-- 풋살 주최 협회 enum 배열 (tennis_org[] 와 동일 패턴)
alter table public.tournaments
  add column if not exists host_futsal_orgs public.futsal_org[] not null default '{}';

-- =========================
-- 인덱스
-- =========================

-- 풋살 대회 검색: 성별·인제 필터
create index if not exists tournaments_futsal_filter_idx
  on public.tournaments (sport, player_count, division_gender)
  where sport = 'futsal' and status = 'published';

-- 마감 여부 빠른 확인
create index if not exists tournaments_team_slots_idx
  on public.tournaments (team_count_max, team_count_current)
  where sport = 'futsal' and status = 'published'
    and team_count_max is not null;

-- =========================
-- 코멘트
-- =========================
comment on column public.tournaments.player_count is
  '인제(人制): 코트 위 선수 수. 5=FIFA공식, 6=동호인최다, 7·8=일부생활체육. NULL=제한없음';
comment on column public.tournaments.division_gender is
  '성별 부서. male/female/mixed/NULL(제한없음). eligible_grades와 독립적으로 운영';
comment on column public.tournaments.division_age_group is
  '연령/자격 부서. adult/youth/elementary/senior/workplace/open';
comment on column public.tournaments.team_count_max is
  '모집 팀 수 상한. team_count_current >= team_count_max이면 마감';
comment on column public.tournaments.host_futsal_orgs is
  '풋살 주최 협회 enum 배열. tennis의 host_orgs와 동일 패턴';
