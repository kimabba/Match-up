-- 022_tournament_status_rejected.sql
-- Phase 3: tournament_status enum 에 'rejected' 추가.
--
-- 의미 구분:
--   'draft'     : 크롤러 또는 사용자 제보로 들어와 검수 대기 중
--   'published' : 관리자 승인되어 사용자에게 노출됨
--   'closed'    : 정상 운영 종료된 마감 대회 (과거 published)
--   'rejected'  : 관리자 검수 거부 — 사용자 UI 노출 안 함,
--                 다음 크롤링 시 같은 source_url 이 다시 들어와도 status 유지
--
-- 거부 사유는 기존 tournaments.rejection_reason 컬럼 그대로 사용.
--
-- 주의: PostgreSQL 의 ALTER TYPE ... ADD VALUE 는 트랜잭션 블록 안에서
-- 사용 후 같은 트랜잭션 내 새 enum 값을 다른 DDL 가 즉시 참조하면 실패할 수 있다.
-- supabase migration up 은 각 마이그레이션 파일을 별도 트랜잭션으로 실행하므로
-- 본 파일은 enum 추가만 다루고, 새 값을 참조하는 RPC 는 023 에서 정의한다.

alter type public.tournament_status add value if not exists 'rejected';

-- 기존 status='closed' AND rejection_reason IS NOT NULL 인 운영 데이터를
-- 'rejected' 로 백필하지 않는다.
--   - 'closed' 컬럼은 "마감 대회" 의미로도 사용되어 왔으므로 자동 분류 시 false positive 위험.
--   - 필요 시 관리자가 어드민 UI 에서 수동 보정.
