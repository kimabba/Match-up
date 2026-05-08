import { jsonResponse, preflight } from '../_shared/cors.ts';

Deno.serve((req) => {
  const pre = preflight(req);
  if (pre) return pre;
  return jsonResponse({ status: 'ok', service: 'match-up', ts: new Date().toISOString() });
});
