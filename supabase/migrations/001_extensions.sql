-- 001_extensions.sql
-- 필수 PostgreSQL 확장 활성화

create extension if not exists pgcrypto;   -- gen_random_uuid()
create extension if not exists vector;     -- pgvector (의미 기반 검색)
create extension if not exists pg_cron;    -- 주기적 작업 스케줄
create extension if not exists pg_net;     -- DB에서 외부 HTTP 호출 (Edge Function 트리거)
