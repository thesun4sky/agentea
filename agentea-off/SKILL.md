---
name: agentea-off
description: Use to fully shut down an agentea session — sends Ctrl+C and exit to each active agent pane, closes all cmux panes, clears agent surfaces from state, and sets mode to off. Preserves .agentea/ artifacts. Use /agentea-clear first if you want to wipe artifacts too.
argument-hint: ""
---

# /agentea-off — 세션 종료 + pane 정리

## 동작 순서

1. 각 활성 에이전트 pane에 `Ctrl+C` 전송 (현재 작업 중단)
2. `exit` 명령 전송 (에이전트 CLI 종료)
3. cmux pane 실제로 닫기 (`cmux close-pane` 또는 동등)
4. state에서 `agents.*.surface = null`, `enabled = false`로 클리어
5. `mode = "off"` 설정

⚠️  `.agentea/` 폴더 내용은 보존 (필요 시 `/agentea-clear`로 별도 정리)

---

## 실행

```bash
source ~/.claude/skills/agentea/lib/common.sh || {
  echo "ERROR: agentea lib/common.sh not found"
  exit 1
}

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

# 각 pane에 Ctrl+C + exit 후 닫기
for entry in "${SURFACES_TO_CLOSE[@]}"; do
  agent="${entry%%:*}"
  surface="${entry##*:}"
  echo "  [$agent] $surface 종료 중..."
  # Ctrl+C로 현재 prompt/작업 취소
  cmux send-key --surface "$surface" C-c >/dev/null 2>&1 || true
  sleep 1
  # CLI 종료
  cmux send --surface "$surface" "exit" >/dev/null 2>&1 || true
  cmux send-key --surface "$surface" Return >/dev/null 2>&1 || true
  sleep 1
  # pane 닫기 (cmux 명령 이름은 환경에 따라 다를 수 있음 — close-pane 시도)
  cmux close-pane --surface "$surface" >/dev/null 2>&1 \
    || cmux kill-pane --surface "$surface" >/dev/null 2>&1 \
    || echo "    ⚠️  pane 자동 종료 실패 — cmux에서 수동 종료 필요"
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
echo "  닫은 pane: ${#SURFACES_TO_CLOSE[@]}"
echo "  state.mode = off"
echo "  .agentea/ 폴더는 보존됨 (필요 시 /agentea-clear 또는 수동 삭제)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
```

---

## CRITICAL 규칙

- 외부 에이전트 작업 중에 실행하면 응답 손실 가능 → 종료 전 작업 마무리 권장
- `cmux close-pane` 명령 이름은 환경에 따라 다를 수 있으니 fallback 포함
- `.agentea/` 산출물은 자동으로 삭제하지 않음 (의도: 검토용 보존)
- 모드가 `pending`(설정 미완료)이어도 정리 동작은 진행 (잔여 pane 청소)
