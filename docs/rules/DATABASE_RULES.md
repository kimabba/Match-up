# Database Rules

Load this when touching `supabase/migrations/`, SQL functions, RLS, RPC, pg_cron, pg_net, or pgvector search.

## Schema rules

- Use explicit types for every column.
- Prefer `text` over `varchar` unless there is a specific constraint reason.
- Reusable enums should use `create type`.
- New tables must enable RLS and include policies in the same migration.
- Add indexes for expected search/filter paths.

## RLS and authorization

- RLS must be the final data access boundary.
- Admin checks should use a reviewed SECURITY DEFINER helper such as `is_admin()`.
- Service-role usage should be isolated to Edge Functions and cron workers; never expose it to the client.

## RPC rules

- Eligibility and filtering rules that must be consistent should live in SQL/RPC, not in Flutter.
- `tournaments_for_user`-style functions must prevent cross-sport grade matching.
- Filters that affect result membership should be applied before pagination.

## Cron and workers

- `embed-pending`, `notify-cron`, and crawler jobs may have `verify_jwt=false`, but still need invocation protection.
- Store cron invocation URL/key via DB GUC only in secure environments.
- Workers should be idempotent where practical.

## pgvector / embeddings

- Tournament/rule content changes should invalidate embeddings by setting `embedding = null`.
- Embedding workers recompute pending rows.
- Vector dimensions must match `gemini-embedding-001` usage: 768d.

## Checks

- For migration changes, run `supabase db reset` when Docker/Supabase CLI are available.
- Add SQL smoke fixtures for RLS/RPC behavior when changing domain-critical logic.
