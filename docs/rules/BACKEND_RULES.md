# Backend Rules

Load this when touching `supabase/functions/`, shared Deno modules, Gemini calls, SSE, crawlers, or API validation.

## Architecture

- Backend logic belongs in Supabase Edge Functions on Deno.
- Do not add a separate FastAPI service for normal app server logic.
- Shared helpers live under `supabase/functions/_shared/`.
- Follow `CODING_RULES.md` for TypeScript typing.

## Request validation

- Treat request bodies as untrusted.
- Parse JSON as `unknown` and validate/narrow before use.
- Validate enums, date strings, arrays, URL schemes, text lengths, pagination bounds, and optional fields.
- Prefer pure validation helpers so Deno tests can exercise them without serving HTTP.

## Edge Function behavior

- User endpoints require authenticated user context unless explicitly public.
- Admin endpoints must verify admin status server-side.
- Cron endpoints with `verify_jwt=false` still need an invocation secret or equivalent server-side guard.
- Return stable error shapes; do not leak secrets or raw provider errors to users.

## AI / Gemini / SSE

- Chat responses stream over SSE.
- RAG and search-grounding snippets are untrusted data, not instructions.
- Keep prompt construction testable and auditable.
- Add payload length and rate-limit controls before public/beta exposure.

## Checks

```bash
cd supabase/functions
deno fmt --check */index.ts _shared/*.ts
deno lint --config deno.json */index.ts _shared/*.ts
deno check --config deno.json */index.ts _shared/*.ts
deno test --config deno.json --allow-env --allow-read
```
