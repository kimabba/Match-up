<div align="center">

# ⚽ Match·Up 🎾

**축구·풋살·테니스 동호인을 위한 모바일 우선 웹앱**

> 주말마다 같이 뛸 사람을 찾고 있나요?
> 축구·풋살부터 테니스까지, 내 근처 모임부터 대회까지 한눈에.


</div>

---

## 📌 한 눈에 보기

5개 탭(홈/대회/룰북/동호회/MY) + 5단계 온보딩으로 구성된 **모바일 위주 SPA**. 종목(축구·풋살 ↔ 테니스)에 따라 액센트 컬러가 동적으로 바뀌는 **sport-aware 테마**가 핵심.

| 탭 | 설명 | v1 상태 |
|---|---|:---:|
| 🏠 **홈** | 추천 대회 + 내 근처 코트 + 오늘의 룰 퀴즈 | ✅ |
| 🏆 **대회** | 모집 글 리스트, 필터(종목/시기/지역), 진행률, 마감임박 자동 | ✅ |
| 📖 **룰북** | 종목별 룰 카테고리 + 자주 찾는 룰 FAQ | ✅ |
| 👥 **동호회** | 클럽/커뮤니티 | 🔜 placeholder |
| 👤 **MY** | 사용자 prefs + 약관 | 🔜 placeholder |

**온보딩 5단계**: 스플래시 → 닉네임 → 활동 지역(서울 16개 구) → 주 종목 → 실력(입문/중급/상급)

---

## 🎨 디자인 토큰

```ts
navy:   #1E3A8A   // Primary
tennis: #FF6B35   // 🎾 테니스 모드 액센트
futsal: #22C55E   // ⚽ 축구·풋살 모드 액센트
kakao:  #FEE500   // 카카오 버튼
bg:     #F5F7FB   // 모바일 배경

font:   Pretendard 400 / 600 / 700
radius: 카드 16px / 칩 풀 라운드 / 버튼 12px
```

종목(`tennis | futsal`)에 따라 카드·뱃지·그라데이션 색이 **전역적으로 동시에** 바뀝니다 (`SportContext` + Tailwind variant).

---

## 🚦 v1 vs v2

| 영역 | v1 (이번 MVP) | v2 (다음) |
|---|---|---|
| 데이터 | 정적 JSON (`src/data/*.json`) | 백엔드 API |
| 챗봇 | placeholder ("준비 중") | 실제 코치봇 (Gemini) |
| 인증 | localStorage prefs | 카카오 OAuth |
| 동호회 탭 | placeholder | 풀 기능 |
| MY 탭 | 기본 표시 | 통계·즐겨찾기·신청 이력 |
| 호스팅 | Cloudflare Pages 또는 Vercel (Phase 0 결정) | 동일 |

---

## 🛠️ 기술 스택

| 영역 | 선택 |
|---|---|
| 언어 | **TypeScript** (strict, `noUncheckedIndexedAccess`) |
| 프론트 | Phase 0 [`SSF-226`](https://linear.app/ssfak/issue/SSF-226)에서 Figma Make export 분석 후 확정<br/>(가설: Vite + React + Tailwind + shadcn/ui) |
| 스타일 | **Tailwind CSS** + **Pretendard** |
| 상태 | React Context + localStorage |
| 라우터 | TBD (스택 결정에 따라) |
| 데이터 | 정적 JSON → `src/lib/data.ts` 추상 레이어 |
| 패키지 매니저 | **pnpm** 9 |
| 런타임 | Node.js ≥ 20 LTS |
| CI | GitHub Actions (lint + typecheck + build) |
| 호스팅 | Phase 0 [`SSF-229`](https://linear.app/ssfak/issue/SSF-229)에서 결정 |
| 작업 추적 | [Linear](https://linear.app/ssfak/project/matchup-web-v1-3574989af78c) |

---

## 📊 진행 상태

```
✅  Phase 0 — 부트스트랩       (5)  ░░░░░░░░░░  진행 중
⬜  Phase 1 — 디자인 시스템    (6)
⬜  Phase 2 — 라우팅 + 데이터  (3)
⬜  Phase 3 — 온보딩           (3)
⬜  Phase 4 — 홈 탭            (3)
⬜  Phase 5 — 대회 탭          (4)
⬜  Phase 6 — 룰북 탭          (4)
⬜  Phase 7 — 마무리           (4)
                       총 32 이슈
```

📅 **MVP 마일스톤**: 2026-06-15 (3탭 출시)

---

## 🚀 개발 시작하기

### 사전 요구사항

- **Node.js** 20.x 이상 ([`.nvmrc`](./.nvmrc) 참고)
- **pnpm** 9.x — `npm install -g pnpm`

### 설치

```bash
git clone https://github.com/kimabba/matchup-web.git
cd matchup-web
pnpm install
```

### 개발 서버

```bash
pnpm dev
```

> 🚧 Phase 0의 [`SSF-226`](https://linear.app/ssfak/issue/SSF-226)에서 dev/build 스크립트가 채워집니다.

### 검증

```bash
pnpm lint        # ESLint
pnpm typecheck   # TypeScript
pnpm build       # 프로덕션 빌드
```

---

## 📂 프로젝트 구조 (목표)

```
matchup-web/
├─ src/
│  ├─ App.tsx
│  ├─ types.ts                    # Sport/Tournament/Venue/Rule 등 도메인 타입
│  ├─ lib/
│  │  ├─ sport-context.tsx        # 종목 전역 상태 (SportContext)
│  │  ├─ user-prefs.ts            # localStorage 사용자 prefs
│  │  └─ data.ts                  # 데이터 fetch 추상화 (v2에서 API로 교체)
│  ├─ data/                       # 정적 시드 JSON (대회/코트/룰/FAQ/퀴즈)
│  ├─ components/                 # 디자인 시스템 (15개)
│  │  ├─ SportToggle.tsx
│  │  ├─ TournamentCard.tsx
│  │  ├─ VenueCard.tsx
│  │  ├─ FilterChipBar.tsx
│  │  ├─ BottomNavBar.tsx
│  │  └─ ...
│  ├─ screens/
│  │  ├─ HomeScreen.tsx
│  │  ├─ TournamentListScreen.tsx
│  │  ├─ TournamentDetailScreen.tsx
│  │  ├─ RulebookScreen.tsx
│  │  ├─ RuleCategoryDetail.tsx
│  │  ├─ ClubPlaceholderScreen.tsx
│  │  ├─ MyScreen.tsx
│  │  ├─ onboarding/              # 5단계 온보딩
│  │  └─ _dev/Gallery.tsx         # 개발 빌드 한정 컴포넌트 갤러리
│  └─ styles/
│     └─ globals.css
├─ public/
│  ├─ fonts/                      # Pretendard self-host
│  └─ og-image.png                # 카카오 공유 미리보기
├─ docs/
│  └─ decisions/                  # ADR (Architecture Decision Records)
├─ .github/workflows/
│  └─ ci.yml
├─ tailwind.config.ts
├─ tsconfig.json
└─ package.json
```

---

## 🔄 작업 워크플로

모든 작업은 [Linear "Match·Up Web v1"](https://linear.app/ssfak/project/matchup-web-v1-3574989af78c)에서 추적됩니다.

```
1. Linear 이슈 (SSF-XXX) → status: In Progress
2. 새 브랜치: feature/SSF-XXX-짧은설명
3. 코드 작성
4. 커밋 메시지: "type(SSF-XXX): 설명"
5. PR 생성 (base=main)
6. 1+ approval + CI 그린
7. squash merge → 자동 배포
8. Linear → status: Done
```

### 브랜치 보호

`main` 브랜치는 GitHub 단에서 보호됩니다:
- ✅ Pull Request 필수
- ✅ 1+ approving review
- ✅ CI 통과 (lint + typecheck + build)
- ❌ Force push 차단
- ❌ 직접 삭제 차단

---

## 🎨 디자인 참고

[Figma Make: Futsal-Tennis-Community-App](https://www.figma.com/make/ZlknKCxB548GDQT9i1tscH/Futsal-Tennis-Community-App)

모바일 위주 디자인 → 데스크톱은 가운데 `max-w-md`(420px) 컨테이너 + 좌우 그라데이션 배경으로 반응형.

---

## 🤝 기여

이 레포는 **비공개**입니다. 팀원으로 초대받은 분만 PR을 만들 수 있습니다.

### PR 체크리스트

- [ ] Linear 이슈와 연결 (커밋 메시지에 `SSF-XXX` 포함)
- [ ] `pnpm lint` 통과
- [ ] `pnpm typecheck` 통과
- [ ] `pnpm build` 성공
- [ ] viewport 375 / 1024 / 1440 모두 확인
- [ ] 종목 토글 회귀 (해당 화면일 시 양쪽 색 모두 확인)

### 커밋 메시지 컨벤션

```
type(SSF-XXX): 한 줄 요약

상세 설명 (선택)

Co-Authored-By: ...
```

`type`: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `style`

---

## 📜 라이센스

[MIT](./LICENSE) © 2026 ssfak

---

<div align="center">

**계획 문서**: [`~/.claude/plans/fuzzy-spinning-thimble.md`](https://linear.app/ssfak/project/matchup-web-v1-3574989af78c)
**Linear 프로젝트**: [Match·Up Web v1](https://linear.app/ssfak/project/matchup-web-v1-3574989af78c)
**문의**: 이슈 또는 Linear 프로젝트 댓글

</div>
