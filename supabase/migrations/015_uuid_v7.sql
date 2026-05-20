-- 015_uuid_v7.sql
-- UUID v7 (RFC 9562, timestamp 기반) 도입.
--
-- 동기:
--   v4 UUID 는 완전 random 이라 PK 인덱스가 시간 순서와 무관해 INSERT 시 B-tree 페이지가
--   사방으로 흩어진다 (random insert → split → fragmentation). v7 은 상위 48비트가 unix_ts_ms
--   라 시간 순서대로 정렬되어 인덱스 locality 가 좋아지고 캐시 효율이 올라간다.
--   특히 qa_cache / intent_examples 처럼 시간 순으로 누적되는 테이블에서 효과가 크다.
--
-- 적용 범위 (제한적):
--   - 새 테이블 (qa_cache, intent_examples) 의 `id` default 만 변경.
--   - 기존 v4 행은 그대로 유지 (혼재 운영 안전 — UUID 는 type 가 동일하므로 PK/FK 호환).
--   - 다른 테이블 (users, tournaments, clubs 등) 은 손대지 않음.
--
-- 구현 방식:
--   - PG 18 부터 core `uuidv7()` 가 들어왔으나 매치업은 PG 17.6 사용 중이라 직접 구현.
--   - application 단 (Deno) 생성은 변경 폭이 커 보류. PostgreSQL 함수 한 곳에서 처리.
--   - pgcrypto 의 `gen_random_bytes` + bit manipulation 으로 RFC 9562 §5.7 명세 따름.
--
-- RFC 9562 §5.7 레이아웃 (128 bits):
--   unix_ts_ms (48) | ver=0111 (4) | rand_a (12) | var=10 (2) | rand_b (62)
--
-- 멱등성: `create or replace function` + `alter ... set default` 모두 재실행 안전.

create extension if not exists pgcrypto;

create or replace function public.uuid_generate_v7()
returns uuid
language plpgsql
volatile
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
  uuid_bytes := unix_ts_ms || gen_random_bytes(10);

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

comment on function public.uuid_generate_v7() is
  'RFC 9562 §5.7 UUID v7 (timestamp 기반). PG 18 core uuidv7() 의 PG 17 대체 구현.';

-- 권한: 다른 RPC 들과 일관성 — service_role 만 호출 가능.
-- qa_cache / intent_examples 의 INSERT 자체가 service_role 전용 (RLS) 이므로
-- default 평가 시에도 동일 권한자가 호출 → 정상 동작.
revoke all on function public.uuid_generate_v7() from public;
grant execute on function public.uuid_generate_v7() to service_role;

-- =========================
-- 신규 테이블 default 만 변경. ALTER COLUMN TYPE 절대 금지 (기존 v4 행 영향).
-- =========================
alter table public.qa_cache
  alter column id set default public.uuid_generate_v7();

alter table public.intent_examples
  alter column id set default public.uuid_generate_v7();
