---
name: agentea-clear
description: Use to clear the .agentea/ working folder (review/council/brainstorm artifacts) and reset state history (decisions, review_sessions arrays). Does NOT close cmux panes or change mode. Use between distinct work sessions to start fresh without restarting agents.
argument-hint: ""
---

# /agentea-clear — `.agentea/` 산출물 + state 히스토리 리셋

## 범위

| 정리 대상 | 동작 |
|---|---|
| `.agentea/` 폴더 내 모든 파일 | 삭제 (`role_guide.md` 제외) |
| `state.decisions` | 빈 배열로 리셋 |
| `state.review_sessions` | 빈 배열로 리셋 |
| pane / 에이전트 프로세스 | 그대로 유지 |
| `state.mode` / `agents.*` | 그대로 유지 |

→ **목적**: 다음 작업 세션을 깨끗하게 시작 (이전 라운드 잔여물 없이)

---

## 실행

```bash
source ~/.claude/skills/agentea/lib/common.sh || {
  echo "ERROR: agentea lib/common.sh not found"
  exit 1
}

_load_state || { echo "⚠️  agentea 세션 없음 — /agentea 로 시작하세요"; exit 0; }
[ "$MODE" != "on" ] && { echo "⚠️  agentea mode = $MODE — /agentea 로 시작하세요"; exit 0; }

# .agentea/ 내용 정리 (role_guide.md 제외)
COUNT=0
if [ -d "$AGENTEA_DIR" ]; then
  for f in "$AGENTEA_DIR"/*; do
    base=$(basename "$f")
    [ "$base" = "role_guide.md" ] && continue
    rm -rf "$f"
    COUNT=$((COUNT+1))
  done
fi

# state 히스토리 리셋
_save_state '{"decisions": [], "review_sessions": []}'

echo "🧹 agentea-clear 완료"
echo "  삭제 파일/폴더: $COUNT"
echo "  state.decisions, state.review_sessions 리셋"
echo "  (mode, agents, role_guide.md 는 유지)"
```

---

## CRITICAL 규칙

- pane이나 에이전트 프로세스는 건드리지 않음 → 즉시 다음 작업 가능
- 완전 종료가 필요하면 `/agentea-off` 사용
- 백업이 필요한 산출물은 미리 다른 곳으로 옮긴 후 실행
