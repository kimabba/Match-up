-- 055_users_profile_columns.sql
-- users 테이블에 프로필 컬럼 추가 + display_name → name 리네임

BEGIN;

-- 1. display_name → name 리네임 (NULL 행 기본값 먼저 설정)
UPDATE public.users
SET display_name = split_part(email, '@', 1)
WHERE display_name IS NULL;

ALTER TABLE public.users
  RENAME COLUMN display_name TO name;

ALTER TABLE public.users
  ALTER COLUMN name SET NOT NULL;

-- 2. 새 프로필 컬럼 추가
ALTER TABLE public.users
  ADD COLUMN nickname   text,
  ADD COLUMN avatar_url text,
  ADD COLUMN phone      text,
  ADD COLUMN birth_year int,
  ADD COLUMN gender     text,
  ADD COLUMN bio        text,
  ADD COLUMN primary_region text REFERENCES public.regions(code),
  ADD COLUMN interest_regions text[] NOT NULL DEFAULT '{}';

-- 3. CHECK 제약조건
ALTER TABLE public.users
  ADD CONSTRAINT users_gender_check
    CHECK (gender IN ('male', 'female')),
  ADD CONSTRAINT users_interest_regions_max3
    CHECK (array_length(interest_regions, 1) IS NULL
        OR array_length(interest_regions, 1) <= 3);

-- 4. handle_new_user() 트리거 함수 수정 (display_name → name)
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.users (id, email, name)
  VALUES (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data ->> 'display_name', split_part(new.email, '@', 1))
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN new;
END;
$$;

COMMIT;
