# Match-up Knowledge Base

이 폴더는 프로젝트의 현재 상태를 문서화합니다.
`docs/rules/`가 "어떻게 작업할 것인가"를 정의한다면, `docs/kb/`는 "현재 무엇이 있는가"를 설명합니다.

## 파일 목록

| 파일 | 내용 |
|---|---|
| `architecture.md` | 시스템 아키텍처, Edge Function 목록, 인증 레이어 |
| `database.md` | 전체 테이블 스키마, RLS, 트리거, 마이그레이션 이력 |
| `domain-tennis.md` | 테니스 도메인: 협회, 등급, 부서코드 체계 |
| `domain-futsal.md` | 풋살 도메인: 협회, 등급 체계 |
| `clubs.md` | 클럽 관리 시스템: 생성→승인 워크플로우, 멤버십, 가입 신청 |
| `crawler.md` | 크롤러 시스템: crawl-dispatch, 파서, 소스 관리 |
| `flutter-app.md` | Flutter 앱 구조: 라우팅, 상태관리, API 클라이언트 |
| `ai-chat.md` | AI 챗봇: Gemini + RAG + SSE 스트리밍 |

## 관리 원칙

1. 코드가 바뀌면 KB도 업데이트한다 — 특히 테이블 추가/변경, Edge Function 추가, 새 기능 도입 시.
2. 중복보다 링크 — 같은 내용을 여러 파일에 쓰지 않고, 참조로 연결한다.
3. 사실 중심 — "이렇게 해야 한다"가 아니라 "현재 이렇게 되어 있다"를 기술한다.
4. 200줄 이하 — 파일당 200줄을 넘기면 분리를 고려한다.
