// dev-auth: 개발용 즉시 로그인 (비밀번호 불필요)
// POST { email: "ssfak@naver.com" }
// service_role로 magic link 토큰을 생성해 반환 → Flutter에서 verifyOTP로 세션 설정
//
// 프로덕션 배포 금지 — 로컬/개발 전용

import { errorResponse, jsonResponse, preflight } from '../_shared/cors.ts';
import { serviceClient } from '../_shared/supabase.ts';

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== 'POST') return errorResponse('Method not allowed', 405);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return errorResponse('Invalid JSON', 400);
  }

  const email = (body.email as string | undefined)?.trim();
  if (!email) return errorResponse('email is required', 400);

  const supa = serviceClient();

  // admin API로 magic link 생성 (메일 발송 안 함, 토큰만 반환)
  const { data, error } = await supa.auth.admin.generateLink({
    type: 'magiclink',
    email,
  });

  if (error) return errorResponse(error.message, 500);
  if (!data?.properties?.hashed_token) {
    return errorResponse('Failed to generate token', 500);
  }

  return jsonResponse({
    hashed_token: data.properties.hashed_token,
    email,
  });
});
