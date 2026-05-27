---
name: agentea
description: Use when you want Claude Code, Codex, and Grok to collaborate in the same cmux workspace — ON/OFF Council decisions and multi-agent Review Loops until all three say LGTM. Agents share files via .agentea/ folder; only Claude Code modifies source files.
argument-hint: "[on|off|status|review|council|send codex|send grok|broadcast]"
---

# /agentea — 3-Agent Tea Party 협업 오케스트레이터

Claude Code + Codex + Grok 이 `.agentea/` 폴더를 통해 소통하며 협력.

**핵심 원칙**:
- Codex·Grok은 **읽기·제안 전용** — 소스 파일 수정은 Claude Code만
- 응답은 `.agentea/` 파일에 저장 → `read-screen` 폴링 불필요
- 절대 코드/diff 내용을 명령어에 직접 붙이지 않음 (파일 경로 전달)

---

## 0. 공통: 환경 초기화

```bash
WORK_DIR=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
AGENTEA_DIR="$WORK_DIR/.agentea"
mkdir -p "$AGENTEA_DIR"

# .agentea/ 를 .gitignore에 추가 (없으면)
if ! grep -q "^\.agentea" "$WORK_DIR/.gitignore" 2>/dev/null; then
  echo ".agentea/" >> "$WORK_DIR/.gitignore"
fi
```

---

## 1. agentea ON — 세션 초기화 + Pane 자동 세팅

### Step 1: 현재 Surface 확인

```bash
MY_SURFACE="$CMUX_SURFACE_ID"
MY_WORKSPACE="$CMUX_WORKSPACE_ID"
echo "현재 위치: $MY_SURFACE (workspace: $MY_WORKSPACE)"
```

### Step 2: 기존 Codex/Grok Pane 탐지

```bash
CODEX_SURFACE="" ; GROK_SURFACE=""
for s in $(cmux tree --workspace "$MY_WORKSPACE" 2>/dev/null | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}|surface:[0-9]+'); do
  [ "$s" = "$MY_SURFACE" ] && continue
  content=$(cmux read-screen --surface "$s" --lines 8 2>/dev/null)
  echo "$content" | grep -qiE 'codex|openai|gpt-' && CODEX_SURFACE="$s"
  echo "$content" | grep -qiE 'grok|xai'           && GROK_SURFACE="$s"
done
```

### Step 3: 없으면 자동으로 Pane 생성 + 에이전트 시작

```bash
if [ -z "$CODEX_SURFACE" ] || [ -z "$GROK_SURFACE" ]; then
  echo "Codex/Grok pane이 없습니다 — 자동 생성 중..."

  # 우측에 Codex pane 생성
  CODEX_RESULT=$(cmux new-split right --surface "$MY_SURFACE" --workspace "$MY_WORKSPACE" --focus false 2>&1)
  CODEX_SURFACE=$(echo "$CODEX_RESULT" | grep -oE 'surface:[0-9]+' | head -1)

  if [ -n "$CODEX_SURFACE" ]; then
    # Codex 아래에 Grok pane 생성
    GROK_RESULT=$(cmux new-split down --surface "$CODEX_SURFACE" --workspace "$MY_WORKSPACE" --focus false 2>&1)
    GROK_SURFACE=$(echo "$GROK_RESULT" | grep -oE 'surface:[0-9]+' | head -1)

    # 에이전트 시작
    cmux send --surface "$CODEX_SURFACE" "cd $WORK_DIR && codex"
    cmux send-key --surface "$CODEX_SURFACE" Return
    cmux send --surface "$GROK_SURFACE" "cd $WORK_DIR && grok"
    cmux send-key --surface "$GROK_SURFACE" Return

    echo "✅ Pane 생성: Codex=$CODEX_SURFACE, Grok=$GROK_SURFACE"
    echo "⏳ 에이전트 기동 대기 중 (8초)..."
    sleep 8
  else
    echo "⚠️ Pane 생성 실패 — pane 수동 확인 필요"
  fi
fi
```

### Step 3.5: ★ 에이전트 기동 상태 점검 (핵심 신규 단계)

에이전트 시작 후 화면을 읽어 **예상치 못한 프롬프트**를 감지하고 처리.

```bash
# 알려진 인터럽트 패턴 정의
# - trust_prompt  : "Do you trust the authors" / "폴더를 신뢰" (Codex workspace trust)
# - login_prompt  : "log in" / "sign in" / "authenticate" / "API key"
# - confirm_yn    : "(y/n)" / "(yes/no)" / "[Y/n]" 형태의 일반 확인 프롬프트
# - error_state   : "command not found" / "Error" / "failed"
# - ready_state   : 정상 프롬프트 (> 또는 에이전트 UI)

_classify_screen() {
  local content="$1"
  # 우선순위 순서로 패턴 매칭
  echo "$content" | grep -qiE 'trust|신뢰|Do you trust|authors of files' && echo "trust_prompt" && return
  echo "$content" | grep -qiE '\[y/n\]|\(y/n\)|\(yes/no\)|yes/no|Y/n' && echo "confirm_yn" && return
  echo "$content" | grep -qiE 'log.?in|sign.?in|authenticate|API.?key|api_key|token|credential|password|username|email' && echo "login_prompt" && return
  echo "$content" | grep -qiE 'command not found|Error:|failed|ENOENT|permission denied|not installed' && echo "error_state" && return
  echo "$content" | grep -qiE '^\s*[•·▸▹►⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]|Thinking\.\.\.|Exploring|Running|Generating|stop  \[' && echo "busy" && return
  echo "ready"
}

_check_agent_startup() {
  local surface="$1"
  local agent_name="$2"
  local max_attempts=5
  local attempt=0
  local STATUS="unknown"

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
        echo "  ⏳ [$agent_name] 작업 중 — 완료 대기 (5초)"
        sleep 5
        ;;
      trust_prompt)
        echo "  ⚠️  [$agent_name] 폴더 신뢰 확인 프롬프트 감지 → 자동 수락 시도"
        cmux send --surface "$surface" "1"
        cmux send-key --surface "$surface" Return
        sleep 1
        cmux send-key --surface "$surface" Return
        sleep 3
        ;;
      confirm_yn)
        echo "  ⚠️  [$agent_name] Y/N 확인 프롬프트 감지 → 'y' 자동 전송"
        cmux send --surface "$surface" "y"
        cmux send-key --surface "$surface" Return
        sleep 3
        ;;
      login_prompt)
        echo "  🔴 [$agent_name] 로그인/인증 필요 — 자동 처리 불가"
        echo ""
        echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  🛑 ACTION REQUIRED: [$agent_name] 로그인이 필요합니다"
        echo ""
        echo "  화면 내용:"
        echo "$screen_content" | head -10 | sed 's/^/    /'
        echo ""
        echo "  해결 방법:"
        if [ "$agent_name" = "Codex" ]; then
          echo "    1. cmux 에서 Codex pane($surface)으로 직접 이동"
          echo "    2. 터미널에 표시된 로그인 URL을 브라우저에서 열기"
          echo "       (또는 Enter/y 를 눌러 브라우저 자동 오픈 허용)"
          echo "    3. OpenAI 구독 계정(ChatGPT Plus/Pro/Team)으로 로그인"
          echo "    4. 로그인 완료 후 터미널로 돌아와 확인"
          echo "    5. 로그인 완료되면 다시 /agentea 실행"
          echo ""
          echo "    ⚠️  OpenAI 구독(ChatGPT Plus 이상)이 없으면 Codex CLI 사용 불가"
        elif [ "$agent_name" = "Grok" ]; then
          echo "    1. cmux 에서 Grok pane($surface)으로 직접 이동"
          echo "    2. 터미널에 표시된 로그인 URL을 브라우저에서 열기"
          echo "       (또는 Enter/y 를 눌러 브라우저 자동 오픈 허용)"
          echo "    3. xAI/Grok 구독 계정으로 로그인"
          echo "    4. 로그인 완료 후 터미널로 돌아와 확인"
          echo "    5. 로그인 완료되면 다시 /agentea 실행"
          echo ""
          echo "    ⚠️  xAI/Grok 구독이 없으면 Grok CLI 사용 불가"
        fi
        echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        return 2  # 사용자 개입 필요
        ;;
      error_state)
        echo "  🔴 [$agent_name] 에러 상태 감지"
        echo ""
        echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  🛑 ERROR: [$agent_name] 시작 실패"
        echo ""
        echo "  화면 내용:"
        echo "$screen_content" | head -10 | sed 's/^/    /'
        echo ""
        echo "  해결 방법:"
        if [ "$agent_name" = "Codex" ]; then
          echo "    - codex 설치 확인: npm install -g @openai/codex"
          echo "    - 또는: npx @openai/codex"
        elif [ "$agent_name" = "Grok" ]; then
          echo "    - grok 설치 확인: npm install -g @xai/grok-cli"
          echo "    - 또는 설치 방법은 xAI 공식 문서 참조"
        fi
        echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        return 2
        ;;
      ready)
        echo "  ✅ [$agent_name] 준비 완료"
        return 0
        ;;
    esac

    sleep 3
  done

  # 5회 시도 후에도 확인 안 되면 경고만 하고 계속
  echo "  ⚠️  [$agent_name] 상태 확인 불확실 — 현재 화면:"
  cmux read-screen --surface "$surface" --lines 10 2>/dev/null | sed 's/^/    /'
  echo "  → 계속 진행하되, 에이전트 pane을 직접 확인하세요"
  return 1
}

# 각 에이전트 점검 실행
CODEX_READY=false; GROK_READY=false

_check_agent_startup "$CODEX_SURFACE" "Codex"
CODEX_EXIT=$?
[ "$CODEX_EXIT" -eq 0 ] && CODEX_READY=true

_check_agent_startup "$GROK_SURFACE" "Grok"
GROK_EXIT=$?
[ "$GROK_EXIT" -eq 0 ] && GROK_READY=true

# 하나라도 개입 필요 시 중단
if [ "$CODEX_READY" = false ] || [ "$GROK_READY" = false ]; then
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "⛔ agentea ON 중단 — 에이전트 환경 설정 필요"
  echo ""
  echo "위의 안내에 따라 설정 완료 후 다시 /agentea 를 실행하세요."
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  # 상태는 pending으로 저장 (완전 ON 아님)
  cat > ~/.claude/agentea-state.json << EOSTATE
{
  "mode": "pending",
  "work_dir": "$WORK_DIR",
  "my_surface": "$MY_SURFACE",
  "codex_surface": "$CODEX_SURFACE",
  "grok_surface": "$GROK_SURFACE",
  "agentea_dir": "$AGENTEA_DIR",
  "codex_ready": $CODEX_READY,
  "grok_ready": $GROK_READY,
  "session_start": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOSTATE
  exit 1
fi
```

### Step 4: 역할 안내 메시지 (에이전트 정상 확인 후 전송)

```bash
# 안내 내용을 파일에 저장 후 경로로 전달 (멀티라인 직접 전송 금지)
cat > "$AGENTEA_DIR/role_guide.md" << 'EOF'
## agentea 협업 규칙

당신의 역할: 코드리뷰 전문 협업자
1. 요청 파일 경로를 읽고 리뷰
2. 소스 파일 직접 수정 금지 — ISSUE:/FIX: 형식으로만 제안
3. 이슈 없으면 마지막 줄에 LGTM
4. 리뷰 결과는 지정된 .agentea/ 파일에 저장
EOF

cmux send --surface "$CODEX_SURFACE" "$AGENTEA_DIR/role_guide.md 읽고 역할 확인해주세요"
cmux send-key --surface "$CODEX_SURFACE" Return
cmux send --surface "$GROK_SURFACE" "$AGENTEA_DIR/role_guide.md 읽고 역할 확인해주세요"
cmux send-key --surface "$GROK_SURFACE" Return
```

### Step 5: 상태 저장

```bash
cat > ~/.claude/agentea-state.json << EOSTATE
{
  "mode": "on",
  "work_dir": "$WORK_DIR",
  "my_surface": "$MY_SURFACE",
  "codex_surface": "$CODEX_SURFACE",
  "grok_surface": "$GROK_SURFACE",
  "agentea_dir": "$AGENTEA_DIR",
  "session_start": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "decisions": [],
  "review_sessions": []
}
EOSTATE
echo "✅ agentea ON — 3-에이전트 티파티 준비 완료"
```

---

## 공통 전송 함수

```bash
_load_state() {
  CODEX_SURFACE=$(python3 -c "import json; d=json.load(open('$HOME/.claude/agentea-state.json')); print(d.get('codex_surface',''))" 2>/dev/null)
  GROK_SURFACE=$(python3 -c "import json; d=json.load(open('$HOME/.claude/agentea-state.json')); print(d.get('grok_surface',''))" 2>/dev/null)
  WORK_DIR=$(python3 -c "import json; d=json.load(open('$HOME/.claude/agentea-state.json')); print(d.get('work_dir','.'))" 2>/dev/null)
  MY_SURFACE=$(python3 -c "import json; d=json.load(open('$HOME/.claude/agentea-state.json')); print(d.get('my_surface',''))" 2>/dev/null)
  AGENTEA_DIR="$WORK_DIR/.agentea"
}

_send_codex() {
  cmux send --surface "$CODEX_SURFACE" "$1"
  cmux send-key --surface "$CODEX_SURFACE" Return
}

_send_grok() {
  cmux send --surface "$GROK_SURFACE" "$1"
  cmux send-key --surface "$GROK_SURFACE" Return
}

_broadcast() {
  _send_codex "$1"
  _send_grok "$1"
}
```

---

## 2. 파일 기반 응답 수집 패턴

**핵심**: Codex·Grok에게 결과를 `.agentea/` 파일에 저장하도록 지시 → Claude가 파일을 읽기만 하면 됨.
`read-screen` 폴링 불필요, 응답 잘림 없음.

### 리뷰 요청 형식

```bash
# 요청 메시지 예시 (단일 라인, 결과 저장 파일 명시)
ROUND=1
REVIEW_FILE="$AGENTEA_DIR/review_r${ROUND}.diff"

_send_codex "🔍 REVIEW #${ROUND}: $REVIEW_FILE 읽고 결과를 $AGENTEA_DIR/codex_r${ROUND}.md 에 저장 (ISSUE:/FIX: 또는 LGTM)"
_send_grok  "🔍 REVIEW #${ROUND}: $REVIEW_FILE 읽고 결과를 $AGENTEA_DIR/grok_r${ROUND}.md 에 저장 (ISSUE:/FIX: 또는 LGTM)"
```

### 응답 파일 대기 및 읽기

```bash
_wait_file() {
  local f="$1" max_sec="${2:-120}" elapsed=0
  until [ -f "$f" ] && [ -s "$f" ]; do
    sleep 5; elapsed=$((elapsed+5))
    [ "$elapsed" -ge "$max_sec" ] && echo "⏰ 타임아웃: $f" && return 1
  done
}

_wait_file "$AGENTEA_DIR/codex_r${ROUND}.md"
_wait_file "$AGENTEA_DIR/grok_r${ROUND}.md"

CODEX_RESP=$(cat "$AGENTEA_DIR/codex_r${ROUND}.md")
GROK_RESP=$(cat "$AGENTEA_DIR/grok_r${ROUND}.md")
```

---

## 3. .agentea/ 폴더 콘텐츠 준비

리뷰 대상은 항상 파일로 저장 후 **경로만** 에이전트에 전달.

```bash
# Case 1: git diff
git diff HEAD > "$AGENTEA_DIR/review_r${ROUND}.diff"

# Case 2: 특정 파일
cp "$TARGET_FILE" "$AGENTEA_DIR/review_r${ROUND}.ts"

# Case 3: PR diff
gh pr diff $PR_NUM > "$AGENTEA_DIR/review_r${ROUND}.diff"

# Case 4: 최근 커밋
git show HEAD > "$AGENTEA_DIR/review_r${ROUND}.diff"
```

**CRITICAL 규칙**:
- 코드 내용을 명령어에 직접 붙이지 말 것 → "Pasted Content" 모드 발생
- Codex에 멀티라인 메시지 금지 → 각 줄이 별도 명령으로 큐에 들어가 코드 수정 시작
- 항상 `cmux send "msg"` + `cmux send-key Return` 분리 → `\n`은 Enter가 아님

---

## 4. Council 모드 (결정)

### 소집 기준
소집 O: 아키텍처 선택, 버그픽스 전략 2가지 이상, 되돌리기 어려운 변경
소집 X: 단순 파일 읽기, 이미 합의된 사항 재실행, 단순 구현

### Council 흐름

```bash
COUNCIL_N=1

# 1) 안건 파일 작성
cat > "$AGENTEA_DIR/council_${COUNCIL_N}.md" << EOF
🏛️ COUNCIL #${COUNCIL_N}: [결정 제목]
배경: [상황 2-3줄]
질문: [결정 내용]
선택지:
  A) ...
  B) ...
결과를 $AGENTEA_DIR/codex_vote_${COUNCIL_N}.md 에 저장 (마지막 줄: VOTE: A 또는 B)
EOF

# 2) 에이전트에 전달
_send_codex "$AGENTEA_DIR/council_${COUNCIL_N}.md 읽고 투표해주세요"
_send_grok  "$AGENTEA_DIR/council_${COUNCIL_N}.md 읽고 투표해주세요"

# 3) 응답 파일 대기
_wait_file "$AGENTEA_DIR/codex_vote_${COUNCIL_N}.md"
_wait_file "$AGENTEA_DIR/grok_vote_${COUNCIL_N}.md"

# 4) 합의 감지
_parse_vote() { echo "$1" | grep -oiE 'VOTE:[[:space:]]*[A-Za-z]+' | tail -1 | sed 's/VOTE:[[:space:]]*//' | tr a-z A-Z; }

codex_vote=$(_parse_vote "$(cat $AGENTEA_DIR/codex_vote_${COUNCIL_N}.md)")
grok_vote=$(_parse_vote "$(cat $AGENTEA_DIR/grok_vote_${COUNCIL_N}.md)")

[[ "$codex_vote" == "$grok_vote" ]] && echo "✅ 합의: $codex_vote" || echo "⚡ 이견 → Round 2"
```

- Round 2: 양측 근거를 `council_${N}_r2.md`에 정리 → 재투표 요청
- Round 3: 합의 불가 → Claude 최종 결정 선언

---

## 5. Review Loop 모드

### 발동 조건
- 사용자 "리뷰해줘", "코드 봐줘", "PR 확인해줘"
- Claude 수정 완료 직후
- agentea ON 상태에서 작업 완료 시 자동 발동

### 리뷰 대상 파악

| 맥락 | 리뷰 파일 준비 |
|---|---|
| "PR #N 리뷰" | `gh pr diff N > .agentea/review_r1.diff` |
| 최근 커밋 | `git show HEAD > .agentea/review_r1.diff` |
| 파일명 언급 | `cp 파일 .agentea/review_r1.ext` |
| 방금 수정 | `git diff HEAD > .agentea/review_r1.diff` |
| 계획 문서 | `cp 문서 .agentea/review_r1.md` |
| 애매함 | → 유저에게 질문 |

### Review Loop 전체 흐름

**3자 병렬 리뷰**: Claude·Codex·Grok 동시에 같은 파일을 리뷰. 모두 LGTM이어야 완료.

```
Round N 시작
  ├─ 리뷰 파일 → .agentea/review_rN.* 저장
  ├─ Codex에 요청 전송 (→ .agentea/codex_rN.md 저장 지시)
  ├─ Grok에 요청 전송  (→ .agentea/grok_rN.md 저장 지시)
  └─ Claude 직접 리뷰 수행 (→ .agentea/claude_rN.md 저장)
       ↓ (Codex·Grok 응답 파일 대기)
  3자 결과 통합 → .agentea/issues_rN.md
       ↓
  Claude LGTM && Codex LGTM && Grok LGTM? ──Yes──→ 🎉 완료
       │
      No
       ↓
  Claude가 이슈 수정 (Edit/Write)
  수정 내역 → .agentea/fixes_rN.md
       ↓
  Round N+1 (최대 5라운드)
```

### 리뷰 요청 + Claude 즉시 리뷰 (병렬)

```bash
ROUND=1
REVIEW_FILE="$AGENTEA_DIR/review_r${ROUND}.diff"
git diff HEAD > "$REVIEW_FILE"

# 이전 라운드 잔여물 삭제
rm -f "$AGENTEA_DIR/codex_r${ROUND}.md" "$AGENTEA_DIR/grok_r${ROUND}.md" "$AGENTEA_DIR/claude_r${ROUND}.md"

# 1) Codex·Grok에 동시 요청 전송
_send_codex "🔍 REVIEW #${ROUND}: $REVIEW_FILE 읽고 결과를 $AGENTEA_DIR/codex_r${ROUND}.md 에 저장 (ISSUE:/FIX: 형식 또는 마지막 줄 LGTM)"
_send_grok  "🔍 REVIEW #${ROUND}: $REVIEW_FILE 읽고 결과를 $AGENTEA_DIR/grok_r${ROUND}.md 에 저장 (ISSUE:/FIX: 형식 또는 마지막 줄 LGTM)"

# 2) Claude도 즉시 리뷰 수행 (Codex·Grok 대기 중에 병렬로)
# → Claude는 REVIEW_FILE 을 직접 Read 하여 코드 리뷰 후 아래 형식으로 저장
cat > "$AGENTEA_DIR/claude_r${ROUND}.md" << 'CLAUDE_REVIEW_PLACEHOLDER'
# Claude Review — Round N
# [Claude가 직접 리뷰 결과를 여기 작성]
# ISSUE: ... / FIX: ... 또는 마지막 줄 LGTM
CLAUDE_REVIEW_PLACEHOLDER
# ↑ 실제 실행 시 Claude는 REVIEW_FILE을 Read한 뒤 분석 결과를 이 파일에 Write

# 3) Codex·Grok 응답 파일 대기
_wait_file "$AGENTEA_DIR/codex_r${ROUND}.md" 180
_wait_file "$AGENTEA_DIR/grok_r${ROUND}.md"  180

CLAUDE_RESP=$(cat "$AGENTEA_DIR/claude_r${ROUND}.md")
CODEX_RESP=$(cat "$AGENTEA_DIR/codex_r${ROUND}.md")
GROK_RESP=$(cat "$AGENTEA_DIR/grok_r${ROUND}.md")
```

### 3자 LGTM 감지 및 이슈 통합

```bash
_has_lgtm() { echo "$1" | grep -qiE 'LGTM' && echo "true" || echo "false"; }
_parse_issues() { echo "$1" | grep -E 'ISSUE:|FIX:' | head -20; }

claude_lgtm=$(_has_lgtm "$CLAUDE_RESP")
codex_lgtm=$(_has_lgtm "$CODEX_RESP")
grok_lgtm=$(_has_lgtm "$GROK_RESP")

# 3자 이슈 통합 파일 저장
{
  echo "# Round $ROUND — 3-Agent Review Issues"
  echo ""
  echo "## Claude"
  _parse_issues "$CLAUDE_RESP"
  echo ""
  echo "## Codex"
  _parse_issues "$CODEX_RESP"
  echo ""
  echo "## Grok"
  _parse_issues "$GROK_RESP"
} > "$AGENTEA_DIR/issues_r${ROUND}.md"

# 3자 모두 LGTM이어야 완료
if [ "$claude_lgtm" = "true" ] && [ "$codex_lgtm" = "true" ] && [ "$grok_lgtm" = "true" ]; then
  echo "🎉 3-Agent LGTM 달성 — Round $ROUND 완료"
else
  echo "이슈 존재:"
  [ "$claude_lgtm" != "true" ] && echo "  Claude: 이슈 있음"
  [ "$codex_lgtm"  != "true" ] && echo "  Codex:  이슈 있음"
  [ "$grok_lgtm"   != "true" ] && echo "  Grok:   이슈 있음"
  echo "→ Claude가 이슈 수정 후 Round $((ROUND+1)) 진행"
fi
```

### 수정 후 다음 라운드

```bash
FIXES_FILE="$AGENTEA_DIR/fixes_r${ROUND}.md"
echo "수정 완료: $(date)" > "$FIXES_FILE"
# ... 수정 내역 append ...

NEXT=$((ROUND+1))
git diff HEAD > "$AGENTEA_DIR/review_r${NEXT}.diff"
rm -f "$AGENTEA_DIR/codex_r${NEXT}.md" "$AGENTEA_DIR/grok_r${NEXT}.md" "$AGENTEA_DIR/claude_r${NEXT}.md"

_send_codex "🔍 REVIEW #${NEXT}: $FIXES_FILE 확인 후 $AGENTEA_DIR/review_r${NEXT}.diff 리뷰 — 결과를 $AGENTEA_DIR/codex_r${NEXT}.md 에 저장"
_send_grok  "🔍 REVIEW #${NEXT}: $FIXES_FILE 확인 후 $AGENTEA_DIR/review_r${NEXT}.diff 리뷰 — 결과를 $AGENTEA_DIR/grok_r${NEXT}.md 에 저장"
# Claude도 즉시 review_r${NEXT}.diff 를 Read하여 리뷰 수행 → claude_r${NEXT}.md 저장
```

---

## 6. agentea STATUS — 세션 주소 및 상태 조회

사용자가 "agentea 상태", "세션 확인", "status" 등을 요청하면 실행.

```bash
STATE_FILE="$HOME/.claude/agentea-state.json"

if [ ! -f "$STATE_FILE" ]; then
  echo "⚠️  agentea 세션 없음 — /agentea 로 시작하세요"
  exit 0
fi

MODE=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d.get('mode','unknown'))")
WORK_DIR=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d.get('work_dir','?'))")
MY_SURFACE=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d.get('my_surface','?'))")
CODEX_SURFACE=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d.get('codex_surface','?'))")
GROK_SURFACE=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d.get('grok_surface','?'))")
SESSION_START=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d.get('session_start','?'))")

_classify_screen() {
  local content="$1"
  [ -z "$content" ] && echo "unreachable" && return
  echo "$content" | grep -qiE 'trust|Do you trust|authors of files' && echo "trust_prompt" && return
  echo "$content" | grep -qiE '\[y/n\]|\(y/n\)|\(yes/no\)|Y/n' && echo "confirm_yn" && return
  echo "$content" | grep -qiE 'log.?in|sign.?in|authenticate|API.?key|token|credential|password|username|email' && echo "login_prompt" && return
  echo "$content" | grep -qiE 'command not found|Error:|failed|ENOENT|permission denied|not installed' && echo "error_state" && return
  # busy: 에이전트가 응답 생성 중 (스피너/진행 표시)
  echo "$content" | grep -qiE '^\s*[•·▸▹►⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]|Thinking\.\.\.|Exploring|Running|working|Generating|stop  \[' && echo "busy" && return
  echo "$content" | grep -qiE 'gpt-|codex|openai' && echo "ready(codex)" && return
  echo "$content" | grep -qiE 'Grok Build|grok' && echo "ready(grok)" && return
  echo "ready"
}

_status_icon() {
  case "$1" in
    ready*) echo "✅" ;;
    busy) echo "⏳" ;;
    trust_prompt|confirm_yn) echo "⚠️ " ;;
    login_prompt) echo "🔐" ;;
    error_state) echo "🔴" ;;
    unreachable) echo "💀" ;;
    *) echo "❓" ;;
  esac
}

CODEX_SCREEN=$(cmux read-screen --surface "$CODEX_SURFACE" --lines 5 2>/dev/null)
GROK_SCREEN=$(cmux read-screen --surface "$GROK_SURFACE" --lines 5 2>/dev/null)
CODEX_STATUS=$(_classify_screen "$CODEX_SCREEN")
GROK_STATUS=$(_classify_screen "$GROK_SCREEN")

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🍵 agentea STATUS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  모드       : $MODE"
echo "  프로젝트   : $WORK_DIR"
echo "  세션 시작  : $SESSION_START"
echo ""
echo "  Surface 주소"
echo "  ┌─────────────────────────────────"
echo "  │ Claude  : $MY_SURFACE"
echo "  │ Codex   : $CODEX_SURFACE  $(_status_icon "$CODEX_STATUS") $CODEX_STATUS"
echo "  │ Grok    : $GROK_SURFACE  $(_status_icon "$GROK_STATUS") $GROK_STATUS"
echo "  └─────────────────────────────────"
echo ""
echo "  화면 미리보기"
echo "  [Codex]"
echo "$CODEX_SCREEN" | tail -3 | sed 's/^/    /'
echo "  [Grok]"
echo "$GROK_SCREEN" | tail -3 | sed 's/^/    /'
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
```

상태 아이콘:
- `✅ ready` — 정상 대기 중
- `⏳ busy` — 응답 생성 중 (완료 후 다시 조회)
- `⚠️  trust_prompt / confirm_yn` — 확인 프롬프트 대기 (Step 3.5 재실행 권장)
- `🔐 login_prompt` — 로그인 필요 (해당 pane으로 이동해 구독 계정 로그인)
- `🔴 error_state` — 에러 상태 (pane 재시작 필요)
- `💀 unreachable` — surface 접근 불가 (pane이 닫혔을 가능성)

---

## 7. agentea OFF

```bash
python3 -c "
import json
with open('$HOME/.claude/agentea-state.json') as f: d = json.load(f)
d['mode'] = 'off'
with open('$HOME/.claude/agentea-state.json', 'w') as f: json.dump(d, f, indent=2)
"
echo "agentea OFF — pane은 유지됩니다."
```

---

## 8. 상태 파일 스키마

`~/.claude/agentea-state.json`:
```json
{
  "mode": "on",
  "work_dir": "/Users/teasunkim/work/jobclaw",
  "my_surface": "surface:1",
  "codex_surface": "surface:3",
  "grok_surface": "surface:8",
  "agentea_dir": "/Users/teasunkim/work/jobclaw/.agentea",
  "session_start": "2026-05-28T00:00:00Z",
  "decisions": [],
  "review_sessions": []
}
```

`mode` 값:
- `"on"` — 정상 가동 중
- `"pending"` — 에이전트 환경 설정 필요 (로그인 등)
- `"off"` — 세션 종료

---

## 9. CRITICAL 규칙

| 규칙 | 이유 |
|---|---|
| 코드를 명령어에 직접 담지 말 것 | "Pasted Content" 모드 + Codex 큐 오염 |
| Codex에 멀티라인 메시지 금지 | 각 줄이 별도 명령으로 큐에 들어가 코드 수정 시작 |
| 항상 `send` + `send-key Return` 분리 | `\n`은 줄바꿈이지 Enter가 아님 |
| 응답은 .agentea/ 파일에 저장 지시 | read-screen 잘림 없이 전체 응답 수집 |
| Codex·Grok은 소스 파일 수정 금지 | 초기화 시 role_guide.md로 역할 안내 |
| **Step 3.5 생략 금지** | trust/login 프롬프트 미처리 시 에이전트가 응답 불능 상태로 방치됨 |

---

## 10. 알려진 스타트업 인터럽트 패턴

| 에이전트 | 패턴 | 증상 | 자동 처리 | 수동 처리 |
|---|---|---|---|---|
| Codex | 폴더 신뢰 확인 | "Do you trust the authors..." | `y` 자동 전송 | — |
| Codex | OpenAI 구독 로그인 | "log in" / "sign in" | — | 브라우저에서 OpenAI 계정 로그인 |
| Codex | Y/N 확인 | `[Y/n]` | `y` 자동 전송 | — |
| Grok | xAI 구독 로그인 | "sign in" / "authenticate" | — | 브라우저에서 xAI/Grok 계정 로그인 |
| 공통 | 미설치 | "command not found" | — | npm install 안내 |

### 로그인 요구사항

```
Codex CLI
  - 필요: OpenAI 구독 계정 (ChatGPT Plus / Pro / Team)
  - 방법: codex 실행 → 브라우저 로그인 URL 자동 표시 → OpenAI 계정으로 로그인
  - 주의: API 키(sk-...) 방식이 아닌 구독 OAuth 방식

Grok CLI
  - 필요: xAI/Grok 구독 계정
  - 방법: grok 실행 → 브라우저 로그인 URL 자동 표시 → xAI 계정으로 로그인
  - 주의: API 키 방식이 아닌 구독 OAuth 방식
```

### 설치 확인

```bash
which codex || npm install -g @openai/codex
which grok  || echo "xAI grok CLI 설치 방법은 xAI 공식 문서 참조"
```

---

## 11. .agentea/ 파일 구조

```
.agentea/
  role_guide.md          # 에이전트 역할 안내 (ON 시 1회 생성)
  review_r1.diff         # Round 1 리뷰 대상
  claude_r1.md           # Claude Round 1 리뷰 결과
  codex_r1.md            # Codex Round 1 리뷰 결과
  grok_r1.md             # Grok Round 1 리뷰 결과
  issues_r1.md           # 3자 통합 이슈 목록
  fixes_r1.md            # Claude 수정 내역
  review_r2.diff         # Round 2 리뷰 대상
  claude_r2.md           # Claude Round 2 리뷰 결과
  ...
  council_1.md           # Council 안건
  codex_vote_1.md        # Codex 투표 결과
  grok_vote_1.md         # Grok 투표 결과
```

---

## 12. 최종 완료 리포트

```
🏁 REVIEW 완료
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
총 N 라운드
수정된 이슈: M건
  - Round 1: [이슈 요약]
  - Round 2: [이슈 요약]

최종 LGTM
  Claude ✅  Codex ✅  Grok ✅

.agentea/ 보관:
  review_r*.diff, claude_r*.md, codex_r*.md, grok_r*.md, issues_r*.md
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
