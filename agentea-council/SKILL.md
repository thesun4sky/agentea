---
name: agentea-council
description: Use to convene a multi-agent council vote on an architectural or design decision. Broadcasts an agenda with options to all active agents, collects votes (last line "VOTE - A" or "VOTE - B"), detects consensus or dissent. Up to 3 rounds; if no consensus, Claude declares final decision. Use when there are 2+ viable design choices and you want independent perspectives.
argument-hint: "<agenda-text>"
---

# /agentea-council — 결정 안건 투표

## 소집 기준

- ✅ 아키텍처 선택 (2+ 옵션)
- ✅ 버그픽스 전략 2가지 이상
- ✅ 되돌리기 어려운 변경
- ❌ 단순 파일 읽기
- ❌ 이미 합의된 사항 재실행

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

_load_state || { echo "⚠️  agentea 세션 없음 — /agentea 로 시작하세요"; exit 0; }
[ "$MODE" != "on" ] && { echo "⚠️  agentea mode = $MODE — /agentea 로 시작하세요"; exit 0; }

AGENDA_TEXT="$*"
[ -z "$AGENDA_TEXT" ] && { echo "사용법: /agentea-council \"안건 + 선택지\""; exit 0; }

# 다음 council 번호 결정
COUNCIL_N=$(($(ls "$AGENTEA_DIR"/council_*.md 2>/dev/null | wc -l) + 1))
AGENDA_FILE="$AGENTEA_DIR/council_${COUNCIL_N}.md"

# Claude가 안건 정리 (Claude는 AGENDA_TEXT를 받아 구조화)
cat > "$AGENDA_FILE" << EOF
🏛️ COUNCIL #${COUNCIL_N}

배경: [Claude가 컨텍스트 정리]
질문: $AGENDA_TEXT
선택지:
  A) ...
  B) ...
EOF
# (Claude가 위 placeholder를 실제 내용으로 채워서 Write)
```

### 활성 에이전트 broadcast

```bash
# 각 에이전트별 vote 파일 경로
declare -A VOTE_FILE
while IFS= read -r agent; do
  VOTE_FILE[$agent]="$AGENTEA_DIR/${agent}_vote_${COUNCIL_N}.md"
done < <(_active_agents)

# 잔여물 정리
for f in "${VOTE_FILE[@]}"; do rm -f "$f"; done

# 각 에이전트에 안건 전달
for agent in "${!VOTE_FILE[@]}"; do
  _send_to_agent "$agent" \
    "$AGENDA_FILE 읽고 투표해주세요. 결과를 ${VOTE_FILE[$agent]} 에 저장 (마지막 줄: VOTE: A 또는 B)"
done
```

### 응답 대기 + 합의 감지

```bash
for f in "${VOTE_FILE[@]}"; do _wait_file "$f" 180; done

_parse_vote() {
  grep -oiE 'VOTE:[[:space:]]*[A-Za-z]+' "$1" | tail -1 | sed 's/VOTE:[[:space:]]*//' | tr a-z A-Z
}

declare -A VOTES
for agent in "${!VOTE_FILE[@]}"; do
  v=$(_parse_vote "${VOTE_FILE[$agent]}")
  VOTES[$agent]="$v"
done

# 모두 같은 표인지 확인
FIRST_VOTE=""
CONSENSUS="true"
for agent in "${!VOTES[@]}"; do
  v="${VOTES[$agent]}"
  echo "  $agent: $v"
  [ -z "$FIRST_VOTE" ] && FIRST_VOTE="$v" && continue
  [ "$v" != "$FIRST_VOTE" ] && CONSENSUS="false"
done

if [ "$CONSENSUS" = "true" ]; then
  echo "✅ 합의: $FIRST_VOTE"
else
  echo "⚡ 이견 → Round 2 (양측 근거를 council_${COUNCIL_N}_r2.md 에 정리 후 재투표)"
fi
```

### Round 2-3

이견 시 Claude가 양측 입장을 정리한 후 재투표. Round 3까지 합의 불가 시 Claude가 최종 결정 선언.

---

## CRITICAL 규칙

- 안건 파일은 명확한 선택지(A/B 또는 다항) 포함
- vote 파일 형식: 자유서술 + 마지막 줄에 `VOTE: <옵션>`
- 활성 에이전트 1명이면 council 의미 없음 — broadcast가 자동으로 처리하므로 그냥 의견만 받음
