SUPABASE  := supabase-beta
# "My Mac (Designed for iPad)" — iOS 시뮬레이터 없이 모바일 레이아웃으로 실행
# iOS Simulator 준비되면: SIM_ID = 35686810-DADA-43C3-B3BF-E420C50AFF8B
DEVICE_ID := 00008142-001A11560106401C

.PHONY: setup backend app check deps reset

# ────────────────────────────────────────────────────
# macOS 시스템 의존성 (ffmpeg_kit_flutter_new 요구)
# ────────────────────────────────────────────────────
deps:
	brew install fontconfig zlib fribidi harfbuzz glib pcre2 graphite2 libiconv libsamplerate srt

# ────────────────────────────────────────────────────
# DB reset 후 시뮬레이터 앱 캐시 초기화
# (make setup 이후 세션 불일치 방지)
# ────────────────────────────────────────────────────
reset:
	xcrun simctl boot 35686810-DADA-43C3-B3BF-E420C50AFF8B 2>/dev/null || true
	xcrun simctl uninstall 35686810-DADA-43C3-B3BF-E420C50AFF8B kr.matchpoint.app 2>/dev/null || true
	@echo "앱 캐시 초기화 완료. make app 으로 재설치하세요."

# ────────────────────────────────────────────────────
# 최초 1회 — Docker Desktop 실행 후
# ────────────────────────────────────────────────────
setup:
	@echo "1) Supabase 로컬 스택 기동..."
	$(SUPABASE) start
	@echo "2) 마이그레이션 + 시드 적용..."
	$(SUPABASE) db reset
	@echo ""
	@echo "SUPABASE_ANON_KEY 를 복사해서 app/.env.local 에 붙여넣으세요:"
	@$(SUPABASE) status | grep -i "publishable\|anon"

# ────────────────────────────────────────────────────
# 매일 개발 — 터미널 두 개 열기
# ────────────────────────────────────────────────────

# 터미널 1: 백엔드 (Edge Functions 핫리로드)
backend:
	@test -f supabase/functions/.env || (echo "supabase/functions/.env 파일이 없습니다. .env.example 을 복사해서 GEMINI_API_KEY 를 채우세요." && exit 1)
	$(SUPABASE) functions serve --env-file ./supabase/functions/.env

# 터미널 2: Flutter 앱 (My Mac - Designed for iPad 모바일 레이아웃)
app:
	@test -f app/.env.local || (echo "app/.env.local 파일이 없습니다. app/.env.local.example 을 복사해서 anon key 를 채우세요." && exit 1)
	cd app && flutter run -d $(DEVICE_ID) --dart-define-from-file=.env.local

# ────────────────────────────────────────────────────
# 정적 검증
# ────────────────────────────────────────────────────
check:
	cd app && flutter analyze
	cd supabase/functions && deno lint
