/**
 * Gemini Generative Language API + Search Grounding 클라이언트.
 *
 * REST 직접 호출. SSE 스트리밍은 streamGenerateContent 엔드포인트를 사용한다.
 * https://ai.google.dev/api/rest/v1beta/models/streamGenerateContent
 */

const MODEL = Deno.env.get('GEMINI_MODEL') ?? 'gemini-2.0-flash';

function apiKey(): string {
  const k = Deno.env.get('GEMINI_API_KEY');
  if (!k) throw new Error('GEMINI_API_KEY not set');
  return k;
}

export interface ChatPart {
  text: string;
}

export interface ChatTurn {
  role: 'user' | 'model';
  parts: ChatPart[];
}

export interface GenerateOptions {
  systemInstruction?: string;
  enableSearch?: boolean;
  temperature?: number;
  maxOutputTokens?: number;
}

interface Citation {
  uri?: string;
  title?: string;
}

export interface StreamEvent {
  type: 'text' | 'citation' | 'done' | 'error';
  text?: string;
  citations?: Citation[];
  error?: string;
}

/**
 * 스트리밍 generate.
 * AsyncGenerator 로 텍스트 청크와 인용을 순차 yield 한다.
 */
export async function* streamChat(
  history: ChatTurn[],
  opts: GenerateOptions = {},
): AsyncGenerator<StreamEvent> {
  const url =
    `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:streamGenerateContent?alt=sse&key=${apiKey()}`;

  const body: Record<string, unknown> = {
    contents: history,
    generationConfig: {
      temperature: opts.temperature ?? 0.4,
      maxOutputTokens: opts.maxOutputTokens ?? 2048,
    },
  };
  if (opts.systemInstruction) {
    body.systemInstruction = { parts: [{ text: opts.systemInstruction }] };
  }
  if (opts.enableSearch) {
    body.tools = [{ googleSearch: {} }];
  }

  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });

  if (!res.ok || !res.body) {
    const err = await res.text();
    yield { type: 'error', error: `Gemini error ${res.status}: ${err}` };
    return;
  }

  const reader = res.body.getReader();
  const decoder = new TextDecoder();
  let buffer = '';

  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });

    // SSE: "data: {json}\n\n"
    const events = buffer.split('\n\n');
    buffer = events.pop() ?? '';

    for (const evt of events) {
      const line = evt.trim();
      if (!line.startsWith('data:')) continue;
      const json = line.slice(5).trim();
      if (!json) continue;

      try {
        const parsed = JSON.parse(json);
        const candidate = parsed.candidates?.[0];
        const text = candidate?.content?.parts?.map((p: ChatPart) => p.text).join('') ?? '';
        if (text) yield { type: 'text', text };

        const grounding = candidate?.groundingMetadata?.groundingChunks;
        if (grounding) {
          const citations: Citation[] = grounding
            .map((c: { web?: Citation }) => c.web)
            .filter(Boolean);
          if (citations.length) yield { type: 'citation', citations };
        }
      } catch (_) {
        // 무시 (일부 청크가 깨질 수 있음)
      }
    }
  }
  yield { type: 'done' };
}
