---
name: agentea-off
description: Use to fully shut down an agentea session — sends Ctrl+C and exit to each active agent pane, closes all cmux surfaces, clears agent surfaces from state, and sets mode to off. Preserves .agentea/ artifacts. Use /agentea-clear first if you want to wipe artifacts too.
argument-hint: ""
---

# /agentea-off — 세션 종료 + pane 정리

## 동작 순서

1. 각 활성 에이전트 pane에 `Ctrl+C` 전송 (현재 작업 중단)
2. `exit` 명령 전송 (에이전트 CLI 종료)
3. `cmux close-surface --surface <id>` 로 pane 닫기
4. state에서 `agents.*.surface = null`, `enabled = false`로 클리어
5. `mode = "off"` 설정

⚠️  `.agentea/` 폴더 내용은 보존 (필요 시 `/agentea-clear`로 별도 정리)

---

## 실행

```bash
# Load shared helpers — portable across skill / plugin / install.sh layouts
_AGENTEA_LIB=""
for _p in \
  "$HOME/.claude/skills/agentea/lib/common.sh" \
  "$HOME/.claude/plugins/cache/agentea/agentea/"*/lib/common.sh \
  "$HOME/.claude/agentea-src/lib/common.sh"; do
  [ -f "$_p" ] && _AGENTEA_LIB="$_p" && break
done
[ -z "$_AGENTEA_LIB" ] && { echo "ERROR: agentea lib/common.sh not found — reinstall via /plugin install agentea"; exit 1; }
source "$_AGENTEA_LIB"

_load_state || { echo "⚠️  agentea 세션 없음"; exit 0; }

# mode != on 이어도 진행 (pending 상태 정리 필요)
echo "🛑 agentea OFF 진행 중..."

# 활성/등록된 모든 에이전트 surface 수집 (mode와 무관, surface만 있으면 정리)
SURFACES_TO_CLOSE=()
for agent in "${KNOWN_AGENTS[@]}"; do
  surface=$(_agent_surface "$agent")
  [ -z "$surface" ] && continue
  SURFACES_TO_CLOSE+=("$agent:$surface")
done

# 각 pane에 Ctrl+C + exit 후 surface 닫기
for entry in "${SURFACES_TO_CLOSE[@]}"; do
  agent="${entry%%:*}"
  surface="${entry##*:}"
  echo "  [$agent] $surface 종료 중..."
  # Ctrl+C로 현재 prompt/작업 취소
  cmux send-key --surface "$surface" C-c >/dev/null 2>&1 || true
  sleep 0.5
  # CLI 종료
  cmux send --surface "$surface" "exit" >/dev/null 2>&1 || true
  sleep 0.3
  cmux send-key --surface "$surface" Return >/dev/null 2>&1 || true
  sleep 0.5
  # surface 닫기 — cmux close-surface (올바른 명령)
  if cmux close-surface --surface "$surface" >/dev/null 2>&1; then
    echo "  [$agent] ✅ surface 닫힘"
  else
    echo "  [$agent] ⚠️  surface 닫기 실패 (이미 닫혔거나 cmux에서 수동 종료 필요)"
  fi
done

# state 클리어
_save_state '{
  "mode": "off",
  "agents": {
    "codex":       {"surface": null, "enabled": false, "status": null},
    "grok":        {"surface": null, "enabled": false, "status": null},
    "antigravity": {"surface": null, "enabled": false, "status": null}
  }
}'

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ agentea OFF"
echo "  닫은 surface: ${#SURFACES_TO_CLOSE[@]}"
echo "  state.mode = off"
echo "  .agentea/ 폴더는 보존됨 (필요 시 /agentea-clear 또는 수동 삭제)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
```

---

## CRITICAL 규칙

- 외부 에이전트 작업 중에 실행하면 응답 손실 가능 → 종료 전 작업 마무리 권장
- cmux에서 surface 닫기: `cmux close-surface --surface <id>` (`close-pane`은 존재하지 않음)
- `.agentea/` 산출물은 자동으로 삭제하지 않음 (의도: 검토용 보존)
- 모드가 `pending`(설정 미완료)이어도 정리 동작은 진행 (잔여 pane 청소)
