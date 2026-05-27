---
name: agentea-status
description: Use to check the live status of an active agentea session — shows surface addresses, real-time agent readiness (ready/busy/login/error), interaction_mode, and a short screen preview for each active agent. Requires /agentea to be ON.
argument-hint: ""
---

# /agentea-status — 세션 주소 + 실시간 상태 조회

```bash
# Load shared helpers — portable across skill / plugin / install.sh layouts
# Discover lib/common.sh — prefer skill-dir / install.sh, else highest plugin version
_AGENTEA_LIB=""
for _p in \
  "$HOME/.claude/skills/agentea/lib/common.sh" \
  "$HOME/.claude/agentea-src/lib/common.sh"; do
  [ -f "$_p" ] && _AGENTEA_LIB="$_p" && break
done
if [ -z "$_AGENTEA_LIB" ]; then
  # Plugin install: pick highest semver dir (1.0.10 > 1.0.2 > 1.0.0)
  _AGENTEA_LIB=$(ls -d "$HOME/.claude/plugins/cache/agentea/agentea/"*/lib/common.sh 2>/dev/null | sort -rV | head -1)
fi
[ -z "$_AGENTEA_LIB" ] || [ ! -f "$_AGENTEA_LIB" ] && { echo "ERROR: agentea lib/common.sh not found — reinstall via /plugin install agentea"; exit 1; }
source "$_AGENTEA_LIB"

_load_state || { echo "⚠️  agentea 세션 없음 — /agentea 로 시작하세요"; exit 0; }

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🍵 agentea STATUS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  mode             : $MODE"
echo "  interaction_mode : $INTERACTION_MODE"
echo "  프로젝트         : $WORK_DIR"
echo ""
echo "  Surface 주소"
echo "  ┌─────────────────────────────────"
echo "  │ Claude : $MY_SURFACE"
for agent in "${KNOWN_AGENTS[@]}"; do
  # Read enabled/surface from state file (zsh + bash compatible)
  read_result=$(python3 -c "
import json
try:
    d = json.load(open('$STATE_FILE'))
    info = d.get('agents',{}).get('$agent',{})
    print((info.get('surface') or '') + '\t' + ('true' if info.get('enabled') else 'false'))
except Exception:
    print('\tfalse')
")
  surface="${read_result%%	*}"
  enabled="${read_result##*	}"

  if [ "$enabled" != "true" ] || [ -z "$surface" ]; then
    printf "  │ %-12s : (disabled)\n" "$agent"
    continue
  fi

  screen=$(cmux read-screen --surface "$surface" --lines 5 2>/dev/null)
  # NOTE: avoid bare name 'status' — zsh has $status as a read-only shell variable
  agent_status=$(_classify_screen "$screen")
  icon=$(_status_icon "$agent_status")
  printf "  │ %-12s : %s  %s %s\n" "$agent" "$surface" "$icon" "$agent_status"
done
echo "  └─────────────────────────────────"

echo ""
echo "  화면 미리보기 (각 활성 에이전트, 최근 3줄)"
for agent in "${KNOWN_AGENTS[@]}"; do
  surface=$(_agent_surface "$agent")
  [ -z "$surface" ] && continue
  echo "  [$agent]"
  cmux read-screen --surface "$surface" --lines 5 2>/dev/null | tail -3 | sed 's/^/    /'
done
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
```

### 상태 아이콘

| 아이콘 | 의미 |
|---|---|
| ✅ | ready — 정상 대기 중 |
| ⏳ | busy — 응답 생성 중 |
| 🔄 | import_offer — Gemini CLI 설정 import 제안 (agy) |
| ⚠️ | trust_prompt / confirm_yn — 확인 프롬프트 대기 |
| 🔐 | login_prompt — 구독 계정 OAuth 필요 |
| 🔴 | error_state — 에러 (재시작 필요) |
| 💀 | unreachable — surface 접근 불가 (pane 닫혔을 가능성) |
| ❓ | unknown — 분류되지 않은 화면 (직접 확인) |
