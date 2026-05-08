import { SupabaseClient } from '@supabase/supabase-js';
import { serviceClient } from './supabase.ts';

export interface CrawlerTournament {
  title: string;
  organizer?: string;
  description?: string;
  start_date: string;            // YYYY-MM-DD
  end_date?: string;
  application_deadline?: string;
  region?: string;
  location?: string;
  eligible_grades: string[];     // ['rookie','div5',...]
  entry_fee?: number;
  prize?: string;
  format?: string;
  source_url: string;
}

interface AuditHandle {
  id: string;
  source: string;
  supabase: SupabaseClient;
  fetched: number;
  inserted: number;
  updated: number;
}

export async function startAudit(source: string): Promise<AuditHandle> {
  const supabase = serviceClient();
  const { data, error } = await supabase
    .from('crawl_audit')
    .insert({ source, status: 'running' })
    .select('id')
    .single();
  if (error) throw new Error(`startAudit: ${error.message}`);
  return { id: data!.id, source, supabase, fetched: 0, inserted: 0, updated: 0 };
}

export async function finishAudit(
  audit: AuditHandle,
  status: 'success' | 'partial' | 'failed',
  error?: string,
) {
  await audit.supabase
    .from('crawl_audit')
    .update({
      status,
      fetched_count: audit.fetched,
      inserted_count: audit.inserted,
      updated_count: audit.updated,
      error: error ?? null,
      finished_at: new Date().toISOString(),
    })
    .eq('id', audit.id);
}

/**
 * source_url 기준 upsert. 신규는 status='published' 로 즉시 게시.
 *  (사용자 제보와 달리 협회/공식 사이트 출처는 검수 없이 표시)
 *
 * 임베딩은 NULL 로 시작 → embed-pending 워커가 5분 이내에 채움.
 */
export async function upsertTournament(
  audit: AuditHandle,
  sport: 'tennis' | 'futsal',
  t: CrawlerTournament,
): Promise<'inserted' | 'updated' | 'skipped'> {
  audit.fetched++;
  const { data: existing } = await audit.supabase
    .from('tournaments')
    .select('id, title, start_date, application_deadline, eligible_grades, region')
    .eq('source', audit.source)
    .eq('source_url', t.source_url)
    .maybeSingle();

  if (existing) {
    // 변경된 필드만 업데이트 (전체 비교 생략하고 항상 업데이트)
    const { error } = await audit.supabase
      .from('tournaments')
      .update({
        title: t.title,
        organizer: t.organizer ?? null,
        description: t.description ?? null,
        start_date: t.start_date,
        end_date: t.end_date ?? null,
        application_deadline: t.application_deadline ?? null,
        region: t.region ?? null,
        location: t.location ?? null,
        eligible_grades: t.eligible_grades,
        entry_fee: t.entry_fee ?? null,
        prize: t.prize ?? null,
        format: t.format ?? null,
      })
      .eq('id', existing.id);
    if (error) throw new Error(`upsertTournament update: ${error.message}`);
    audit.updated++;
    return 'updated';
  }

  const { error } = await audit.supabase.from('tournaments').insert({
    sport,
    title: t.title,
    organizer: t.organizer ?? null,
    description: t.description ?? null,
    start_date: t.start_date,
    end_date: t.end_date ?? null,
    application_deadline: t.application_deadline ?? null,
    region: t.region ?? null,
    location: t.location ?? null,
    eligible_grades: t.eligible_grades,
    entry_fee: t.entry_fee ?? null,
    prize: t.prize ?? null,
    format: t.format ?? null,
    source: audit.source,
    source_url: t.source_url,
    status: 'published',
  });
  if (error) throw new Error(`upsertTournament insert: ${error.message}`);
  audit.inserted++;
  return 'inserted';
}

/**
 * 페이지 전체 텍스트에서 등급 키워드 자동 추출.
 * 광주/전남 협회 공고문 패턴: "신입부", "5부", "4부"... "오픈" 등.
 *
 * 정밀하지 않으니 사이트별 파서에서 override 권장.
 */
export function extractTennisGradesFromText(text: string): string[] {
  const found: Set<string> = new Set();
  if (/신입|노부|새내기|초보/i.test(text)) found.add('rookie');
  if (/\b5\s*부\b|5부|디비전5|d5/i.test(text)) found.add('div5');
  if (/\b4\s*부\b|4부|디비전4|d4/i.test(text)) found.add('div4');
  if (/\b3\s*부\b|3부|디비전3|d3/i.test(text)) found.add('div3');
  if (/\b2\s*부\b|2부|디비전2|d2/i.test(text)) found.add('div2');
  if (/\b1\s*부\b|1부|디비전1|d1|오픈/i.test(text)) found.add('div1');
  // 모든 부수 대회면 전체
  if (found.size === 0 && /(전\s*부수|모든\s*부수)/i.test(text)) {
    return ['rookie', 'div5', 'div4', 'div3', 'div2', 'div1'];
  }
  return [...found];
}
