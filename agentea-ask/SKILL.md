---
name: agentea-ask
description: Use to send a message to the agentea tea party. By default broadcasts to ALL active agents (codex/grok/antigravity). To target a specific agent, prefix the message with the agent name (e.g., "codex ..." or "agy ..."). Requires /agentea to be ON.
argument-hint: "[<agent>] <message>"
---

# /agentea-ask — 메시지 전송 (broadcast 기본)

## 동작

| 입력 형태 | 동작 |
|---|---|
| `/agentea-ask "안녕하세요"` | 모든 활성 에이전트에게 broadcast |
| `/agentea-ask codex "이거 봐줘"` | codex pane에만 전송 |
| `/agentea-ask agy "이거 봐줘"` | antigravity pane에만 전송 |
| `/agentea-ask grok "리뷰 부탁"` | grok pane에만 전송 |

첫 토큰이 `codex`/`grok`/`antigravity`/`agy` 중 하나이면 타겟 전송, 아니면 전체 broadcast.

---

## 실행

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
[ "$MODE" != "on" ] && { echo "⚠️  agentea mode = $MODE (not on) — /agentea 로 시작하세요"; exit 0; }

# Claude는 사용자 입력 전체를 ARGS 변수로 받아 _parse_ask_target 호출
ARGS="$@"
if [ -z "$ARGS" ]; then
  echo "사용법: /agentea-ask [에이전트] <메시지>"
  echo "  예: /agentea-ask \"전체에게 안녕\""
  echo "  예: /agentea-ask codex \"이 파일 봐줘: src/foo.ts\""
  exit 0
fi

_parse_ask_target "$ARGS"

if [ -n "$PARSED_TARGET" ]; then
  # 타겟 전송
  surface=$(_agent_surface "$PARSED_TARGET")
  if [ -z "$surface" ]; then
    echo "⚠️  [$PARSED_TARGET] 비활성 — /agentea 에서 다시 활성화하세요"
    exit 1
  fi
  _send_to_agent "$PARSED_TARGET" "$PARSED_MESSAGE"
  echo "📨 [$PARSED_TARGET] ← \"$PARSED_MESSAGE\""
else
  # broadcast
  _broadcast "$PARSED_MESSAGE"
fi
```

---

## CRITICAL 규칙

- 메시지에 줄바꿈 포함 금지 — `cmux send`는 단일 라인만 안전
- 코드/diff 직접 붙이지 말 것 → 파일에 저장 후 경로 전달:
  ```bash
  echo "this code" > .agentea/scratch.txt
  /agentea-ask codex ".agentea/scratch.txt 읽고 검토"
  ```
