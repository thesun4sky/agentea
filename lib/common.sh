# agentea/lib/common.sh — shared helpers for all agentea-* subskills
#
# REQUIRED USAGE in every subskill SKILL.md:
#   source ~/.claude/skills/agentea/lib/common.sh || {
#     echo "ERROR: agentea lib/common.sh not found at ~/.claude/skills/agentea/lib/common.sh"
#     echo "       Run /agentea to reinstall, or check installation."
#     exit 1
#   }
#
# Schema v2 (current):
#   ~/.claude/agentea-state.json
#   {
#     "mode": "on|off|pending",
#     "interaction_mode": "auto|manual",
#     "work_dir": "...",
#     "my_surface": "...",
#     "agentea_dir": "...",
#     "agents": {
#       "codex":       {"surface": "...", "enabled": bool, "status": "..."},
#       "grok":        {"surface": "...", "enabled": bool, "status": "..."},
#       "antigravity": {"surface": "...", "enabled": bool, "status": "..."}
#     },
#     "session_start": "ISO8601",
#     "decisions": [],
#     "review_sessions": []
#   }

# Guard against double source
[ -n "${AGENTEA_COMMON_LOADED:-}" ] && return 0
AGENTEA_COMMON_LOADED=1

STATE_FILE="$HOME/.claude/agentea-state.json"
KNOWN_AGENTS=(codex grok antigravity)
# Alias map handled by _resolve_agent_alias case statement below.

# -----------------------------------------------------------------------------
# State management
# -----------------------------------------------------------------------------

# _load_state — read state JSON into shell vars: MODE, INTERACTION_MODE,
#               WORK_DIR, MY_SURFACE, AGENTEA_DIR, plus AGENT_<NAME>_SURFACE etc.
_load_state() {
  [ ! -f "$STATE_FILE" ] && return 1
  eval "$(python3 - "$STATE_FILE" <<'PY'
import json, sys, shlex
try:
    with open(sys.argv[1]) as f: d = json.load(f)
except Exception as e:
    print(f'echo "ERROR: state file corrupt: {e}" >&2; return 1')
    sys.exit(0)
def emit(k, v):
    if v is None: v = ""
    print(f'{k}={shlex.quote(str(v))}')
emit('MODE', d.get('mode'))
emit('INTERACTION_MODE', d.get('interaction_mode', 'auto'))
emit('WORK_DIR', d.get('work_dir'))
emit('MY_SURFACE', d.get('my_surface'))
emit('AGENTEA_DIR', d.get('agentea_dir'))
agents = d.get('agents', {})
for name, info in agents.items():
    n = name.upper()
    emit(f'AGENT_{n}_SURFACE', info.get('surface'))
    emit(f'AGENT_{n}_ENABLED', 'true' if info.get('enabled') else 'false')
    emit(f'AGENT_{n}_STATUS', info.get('status'))
PY
)"
}

# _save_state <json-patch> — merge json fragment into state file
# Example: _save_state '{"mode":"on"}'
_save_state() {
  local patch="$1"
  python3 - "$STATE_FILE" "$patch" <<'PY'
import json, sys, os
path, patch_json = sys.argv[1], sys.argv[2]
patch = json.loads(patch_json)
try:
    with open(path) as f: d = json.load(f)
except Exception:
    d = {}
def deep_merge(a, b):
    for k, v in b.items():
        if isinstance(v, dict) and isinstance(a.get(k), dict):
            deep_merge(a[k], v)
        else:
            a[k] = v
deep_merge(d, patch)
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, 'w') as f: json.dump(d, f, indent=2)
PY
}

# _migrate_state_v1_to_v2 — auto-migrate flat codex_surface/grok_surface schema
#                           to nested agents.* schema. Idempotent.
_migrate_state_v1_to_v2() {
  [ ! -f "$STATE_FILE" ] && return 0
  python3 - "$STATE_FILE" <<'PY'
import json, sys, shutil, time, os
path = sys.argv[1]
try:
    with open(path) as f: d = json.load(f)
except Exception:
    sys.exit(0)

needs_migration = ('codex_surface' in d or 'grok_surface' in d) and 'agents' not in d
if not needs_migration:
    if 'agents' in d:
        for n in ('codex','grok','antigravity'):
            d['agents'].setdefault(n, {'surface': None, 'enabled': False, 'status': None})
        d.setdefault('interaction_mode', 'auto')
        with open(path, 'w') as f: json.dump(d, f, indent=2)
    sys.exit(0)

backup = f'{path}.bak.{int(time.time())}'
shutil.copy2(path, backup)

agents = {}
for legacy in ('codex','grok'):
    surf = d.pop(f'{legacy}_surface', None)
    agents[legacy] = {
        'surface': surf,
        'enabled': bool(surf),
        'status': None,
    }
agents['antigravity'] = {'surface': None, 'enabled': False, 'status': None}
d['agents'] = agents
d.setdefault('interaction_mode', 'auto')

with open(path, 'w') as f: json.dump(d, f, indent=2)
print(f'✅ Migrated state to v2 schema (backup: {os.path.basename(backup)})')
PY
}

# -----------------------------------------------------------------------------
# Screen classification (used by status, on, review, etc.)
# -----------------------------------------------------------------------------

# _classify_screen <content> — categorize agent terminal screen
#   Returns one of: ready | ready(codex) | ready(grok) | ready(antigravity)
#                   busy | trust_prompt | confirm_yn | login_prompt
#                   error_state | import_offer | unknown | unreachable
_classify_screen() {
  local content="$1"
  [ -z "$content" ] && echo "unreachable" && return

  # Ready FIRST — common TUI prompt patterns indicate idle/ready state.
  # We look at the last few lines for an interactive prompt marker.
  local tail_content=$(echo "$content" | tail -8)
  if echo "$tail_content" | grep -qE '(^|\s)(›|❯|>)\s|to change|shortcuts|always-approve|Build · '; then
    if echo "$content" | grep -qE 'Codex|gpt-[0-9]|OpenAI'; then echo "ready(codex)"; return; fi
    if echo "$content" | grep -qE 'Grok Build|Grok·|xAI'; then echo "ready(grok)"; return; fi
    if echo "$content" | grep -qE 'Antigravity|Gemini [0-9]\.[0-9]|Google AI'; then echo "ready(antigravity)"; return; fi
  fi

  # Order matters — more specific patterns first
  echo "$content" | grep -qiE 'Do you trust|authors of files|신뢰하|trust this folder' && echo "trust_prompt" && return
  # import_offer BEFORE confirm_yn (Gemini import is also a Y/N prompt — must classify as import)
  # Match both with-and-without "CLI" wording, and standalone "Gemini settings ... [Y/n]" forms.
  echo "$content" | grep -qiE 'Gemini CLI .* (import|migrate)|(import|migrate).*Gemini( CLI)? (settings|configuration|config)|migrate.*Gemini settings|Import existing Gemini' && echo "import_offer" && return
  # Also catch "Gemini settings ... [Y/n]" prompt form even when 'import'/'migrate' verb is implicit
  if echo "$content" | grep -qiE 'Gemini( CLI)? settings'; then
    echo "$tail_content" | grep -qE '\[Y/[nN]\]|\(yes/no\)' && echo "import_offer" && return
  fi
  # confirm_yn requires prompt marker near end (not arbitrary yes/no text in body)
  # Case-insensitive so both [Y/n] and [y/N] forms match.
  echo "$tail_content" | grep -qiE '\[y/n\][[:space:]]*[?:]?[[:space:]]*$|\(y/n\)[[:space:]]*[?:]?[[:space:]]*$|\(yes/no\)[[:space:]]*[?:]?[[:space:]]*$' && echo "confirm_yn" && return
  # login_prompt requires action context, not bare 'email'/'token' words
  echo "$tail_content" | grep -qiE '(please|to continue|required to|first need to) (log|sign).?in|Enter your (API|access) (key|token)|authentication required|authorize this device|press Enter to.*(login|sign|auth)' && echo "login_prompt" && return
  # error_state — anchored to line start or specific failure messages
  echo "$content" | grep -qE '^(Error:|ENOENT|.+command not found|.+permission denied)|spawn ENOENT|process exited with code|cannot start' && echo "error_state" && return
  # busy — spinner glyphs at line start, or explicit progress verbs
  echo "$content" | grep -qE '^\s*[•·▸▹►⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]|^(Thinking|Exploring|Running|Working|Generating)\.\.\.|stop  \[' && echo "busy" && return

  # Fallback ready — broader keyword match (last resort)
  echo "$content" | grep -qE 'Codex|gpt-[0-9]' && echo "ready(codex)" && return
  echo "$content" | grep -qE 'Grok Build|Grok·' && echo "ready(grok)" && return
  echo "$content" | grep -qE 'Antigravity CLI|Gemini [0-9]\.[0-9]' && echo "ready(antigravity)" && return

  # Non-empty content that matches no known pattern → unknown (do NOT fall back to ready)
  echo "unknown"
}

_status_icon() {
  case "$1" in
    ready*)                   echo "✅" ;;
    busy)                     echo "⏳" ;;
    trust_prompt|confirm_yn)  echo "⚠️ " ;;
    import_offer)             echo "🔄" ;;
    login_prompt)             echo "🔐" ;;
    error_state)              echo "🔴" ;;
    unreachable)              echo "💀" ;;
    unknown)                  echo "❓" ;;
    *)                        echo "❓" ;;
  esac
}

# -----------------------------------------------------------------------------
# Agent resolution & messaging
# -----------------------------------------------------------------------------

# _resolve_agent_cli <name> — map canonical name → actual CLI executable
# Note: agy uses --dangerously-skip-permissions to prevent mid-task approval prompts
_resolve_agent_cli() {
  case "$1" in
    codex)        echo "codex" ;;
    grok)         echo "grok" ;;
    antigravity)  echo "agy --dangerously-skip-permissions" ;;
    *)            echo "" ;;
  esac
}

# _resolve_agent_alias <alias> — normalize alias to canonical name; empty if not an agent
_resolve_agent_alias() {
  case "$(echo "$1" | tr '[:upper:]' '[:lower:]')" in
    codex)       echo "codex" ;;
    grok)        echo "grok" ;;
    antigravity) echo "antigravity" ;;
    agy)         echo "antigravity" ;;
    *)           echo "" ;;
  esac
}

# _agent_surface <name> — get surface for a canonical agent name
# Reads from STATE_FILE directly so it works in both bash and zsh
# (zsh does not support ${!var} indirect expansion).
_agent_surface() {
  local name="$1"
  [ -z "$name" ] && return 1
  python3 -c "
import json, sys
try:
    d = json.load(open('$STATE_FILE'))
    print(d.get('agents',{}).get('$name',{}).get('surface') or '')
except Exception:
    print('')
"
}

# _send_to_agent <name> <msg> — send single-line message + Return to agent
_send_to_agent() {
  local name="$1" msg="$2"
  local surface=$(_agent_surface "$name")
  if [ -z "$surface" ]; then
    echo "⚠️  [$name] surface not found in state" >&2
    return 1
  fi
  cmux send --surface "$surface" "$msg" >/dev/null
  sleep 0.3  # Wait for text to land in terminal buffer before pressing Return
  cmux send-key --surface "$surface" Return >/dev/null
}

# _active_agents — print canonical names of enabled+reachable agents (one per line)
# Reads from STATE_FILE directly so it works in bash and zsh.
_active_agents() {
  python3 -c "
import json
try:
    d = json.load(open('$STATE_FILE'))
    for n, info in d.get('agents', {}).items():
        if info.get('enabled') and (info.get('status') or '').startswith(('ready','busy')):
            print(n)
except Exception:
    pass
"
}

# _broadcast <msg> — send to every active agent
_broadcast() {
  local msg="$1"
  local count=0
  while IFS= read -r name; do
    _send_to_agent "$name" "$msg"
    count=$((count+1))
  done < <(_active_agents)
  echo "📡 broadcast → $count agent(s)"
}

# _parse_ask_target <args> — determine target from first token
#   Sets PARSED_TARGET and PARSED_MESSAGE shell vars.
#   If first token (split on whitespace) matches a known agent/alias, treat as target.
#   Otherwise PARSED_TARGET="" (broadcast) and PARSED_MESSAGE=full input.
_parse_ask_target() {
  local input="$*"
  local first="${input%% *}"
  local rest="${input#* }"
  [ "$first" = "$input" ] && rest=""
  local canonical=$(_resolve_agent_alias "$first")
  if [ -n "$canonical" ]; then
    PARSED_TARGET="$canonical"
    PARSED_MESSAGE="$rest"
  else
    PARSED_TARGET=""
    PARSED_MESSAGE="$input"
  fi
}

# -----------------------------------------------------------------------------
# Login & startup helpers
# -----------------------------------------------------------------------------

_agent_login_guide() {
  local name="$1" surface="$2"
  echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  🛑 [$name] 로그인이 필요합니다 ($surface)"
  echo ""
  case "$name" in
    codex)
      echo "    1. cmux Codex pane으로 이동"
      echo "    2. 브라우저로 OpenAI 구독(ChatGPT Plus/Pro/Team) 로그인"
      echo "    3. 완료 후 /agentea 재실행"
      ;;
    grok)
      echo "    1. cmux Grok pane으로 이동"
      echo "    2. 브라우저로 xAI/Grok 구독 로그인"
      echo "    3. 완료 후 /agentea 재실행"
      ;;
    antigravity)
      echo "    1. cmux Antigravity pane으로 이동"
      echo "    2. 브라우저로 Google/Antigravity 계정 로그인"
      echo "    3. 'Gemini CLI 설정 import' 프롬프트 나오면 Yes/No 직접 선택"
      echo "    4. 완료 후 /agentea 재실행"
      ;;
  esac
  echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# _check_agent_startup <surface> <agent_name> — wait until agent is ready
# Returns: 0=ready, 1=unknown(uncertain), 2=needs user intervention
_check_agent_startup() {
  local surface="$1" agent_name="$2"
  local max_attempts=5 attempt=0 STATUS="unknown"

  echo ""
  echo "🔍 [$agent_name] 기동 상태 점검 중..."

  while [ $attempt -lt $max_attempts ]; do
    attempt=$((attempt+1))
    local screen_content
    screen_content=$(cmux read-screen --surface "$surface" --lines 20 2>/dev/null)
    STATUS=$(_classify_screen "$screen_content")

    echo "  시도 $attempt/$max_attempts: 상태=$STATUS"

    case "$STATUS" in
      busy)
        sleep 5
        ;;
      trust_prompt)
        echo "  ⚠️  trust 프롬프트 → 자동 수락 (1 + Enter)"
        cmux send --surface "$surface" "1" >/dev/null
        cmux send-key --surface "$surface" Return >/dev/null
        sleep 1
        cmux send-key --surface "$surface" Return >/dev/null
        sleep 3
        ;;
      confirm_yn)
        echo "  ⚠️  Y/N 프롬프트 → 자동 y"
        cmux send --surface "$surface" "y" >/dev/null
        cmux send-key --surface "$surface" Return >/dev/null
        sleep 3
        ;;
      import_offer)
        echo "  🔄 [$agent_name] Gemini CLI 설정 import 제안 감지 → 거절 (n)"
        cmux send --surface "$surface" "n" >/dev/null
        cmux send-key --surface "$surface" Return >/dev/null
        sleep 3
        ;;
      login_prompt)
        _agent_login_guide "$agent_name" "$surface"
        return 2
        ;;
      error_state)
        echo "  🔴 [$agent_name] 에러:"
        echo "$screen_content" | head -10 | sed 's/^/    /'
        case "$agent_name" in
          codex)        echo "    설치: npm install -g @openai/codex" ;;
          grok)         echo "    설치: xAI Grok CLI 공식 문서 참조" ;;
          antigravity)  echo "    설치: brew install --cask antigravity-cli" ;;
        esac
        return 2
        ;;
      ready*)
        echo "  ✅ [$agent_name] 준비 완료 ($STATUS)"
        return 0
        ;;
      unknown)
        echo "  ❓ [$agent_name] 분류되지 않은 화면 — 사용자 확인 필요:"
        echo "$screen_content" | tail -8 | sed 's/^/    /'
        sleep 3
        ;;
    esac
  done

  echo "  ⚠️  [$agent_name] 5회 시도 후에도 ready 아님 — 진행하되 pane 직접 확인"
  return 1
}

# -----------------------------------------------------------------------------
# File / I/O helpers
# -----------------------------------------------------------------------------

# _wait_file <path> [timeout_seconds=120]
_wait_file() {
  local f="$1" max_sec="${2:-120}" elapsed=0
  until [ -f "$f" ] && [ -s "$f" ]; do
    sleep 5
    elapsed=$((elapsed+5))
    if [ "$elapsed" -ge "$max_sec" ]; then
      echo "⏰ 타임아웃 ($max_sec s): $f" >&2
      return 1
    fi
  done
}

# _require_on — exit if mode != on. Usage at top of every subskill.
_require_on() {
  _load_state || { echo "⚠️  agentea 세션 없음 — /agentea 로 시작하세요"; exit 0; }
  if [ "$MODE" != "on" ]; then
    echo "⚠️  agentea mode = $MODE (not on) — /agentea 로 시작하세요"
    exit 0
  fi
}

# _require_manual_or_explicit — exit if auto-trigger blocked
# Called by subskills that auto-trigger; allows manual call to bypass.
# Set AGENTEA_EXPLICIT_CALL=1 in the invocation when user explicitly typed the slash command.
_require_manual_or_explicit() {
  if [ "$INTERACTION_MODE" = "manual" ] && [ -z "${AGENTEA_EXPLICIT_CALL:-}" ]; then
    echo "ℹ️  manual 모드 — 명시 호출 필요. /$(basename $0 .md) 를 직접 실행하세요."
    exit 0
  fi
}
