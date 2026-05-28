# AI 챗봇 시스템

## 아키텍처

```
Flutter (SSE) → chat Edge Function
                    ├── 의도 분류 (Gemini)
                    ├── pgvector 시맨틱 검색 (RAG)
                    ├── Gemini Search Grounding (웹 검색)
                    └── SSE 스트리밍 응답
```

## 핵심 구성

| 요소 | 설명 |
|---|---|
| 모델 | gemini-2.0-flash |
| 임베딩 | gemini-embedding-001 (768 차원) |
| 벡터DB | pgvector (tournaments.embedding) |
| 스트리밍 | Server-Sent Events (SSE) |

## RAG 파이프라인

1. **임베딩 생성** — embed-pending Edge Function (pg_cron 주기 실행)
   - `embedding IS NULL`인 published 대회 조회
   - Gemini 임베딩 API로 768d 벡터 생성
   - tournaments.embedding에 저장

2. **검색** — `tournaments_semantic_search` RPC
   - 사용자 쿼리 → 임베딩 → cosine similarity 상위 5건
   - `p_only_my_grade: false` (등급 필터 제거, 관련성 우선)

3. **응답 생성** — RAG 컨텍스트 + Search Grounding으로 답변 생성

## 의도 분류
- `intent_examples` 테이블의 예시 기반
- 대회 검색, 클럽 문의, 규칙 질문, 일반 대화 등 분류

## 비용 제어
- `chat_rate_limit` 테이블로 사용자별 요청 제한
- `qa_cache` — 유사 질문 캐시

## Flutter 구현
- `ChatScreen` — SSE 스트림 수신, 마크다운 렌더링
- `ApiService.chat()` — http.Request로 SSE 스트리밍, ChatStreamEvent yield
- 대화 이력: chat-history Edge Function (GET/DELETE)
