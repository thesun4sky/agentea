---
name: agentea
description: Use when you want Claude Code, Codex, and Grok to collaborate in the same cmux workspace — ON/OFF Council decisions and multi-agent Review Loops until all three say LGTM. Agents share files via .agentea/ folder; only Claude Code modifies source files.
argument-hint: "[on|off|status|review|task 설명|send codex|send grok|broadcast]"
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
for s in $(cmux tree --workspace "$MY_WORKSPACE" 2>/dev/null | grep -oE 'surface:[0-9]+'); do
  [ "$s" = "$MY_SURFACE" ] && continue
  content=$(cmux read-screen --surface "$s" --lines 6 2>/dev/null)
  echo "$content" | grep -qiE 'gpt-|codex|openai' && CODEX_SURFACE="$s"
  echo "$content" | grep -qiE 'Grok Build|grok|xai'  && GROK_SURFACE="$s"
done
```

### Step 3: 없으면 자동으로 Pane 생성 + 에이전트 시작

```bash
if [ -z "$CODEX_SURFACE" ] || [ -z "$GROK_SURFACE" ]; then
  echo "Codex/Grok pane이 없습니다 — 자동 생성 중..."

  # 현재 surface 우측에 새 pane 생성
  NEW_RIGHT=$(cmux split-off --surface "$MY_SURFACE" right --no-focus 2>/dev/null | grep -oE 'surface:[0-9]+' | head -1)

  if [ -n "$NEW_RIGHT" ]; then
    CODEX_SURF="$NEW_RIGHT"
    # 우측 pane을 다시 위아래로 분할 → Codex(위), Grok(아래)
    GROK_SURF=$(cmux split-off --surface "$NEW_RIGHT" down --no-focus 2>/dev/null | grep -oE 'surface:[0-9]+' | head -1)

    cmux send --surface "$CODEX_SURF" "cd $WORK_DIR && codex"
    cmux send-key --surface "$CODEX_SURF" Return
    cmux send --surface "$GROK_SURF" "cd $WORK_DIR && grok"
    cmux send-key --surface "$GROK_SURF" Return

    CODEX_SURFACE="$CODEX_SURF"
    GROK_SURFACE="$GROK_SURF"
    echo "✅ Pane 생성 완료: Codex=$CODEX_SURFACE, Grok=$GROK_SURFACE"
  else
    echo "⚠️ split-off 실패 — pane 수동 확인 필요"
  fi
fi
```

### Step 4: 역할 안내 메시지 (에이전트 초기화 후 전송)

```bash
# 에이전트가 시작될 시간 대기 후 역할 안내
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
echo "✅ agentea ON"
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
# 파일 생성 대기 (폴링 불필요 — fswatch 또는 단순 루프)
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

```
Round N 시작
  ├─ 리뷰 파일 → .agentea/review_rN.* 저장
  ├─ Codex: .agentea/review_rN.* 읽고 결과 → .agentea/codex_rN.md
  ├─ Grok:  .agentea/review_rN.* 읽고 결과 → .agentea/grok_rN.md
  └─ Claude 직접 리뷰
       ↓
  _wait_file 으로 응답 파일 대기
       ↓
  파일 읽어서 이슈 통합
       ↓
  모두 LGTM? ──Yes──→ 🎉 완료
       │
      No
       ↓
  Claude가 이슈 수정 (Edit/Write)
  수정 내역 → .agentea/fixes_rN.md
       ↓
  Round N+1 (최대 5라운드)
```

### 리뷰 요청 실행 (단일 라인)

```bash
ROUND=1
REVIEW_FILE="$AGENTEA_DIR/review_r${ROUND}.diff"
git diff HEAD > "$REVIEW_FILE"

# 응답 파일 미리 삭제 (이전 라운드 잔여물 방지)
rm -f "$AGENTEA_DIR/codex_r${ROUND}.md" "$AGENTEA_DIR/grok_r${ROUND}.md"

_send_codex "🔍 REVIEW #${ROUND}: $REVIEW_FILE 읽고 결과를 $AGENTEA_DIR/codex_r${ROUND}.md 에 저장 (ISSUE:/FIX: 또는 LGTM)"
_send_grok  "🔍 REVIEW #${ROUND}: $REVIEW_FILE 읽고 결과를 $AGENTEA_DIR/grok_r${ROUND}.md 에 저장 (ISSUE:/FIX: 또는 LGTM)"

# 응답 파일 대기
_wait_file "$AGENTEA_DIR/codex_r${ROUND}.md" 180
_wait_file "$AGENTEA_DIR/grok_r${ROUND}.md"  180

CODEX_RESP=$(cat "$AGENTEA_DIR/codex_r${ROUND}.md")
GROK_RESP=$(cat "$AGENTEA_DIR/grok_r${ROUND}.md")
```

### LGTM 감지 및 이슈 통합

```bash
_has_lgtm() { echo "$1" | grep -qiE 'LGTM' && echo "true" || echo "false"; }
_parse_issues() { echo "$1" | grep -E 'ISSUE:|FIX:' | head -20; }

codex_lgtm=$(_has_lgtm "$CODEX_RESP")
grok_lgtm=$(_has_lgtm "$GROK_RESP")

# 이슈 통합 파일 저장
{
  echo "# Round $ROUND Issues"
  echo "## Codex"
  _parse_issues "$CODEX_RESP"
  echo "## Grok"
  _parse_issues "$GROK_RESP"
} > "$AGENTEA_DIR/issues_r${ROUND}.md"
```

### 수정 후 다음 라운드

```bash
FIXES_FILE="$AGENTEA_DIR/fixes_r${ROUND}.md"
echo "수정 완료: $(date)" > "$FIXES_FILE"
# ... 수정 내역 append ...

NEXT=$((ROUND+1))
git diff HEAD > "$AGENTEA_DIR/review_r${NEXT}.diff"
rm -f "$AGENTEA_DIR/codex_r${NEXT}.md" "$AGENTEA_DIR/grok_r${NEXT}.md"

_send_codex "🔍 REVIEW #${NEXT}: $FIXES_FILE 확인 후 $AGENTEA_DIR/review_r${NEXT}.diff 리뷰 — 결과를 $AGENTEA_DIR/codex_r${NEXT}.md 에 저장"
_send_grok  "🔍 REVIEW #${NEXT}: $FIXES_FILE 확인 후 $AGENTEA_DIR/review_r${NEXT}.diff 리뷰 — 결과를 $AGENTEA_DIR/grok_r${NEXT}.md 에 저장"
```

---

## 6. agentea OFF

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

## 7. 상태 파일 스키마

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

---

## 8. CRITICAL 규칙

| 규칙 | 이유 |
|---|---|
| 코드를 명령어에 직접 담지 말 것 | "Pasted Content" 모드 + Codex 큐 오염 |
| Codex에 멀티라인 메시지 금지 | 각 줄이 별도 명령으로 큐에 들어가 코드 수정 시작 |
| 항상 `send` + `send-key Return` 분리 | `\n`은 줄바꿈이지 Enter가 아님 |
| 응답은 .agentea/ 파일에 저장 지시 | read-screen 잘림 없이 전체 응답 수집 |
| Codex·Grok은 소스 파일 수정 금지 | 초기화 시 role_guide.md로 역할 안내 |

---

## 9. .agentea/ 파일 구조

```
.agentea/
  role_guide.md          # 에이전트 역할 안내 (ON 시 1회 생성)
  review_r1.diff         # Round 1 리뷰 대상
  codex_r1.md            # Codex Round 1 응답
  grok_r1.md             # Grok Round 1 응답
  issues_r1.md           # 통합 이슈 목록
  fixes_r1.md            # Claude 수정 내역
  review_r2.diff         # Round 2 리뷰 대상
  ...
  council_1.md           # Council 안건
  codex_vote_1.md        # Codex 투표 결과
  grok_vote_1.md         # Grok 투표 결과
```

---

## 10. 최종 완료 리포트

```
🏁 REVIEW 완료
━━━━━━━━━━━━━━
총 N 라운드
수정된 이슈: M건
  - Round 1: [이슈 요약]
  - Round 2: [이슈 요약]
최종 상태: 3자 LGTM ✅
.agentea/ 보관: review_r*.diff, codex_r*.md, grok_r*.md, issues_r*.md
```
