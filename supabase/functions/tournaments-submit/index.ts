import { errorResponse, jsonResponse, preflight } from '../_shared/cors.ts';
import { requireUser } from '../_shared/auth.ts';
import { isValidGrade, Sport } from '../_shared/enums.ts';

/**
 * POST /tournaments-submit
 *
 * 일반 사용자가 대회를 제보. status='draft' 로 저장되며 관리자가 승인하면 published.
 *
 * Body:
 *  {
 *    sport: 'tennis' | 'futsal',
 *    title: string,
 *    organizer?: string,
 *    description?: string,
 *    start_date: 'YYYY-MM-DD',
 *    end_date?: string,
 *    application_deadline?: string,
 *    region?: string,
 *    location?: string,
 *    eligible_grades: string[],
 *    entry_fee?: number,
 *    prize?: string,
 *    format?: string,
 *    source_url?: string
 *  }
 */
interface SubmitBody {
  sport: Sport;
  title: string;
  organizer?: string;
  description?: string;
  start_date: string;
  end_date?: string;
  application_deadline?: string;
  region?: string;
  location?: string;
  eligible_grades: string[];
  entry_fee?: number;
  prize?: string;
  format?: string;
  source_url?: string;
}

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== 'POST') return errorResponse('Method not allowed', 405);

  const auth = await requireUser(req);
  if ('error' in auth) return auth.error;
  const { supabase, user } = auth;

  let body: SubmitBody;
  try {
    body = await req.json();
  } catch {
    return errorResponse('Invalid JSON body');
  }

  if (!body.sport || (body.sport !== 'tennis' && body.sport !== 'futsal')) {
    return errorResponse('sport must be tennis or futsal');
  }
  if (!body.title?.trim()) return errorResponse('title required');
  if (!body.start_date) return errorResponse('start_date required');
  if (!Array.isArray(body.eligible_grades) || body.eligible_grades.length === 0) {
    return errorResponse('eligible_grades required (non-empty array)');
  }
  for (const g of body.eligible_grades) {
    if (!isValidGrade(body.sport, g)) {
      return errorResponse(`Invalid grade for ${body.sport}: ${g}`);
    }
  }

  const { data, error } = await supabase
    .from('tournaments')
    .insert({
      sport: body.sport,
      title: body.title.trim(),
      organizer: body.organizer ?? null,
      description: body.description ?? null,
      start_date: body.start_date,
      end_date: body.end_date ?? null,
      application_deadline: body.application_deadline ?? null,
      region: body.region ?? null,
      location: body.location ?? null,
      eligible_grades: body.eligible_grades,
      entry_fee: body.entry_fee ?? null,
      prize: body.prize ?? null,
      format: body.format ?? null,
      source_url: body.source_url ?? null,
      source: 'user_submission',
      status: 'draft',
      submitted_by: user.id,
    })
    .select()
    .single();

  if (error) return errorResponse(error.message, 500);
  return jsonResponse({ tournament: data }, { status: 201 });
});
