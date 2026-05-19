# Match-up Rule System

This directory contains the detailed rules that used to make root agent files too large.
The root `AGENTS.md`/`CLAUDE.md` files should stay small and only route agents to these files.

## How to use

1. Start with the task description.
2. Open `AGENTS.md` and load only the matching rule files below.
3. Apply the relevant rules and run the smallest relevant checks.
4. If a new recurring rule appears, add it to the right file here, not to the root agent file.

## Files

| File | Use when... |
|---|---|
| `PROJECT_CONTEXT.md` | You need app overview, stack, architecture, API list, env vars, operational notes. |
| `CODING_RULES.md` | You write/review TypeScript, Dart, SQL, tests, or PR gates. |
| `DOMAIN_RULES.md` | You touch sports, grades, tournaments, clubs, eligibility, favorites, notifications. |
| `FRONTEND_RULES.md` | You touch Flutter screens, router, Riverpod state, API client, app UX. |
| `BACKEND_RULES.md` | You touch Supabase Edge Functions, shared Deno code, SSE, Gemini calls. |
| `DATABASE_RULES.md` | You touch migrations, RLS, RPC, pg_cron, pg_net, pgvector. |
| `SECURITY_RULES.md` | You touch auth, admin, secrets, AI/RAG, rate limits, abuse/cost controls. |
| `SPEED_GUN_RULES.md` | You touch speed-gun/video/ball tracking measurement code. |
| `HARNESS.md` | You add CI, scripts, custom rule checks, test harnesses, or merge gates. |

## Rule authoring policy

- Root files should stay under roughly 100 lines.
- Detailed rules belong here.
- A rule is strongest when it has a test, script, SQL check, or CI gate.
- Avoid duplicating rules across files. Put shared rules in `CODING_RULES.md` or `HARNESS.md` and link to them.
- Prefer “load on demand” over “always inject everything.”
