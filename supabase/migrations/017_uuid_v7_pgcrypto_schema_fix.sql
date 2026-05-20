-- 017_uuid_v7_pgcrypto_schema_fix.sql
-- Hotfix: uuid_generate_v7() 의 gen_random_bytes 호출이 search_path 미명시로 실패하던 문제 수정.
--
-- 증상 (production logs):
--   [Warning] chat_cache {"event":"insert_failed",
--     "reason":"function gen_random_bytes(integer) does not exist"}
--   → qa_cache INSERT 가 모두 실패 → Day 2 의 semantic cache 효과 무력화.
--
-- 원인:
--   Supabase 는 pgcrypto extension 을 `extensions` schema 에 설치 (기본 schema 가 아님).
--   015 의 uuid_generate_v7() 는 search_path 명시 없이 `gen_random_bytes(10)` 호출.
--   service_role 컨텍스트의 search_path 가 strict (e.g. `pg_catalog, public` 만) 라
--   `extensions.gen_random_bytes` 를 찾지 못해 함수 실행 자체가 깨짐.
--
-- 수정:
--   - `extensions.gen_random_bytes(10)` 으로 schema-qualified 호출 → 환경 무관 안전.
--   - 추가로 `set search_path = pg_catalog, public, extensions` 도 명시 (이중 안전망).
--   - 기존 함수 시그니처 / 반환 타입 / 권한 유지 (create or replace).

create or replace function public.uuid_generate_v7()
returns uuid
language plpgsql
volatile
set search_path = pg_catalog, public, extensions
as $$
declare
  unix_ts_ms bytea;
  uuid_bytes bytea;
begin
  -- 48 bits unix timestamp (ms). int8send 는 8 bytes 반환 → 상위 2 bytes drop 해서 6 bytes 확보.
  unix_ts_ms := substring(
    int8send((extract(epoch from clock_timestamp()) * 1000)::bigint)
    from 3
  );

  -- 48 bits timestamp + 80 bits random = 128 bits (16 bytes).
  -- schema-qualified 호출: Supabase 에서 pgcrypto 는 extensions schema 에 설치됨.
  uuid_bytes := unix_ts_ms || extensions.gen_random_bytes(10);

  -- byte 6 (0-indexed): version 7 설정. 상위 4비트 = 0111 (0x70), 하위 4비트는 random rand_a 유지.
  uuid_bytes := set_byte(
    uuid_bytes,
    6,
    ((get_byte(uuid_bytes, 6) & 15) | 112)
  );

  -- byte 8: RFC 4122 variant 설정. 상위 2비트 = 10 (0x80), 하위 6비트는 random rand_b 유지.
  uuid_bytes := set_byte(
    uuid_bytes,
    8,
    ((get_byte(uuid_bytes, 8) & 63) | 128)
  );

  return encode(uuid_bytes, 'hex')::uuid;
end;
$$;

-- 권한 재적용 (create or replace 는 권한 유지하나 안전을 위해 명시).
revoke all on function public.uuid_generate_v7() from public;
grant execute on function public.uuid_generate_v7() to service_role;
