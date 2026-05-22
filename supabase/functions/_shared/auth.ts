import { SupabaseClient } from '@supabase/supabase-js';
import { userClient } from './supabase.ts';
import { errorResponse } from './cors.ts';

export interface AuthedUser {
  id: string;
  email: string | null;
  isAdmin: boolean;
}

/**
 * Authorization 헤더의 JWT 를 검증하고 public.users 의 role 을 합쳐 반환.
 * 인증 실패 시 Response 를 반환하므로 호출 측에서 분기한다.
 */
export async function requireUser(
  req: Request,
): Promise<{ user: AuthedUser; supabase: SupabaseClient } | { error: Response }> {
  const authHeader = req.headers.get('Authorization');
  if (!authHeader) {
    return { error: errorResponse('Missing Authorization header', 401) };
  }

  const supabase = userClient(authHeader);
  const { data: userData, error } = await supabase.auth.getUser();
  if (error || !userData.user) {
    return { error: errorResponse('Invalid or expired token', 401) };
  }

  const { data: profile } = await supabase
    .from('users')
    .select('role')
    .eq('id', userData.user.id)
    .maybeSingle();

  return {
    supabase,
    user: {
      id: userData.user.id,
      email: userData.user.email ?? null,
      isAdmin: profile?.role === 'admin',
    },
  };
}

export async function requireAdmin(req: Request) {
  const result = await requireUser(req);
  if ('error' in result) return result;
  if (!result.user.isAdmin) {
    return { error: errorResponse('Admin only', 403) };
  }
  return result;
}

export function requireServiceRole(
  req: Request,
): { error: Response } | Record<string, never> {
  const auth = req.headers.get('Authorization') ?? '';
  const token = auth.replace('Bearer ', '');
  if (!token) {
    return { error: errorResponse('Missing token in Authorization header', 401) };
  }

  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!serviceKey || token !== serviceKey) {
    return { error: errorResponse('Forbidden: Invalid Service Key', 403) };
  }
  return {};
}

export function requireServiceRoleOrAdmin(
  req: Request,
): Promise<{ error: Response } | Record<string, never>> {
  const srResult = requireServiceRole(req);
  if (!('error' in srResult)) return Promise.resolve({});
  // admin 통과 시 user/supabase 객체는 현재 호출처들이 사용하지 않으므로 빈 객체로 정규화
  // (반환 타입 시그니처와 일치 + 모든 callers 가 'error in auth' 만 분기).
  return requireAdmin(req).then((r) => ('error' in r ? r : ({} as Record<string, never>)));
}
