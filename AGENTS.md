# AGENTS.md — Match-up Agent Router

This file is intentionally short. Do **not** turn it into a full project manual.
Detailed rules live under `docs/rules/` and should be loaded only when the task touches that area.

## Always-on rules

1. Preserve user work. Check the working tree before broad edits and never overwrite unrelated changes.
2. Keep commits/changes small: one change should have one purpose.
3. Server/DB are the source of truth for auth, eligibility, visibility, quotas, and admin decisions.
4. Type safety is mandatory:
   - TypeScript/Deno: no `any`; parse external JSON as `unknown` and narrow with type guards.
   - Dart/Flutter: avoid `dynamic` except JSON boundaries; convert immediately to typed models.
   - SQL: new tables require explicit types, RLS enabled, and policies.
5. Root rule files stay small. Add detailed guidance under `docs/rules/`, then add a link here if needed.
6. Before finalizing, run the checks relevant to the files changed, or state exactly why they were not run.

## Load-on-demand rule map

Read only the docs needed for the task:

| Task touches... | Load first |
|---|---|
| Project overview, API map, env, operations | `docs/rules/PROJECT_CONTEXT.md` |
| Coding style, PR gates, language rules | `docs/rules/CODING_RULES.md` |
| Tournaments, sports, grades, eligibility, clubs | `docs/rules/DOMAIN_RULES.md` |
| Flutter app, routing, UI, Riverpod, API client | `docs/rules/FRONTEND_RULES.md` |
| Supabase Edge Functions, Deno, Gemini, SSE | `docs/rules/BACKEND_RULES.md` |
| Migrations, RLS, RPC, pgvector, cron | `docs/rules/DATABASE_RULES.md` |
| Auth, secrets, RAG safety, rate limits, abuse controls | `docs/rules/SECURITY_RULES.md` |
| Speed-gun/video/ball tracking logic | `docs/rules/SPEED_GUN_RULES.md` |
| Harness scripts, CI, custom rule checks | `docs/rules/HARNESS.md` |

## Common checks

Run the smallest relevant set, or use the common harness:

```bash
# Common repo harness
scripts/harness/run_all.sh

# Flutter changes
cd app && flutter analyze && flutter test

# Edge Function changes
cd supabase/functions && deno fmt --check */index.ts _shared/*.ts tests/*.ts && deno lint --config deno.json */index.ts _shared/*.ts tests/*.ts && deno check --config deno.json */index.ts _shared/*.ts tests/*.ts && deno test --config deno.json --allow-env --allow-read tests

# DB migration changes
supabase db reset
```
