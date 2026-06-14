-- 062: 일정 공유 (schedule_shares)
--
-- 파트너 자동: match_entries.partner_id에서 조회 (별도 테이블 불필요)
-- 수동 공유: 이벤트 단위로 특정 사람에게 공유 (이 테이블)

BEGIN;

CREATE TABLE public.schedule_shares (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  shared_by uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  shared_with uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  event_type text NOT NULL CHECK (event_type IN ('tournament', 'club_event')),
  event_id uuid NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'declined')),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT schedule_shares_no_self CHECK (shared_by != shared_with)
);

-- 중복 방지: 같은 사람에게 같은 이벤트 2번 공유 불가
CREATE UNIQUE INDEX schedule_shares_dedup_idx
  ON public.schedule_shares (shared_by, shared_with, event_type, event_id);

-- 공유받은 사람 기준 조회 (캘린더 화면)
CREATE INDEX schedule_shares_with_idx
  ON public.schedule_shares (shared_with, status);

ALTER TABLE public.schedule_shares ENABLE ROW LEVEL SECURITY;

-- 공유한 사람 + 공유받은 사람 모두 읽기 가능
-- 쓰기는 공유한 사람만
CREATE POLICY schedule_shares_self ON public.schedule_shares
  FOR ALL
  USING (shared_by = auth.uid() OR shared_with = auth.uid())
  WITH CHECK (shared_by = auth.uid());

COMMIT;
