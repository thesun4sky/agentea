---
name: agentea
description: Use to start a 3-agent tea party (Claude + codex + grok + antigravity/agy) in cmux. Initializes panes, prompts for mode (auto/manual) and agent selection, manages OAuth login flows, and migrates legacy state. Companion skills handle status/ask/review/council/brainstorming/clear/off.
argument-hint: "[on [auto|manual] [codex] [grok] [agy]]"
---

# /agentea — Multi-Agent Tea Party (ON)

3개의 외부 AI 에이전트(`codex`, `grok`, `antigravity/agy`)와 Claude Code를 cmux 멀티 pane으로 묶어
협업 세션을 시작합니다. 이 진입점은 **ON 전용**입니다. 다른 동작은 별도 서브 스킬:

| 명령 | 역할 |
|---|---|
| `/agentea-status` | 활성 에이전트 주소·상태 조회 |
| `/agentea-ask` | 메시지 전송 (기본 broadcast, 첫 토큰이 에이전트면 타겟 전송) |
| `/agentea-review` | (1+N)자 LGTM 코드 리뷰 루프 |
| `/agentea-council` | 결정 안건 투표 |
| `/agentea-brainstorming` | 다같이 아이디에이션 |
| `/agentea-clear` | `.agentea/` 산출물 + state 히스토리 리셋 |
| `/agentea-off` | 모든 pane 종료 + 비활성화 |

---

## 핵심 원칙

- **broadcast가 default** — 모든 메시지는 활성 에이전트 전체에 전송. 특정 에이전트는 명시 지정.
- **외부 에이전트는 읽기·제안 전용** — 소스 파일 수정은 Claude Code만.
- **응답은 `.agentea/` 파일에 저장** — read-screen 폴링 불필요.
- **코드/diff를 명령어에 직접 붙이지 말 것** — 파일 경로만 전달.

---

## 0. 환경 초기화 + 공유 라이브러리 로드

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

# Auto-migrate legacy state (codex_surface/grok_surface flat → agents.* nested)
_migrate_state_v1_to_v2

WORK_DIR=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
AGENTEA_DIR="$WORK_DIR/.agentea"
mkdir -p "$AGENTEA_DIR"

if ! grep -q "^\.agentea" "$WORK_DIR/.gitignore" 2>/dev/null; then
  echo ".agentea/" >> "$WORK_DIR/.gitignore"
fi

MY_SURFACE="$CMUX_SURFACE_ID"
MY_WORKSPACE="$CMUX_WORKSPACE_ID"
```

---

## 1. 인자 파싱 OR 인터랙티브 선택

**인자 있으면** 그대로 사용 (AC2):
- `/agentea on auto codex grok` → mode=auto, agents=[codex, grok]
- `/agentea on manual codex grok agy` → mode=manual, agents 전부
- 첫 토큰이 `auto`/`manual` 아니면 무시; 나머지에서 `codex`/`grok`/`agy`만 인식

**인자 없으면** AskUserQuestion 2단계 (AC1):
1. **모드 선택**: `auto` (작업 후 자동 review/council 트리거) vs `manual` (명시 호출만)
2. **에이전트 멀티셀렉트**: `codex`, `grok`, `agy` 중 1~3개 (체크박스)

```bash
# (Claude가 인자 분석 후) 결과:
SELECTED_MODE="auto"     # 또는 "manual"
SELECTED_AGENTS=(codex grok antigravity)   # 정규화된 canonical 이름
```

---

## 2. 기존 pane 탐지

```bash
declare -A EXISTING_SURFACE
for s in $(cmux tree --workspace "$MY_WORKSPACE" 2>/dev/null | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}|surface:[0-9]+'); do
  [ "$s" = "$MY_SURFACE" ] && continue
  content=$(cmux read-screen --surface "$s" --lines 8 2>/dev/null)
  # NOTE: avoid bare name 'status' — zsh has $status as a read-only shell variable
  agent_status=$(_classify_screen "$content")
  case "$agent_status" in
    ready\(codex\))        EXISTING_SURFACE[codex]="$s" ;;
    ready\(grok\))         EXISTING_SURFACE[grok]="$s" ;;
    ready\(antigravity\))  EXISTING_SURFACE[antigravity]="$s" ;;
  esac
done
```

---

## 3. 없는 에이전트만 pane 생성 + CLI 실행

선택된 에이전트 각각에 대해:

```bash
for agent in "${SELECTED_AGENTS[@]}"; do
  surface="${EXISTING_SURFACE[$agent]}"
  if [ -z "$surface" ]; then
    # 새 pane 생성 (수직 stack: 첫 에이전트는 right split, 이후는 down split)
    if [ -z "$ANCHOR_SURFACE" ]; then
      result=$(cmux new-split right --surface "$MY_SURFACE" --workspace "$MY_WORKSPACE" --focus false 2>&1)
    else
      result=$(cmux new-split down --surface "$ANCHOR_SURFACE" --workspace "$MY_WORKSPACE" --focus false 2>&1)
    fi
    surface=$(echo "$result" | grep -oE 'surface:[0-9]+' | head -1)
    ANCHOR_SURFACE="$surface"

    # 에이전트 CLI 실행
    cli=$(_resolve_agent_cli "$agent")
    cmux send --surface "$surface" "cd $WORK_DIR && $cli" >/dev/null
    cmux send-key --surface "$surface" Return >/dev/null
    echo "✅ [$agent] pane=$surface, CLI=$cli 시작"
  else
    echo "♻️  [$agent] 기존 pane 재사용: $surface"
  fi

  # state에 즉시 반영
  _save_state "{\"agents\":{\"$agent\":{\"surface\":\"$surface\",\"enabled\":true}}}"
done

echo "⏳ 에이전트 기동 대기 (8초)..."
sleep 8
```

---

## 4. 기동 상태 점검 (`_check_agent_startup` 루프)

각 선택된 에이전트에 대해:

```bash
ANY_PENDING=0
for agent in "${SELECTED_AGENTS[@]}"; do
  surface=$(_agent_surface "$agent")
  _check_agent_startup "$surface" "$agent"
  rc=$?
  case $rc in
    0) _save_state "{\"agents\":{\"$agent\":{\"status\":\"ready\"}}}" ;;
    1) _save_state "{\"agents\":{\"$agent\":{\"status\":\"unknown\"}}}" ; ANY_PENDING=1 ;;
    2) _save_state "{\"agents\":{\"$agent\":{\"status\":\"login_prompt\"}}}" ; ANY_PENDING=1 ;;
  esac
done

if [ "$ANY_PENDING" = "1" ]; then
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "⛔ 일부 에이전트 환경 설정 필요 — mode=pending 으로 저장"
  echo "  설정 완료 후 다시 /agentea 실행"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  _save_state "{\"mode\":\"pending\"}"
  exit 1
fi
```

---

## 5. 역할 안내 파일 전송

```bash
cat > "$AGENTEA_DIR/role_guide.md" << 'EOF'
## agentea 협업 규칙

당신의 역할: 코드리뷰 / 아이디에이션 / 결정 투표 협업자
1. 요청 파일 경로를 읽고 응답
2. 소스 파일 직접 수정 금지 — ISSUE: / FIX: 형식 제안만
3. 리뷰가 이슈 없으면 마지막 줄에 LGTM
4. 모든 응답은 지정된 .agentea/ 파일에 저장
EOF

for agent in "${SELECTED_AGENTS[@]}"; do
  # --verify-soft: nonce-prefixed echo check, but press Return anyway on
  # final echo-miss (rc=3) since the role_guide handshake is cheap to re-send
  # and the bigger risk is failing to deliver the message at all (grok's TUI
  # occasionally drops the echo even when input was accepted).
  # rc=2 still means strict abandon (only --verify, not used here).
  _send_to_agent "$agent" "$AGENTEA_DIR/role_guide.md 읽고 역할 확인해주세요" --verify-soft
  rc=$?
  if [ "$rc" = "3" ]; then
    echo "ℹ️  [$agent] role_guide handshake echo가 잡히지 않았지만 Return은 전송됨 (--verify-soft)."
    echo "    cmux $agent pane을 확인해서 메시지가 들어갔는지 확인하고, 필요 시:"
    echo "    /agentea-ask $agent \"$AGENTEA_DIR/role_guide.md 읽고 역할 확인해주세요\""
  fi
done
```

---

## 6. 상태 최종 저장

```bash
_save_state "$(python3 -c "
import json
print(json.dumps({
  'mode': 'on',
  'interaction_mode': '$SELECTED_MODE',
  'work_dir': '$WORK_DIR',
  'my_surface': '$MY_SURFACE',
  'agentea_dir': '$AGENTEA_DIR',
  'session_start': '$(date -u +%Y-%m-%dT%H:%M:%SZ)'
}))")"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🍵 agentea ON — interaction_mode=$SELECTED_MODE"
for agent in "${SELECTED_AGENTS[@]}"; do
  echo "  $(_status_icon ready) $agent : $(_agent_surface $agent)"
done
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "다음 명령들 사용 가능:"
echo "  /agentea-status        — 상태 조회"
echo "  /agentea-ask           — 메시지 전송 (broadcast 기본)"
echo "  /agentea-review        — 코드 리뷰 루프"
echo "  /agentea-council       — 결정 투표"
echo "  /agentea-brainstorming — 아이디에이션"
echo "  /agentea-clear         — 산출물 정리"
echo "  /agentea-off           — 세션 종료"
```

---

## 7. CRITICAL 규칙

| 규칙 | 이유 |
|---|---|
| 코드/diff를 명령어에 직접 담지 말 것 | "Pasted Content" 모드 + 에이전트 큐 오염 |
| 멀티라인 메시지 금지 — 항상 단일 라인 | 각 줄이 별도 명령으로 큐에 들어감 |
| `cmux send "msg"` + `cmux send-key Return` 분리 | `\n`은 줄바꿈이지 Enter가 아님 |
| 응답은 `.agentea/` 파일에 저장 지시 | read-screen 잘림 없이 전체 응답 수집 |
| 외부 에이전트는 소스 파일 수정 금지 | role_guide.md로 ON 시 1회 안내 |
| `_check_agent_startup` 생략 금지 | trust/login/import 프롬프트 미처리 시 응답 불능 |

---

## 8. 알려진 스타트업 인터럽트 패턴

| 에이전트 | 패턴 | 자동 처리 | 수동 처리 |
|---|---|---|---|
| codex | 폴더 신뢰 확인 | `1` + Enter 자동 | — |
| codex | OpenAI 구독 로그인 | — | 브라우저 OAuth |
| grok | xAI/Grok 로그인 | — | 브라우저 OAuth |
| agy | Gemini CLI 설정 import 제안 | `n` 자동 거절 | — |
| agy | Google 계정 로그인 | — | 브라우저 OAuth |
| 공통 | Y/N 확인 | `y` 자동 | — |
| 공통 | 미설치 | — | 설치 가이드 출력 |

### CLI 설치 확인

```bash
which codex || npm install -g @openai/codex
which grok  || echo "xAI Grok CLI 설치 방법은 xAI 공식 문서 참조"
which agy   || brew install --cask antigravity-cli
```

---

## 9. 상태 파일 스키마 (v2)

`~/.claude/agentea-state.json`:
```json
{
  "mode": "on|off|pending",
  "interaction_mode": "auto|manual",
  "work_dir": "/path/to/project",
  "my_surface": "<claude surface>",
  "agentea_dir": "/path/.agentea",
  "agents": {
    "codex":       {"surface": "...", "enabled": true,  "status": "ready"},
    "grok":        {"surface": "...", "enabled": true,  "status": "ready"},
    "antigravity": {"surface": null,  "enabled": false, "status": null}
  },
  "session_start": "ISO8601",
  "decisions": [],
  "review_sessions": []
}
```

v1 → v2 마이그레이션은 첫 `/agentea` 실행 시 자동 수행 (백업: `.bak.<epoch>`).
