-- 057: clubs/club_members/club_events 재설계
--
-- 1. clubs: meeting_days, monthly_fee, gender_preference 추가
-- 2. club_members: can_kick, can_create_event, can_post_notice 권한 추가
-- 3. club_events: type 컬럼 제거 + RLS 권한 체계 변경 (운영자 + can_create_event)

BEGIN;

-- ═══════════════════════════════════════════════════════════════
-- 1. clubs 필터용 컬럼 추가
-- ═══════════════════════════════════════════════════════════════

ALTER TABLE public.clubs
  ADD COLUMN meeting_days text[] NOT NULL DEFAULT '{}',
  ADD COLUMN monthly_fee int,
  ADD COLUMN gender_preference text;

ALTER TABLE public.clubs
  ADD CONSTRAINT clubs_gender_preference_check
  CHECK (gender_preference IS NULL OR gender_preference IN ('male', 'female', 'mixed'));

-- ═══════════════════════════════════════════════════════════════
-- 2. club_members 권한 boolean 추가
-- ═══════════════════════════════════════════════════════════════

ALTER TABLE public.club_members
  ADD COLUMN can_kick boolean NOT NULL DEFAULT false,
  ADD COLUMN can_create_event boolean NOT NULL DEFAULT false,
  ADD COLUMN can_post_notice boolean NOT NULL DEFAULT false;

-- ═══════════════════════════════════════════════════════════════
-- 3. club_events: type 컬럼 제거 + RLS 재설정
--    기존: official=manager만, casual=모든멤버
--    변경: owner + manager + can_create_event 멤버만
-- ═══════════════════════════════════════════════════════════════

-- 기존 INSERT 정책 제거 (type 기반)
DROP POLICY IF EXISTS club_events_insert ON public.club_events;

-- 새 INSERT 정책: owner/manager 또는 can_create_event=true
CREATE POLICY club_events_insert ON public.club_events
  FOR INSERT WITH CHECK (
    created_by = auth.uid()
    AND (
      is_club_manager(club_id)
      OR EXISTS (
        SELECT 1 FROM public.club_members
        WHERE club_id = club_events.club_id
          AND user_id = auth.uid()
          AND status = 'active'
          AND can_create_event = true
      )
    )
  );

-- 기존 UPDATE 정책 제거 (type 기반 with check)
DROP POLICY IF EXISTS club_events_update ON public.club_events;

-- 새 UPDATE 정책: 작성자 또는 manager
CREATE POLICY club_events_update ON public.club_events
  FOR UPDATE
  USING (is_admin() OR created_by = auth.uid() OR is_club_manager(club_id))
  WITH CHECK (is_admin() OR created_by = auth.uid() OR is_club_manager(club_id));

-- type 컬럼 제거
ALTER TABLE public.club_events DROP COLUMN IF EXISTS type;

COMMIT;
