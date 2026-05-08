import { errorResponse, jsonResponse, preflight } from '../_shared/cors.ts';
import { requireAdmin } from '../_shared/auth.ts';

/**
 * POST /tournaments-approve
 * Body: { id: uuid, action: 'approve'|'reject', reason?: string }
 *
 * 관리자만 호출 가능. approve → status='published', reject → 'closed' + rejection_reason
 */
Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== 'POST') return errorResponse('Method not allowed', 405);

  const auth = await requireAdmin(req);
  if ('error' in auth) return auth.error;
  const { supabase, user } = auth;

  let body: { id?: string; action?: 'approve' | 'reject'; reason?: string };
  try {
    body = await req.json();
  } catch {
    return errorResponse('Invalid JSON body');
  }

  if (!body.id) return errorResponse('id required');
  if (body.action !== 'approve' && body.action !== 'reject') {
    return errorResponse('action must be approve or reject');
  }

  const update = body.action === 'approve'
    ? {
      status: 'published' as const,
      approved_by: user.id,
      approved_at: new Date().toISOString(),
      rejection_reason: null,
    }
    : {
      status: 'closed' as const,
      approved_by: user.id,
      approved_at: new Date().toISOString(),
      rejection_reason: body.reason ?? '관리자 거부',
    };

  const { data, error } = await supabase
    .from('tournaments')
    .update(update)
    .eq('id', body.id)
    .select()
    .single();

  if (error) return errorResponse(error.message, 500);
  return jsonResponse({ tournament: data });
});
