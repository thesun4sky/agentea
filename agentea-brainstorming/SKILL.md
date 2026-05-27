---
name: agentea-brainstorming
description: Use to start a multi-agent ideation session — broadcasts a topic to all active agents and collects independent ideas in parallel. Each agent saves ideas to .agentea/brainstorm_<agent>_<n>.md. Claude synthesizes responses into a unified summary. Use for design exploration, feature ideation, naming, or any creative divergent thinking.
argument-hint: "<topic-or-question>"
---

# /agentea-brainstorming — 다같이 아이디에이션

## 동작

활성 에이전트 전체에게 주제를 broadcast하여 독립적 아이디어를 동시 수집. Claude는 자신의 아이디어도 같이 생성한 후, 통합 요약을 만듭니다.

```
브레인스토밍 #N 시작
  ├─ 주제 → .agentea/brainstorm_topic_N.md 저장
  ├─ Codex, Grok, Antigravity (활성) 에게 broadcast
  └─ Claude도 직접 아이디어 생성
       ↓
  각 에이전트 응답 파일 대기 (.agentea/brainstorm_<agent>_N.md)
       ↓
  Claude가 모든 아이디어 통합 → .agentea/brainstorm_summary_N.md
```

---

## 실행

```bash
source ~/.claude/skills/agentea/lib/common.sh || {
  echo "ERROR: agentea lib/common.sh not found"
  exit 1
}

_load_state || { echo "⚠️  agentea 세션 없음 — /agentea 로 시작하세요"; exit 0; }
[ "$MODE" != "on" ] && { echo "⚠️  agentea mode = $MODE — /agentea 로 시작하세요"; exit 0; }

TOPIC="$*"
[ -z "$TOPIC" ] && { echo "사용법: /agentea-brainstorming \"주제 또는 질문\""; exit 0; }

# 다음 브레인스토밍 번호
BRAIN_N=$(($(ls "$AGENTEA_DIR"/brainstorm_topic_*.md 2>/dev/null | wc -l) + 1))
TOPIC_FILE="$AGENTEA_DIR/brainstorm_topic_${BRAIN_N}.md"

cat > "$TOPIC_FILE" << EOF
# Brainstorming #${BRAIN_N}

## 주제
$TOPIC

## 요청
자유롭게 아이디어 5-10개 제안해주세요. 형식은 자유. 가능하면 각 아이디어에 한 줄 설명 첨부.
EOF
```

### 활성 에이전트에 broadcast

```bash
declare -A IDEA_FILE
while IFS= read -r agent; do
  IDEA_FILE[$agent]="$AGENTEA_DIR/brainstorm_${agent}_${BRAIN_N}.md"
done < <(_active_agents)

for f in "${IDEA_FILE[@]}"; do rm -f "$f"; done

for agent in "${!IDEA_FILE[@]}"; do
  _send_to_agent "$agent" \
    "$TOPIC_FILE 읽고 아이디어 5-10개를 ${IDEA_FILE[$agent]} 에 저장"
done

# Claude도 직접 TOPIC_FILE을 Read한 뒤 아이디어를 .agentea/brainstorm_claude_${BRAIN_N}.md 에 Write
```

### 응답 대기 + 통합

```bash
for f in "${IDEA_FILE[@]}"; do _wait_file "$f" 180; done

# Claude는 자신 + 모든 에이전트 아이디어를 읽어 통합 요약 작성
SUMMARY_FILE="$AGENTEA_DIR/brainstorm_summary_${BRAIN_N}.md"
{
  echo "# Brainstorming #${BRAIN_N} — Summary"
  echo ""
  echo "## Topic"
  echo "$TOPIC"
  echo ""
  echo "## Claude"
  cat "$AGENTEA_DIR/brainstorm_claude_${BRAIN_N}.md" 2>/dev/null
  echo ""
  for agent in "${!IDEA_FILE[@]}"; do
    echo "## $agent"
    cat "${IDEA_FILE[$agent]}"
    echo ""
  done
  echo "## Synthesis (Claude)"
  echo "[중복 제거 + 클러스터링 + 추천 TOP 3]"
} > "$SUMMARY_FILE"

echo "📚 Brainstorm #${BRAIN_N} 완료 — $SUMMARY_FILE"
```

---

## 활용 예시

- `/agentea-brainstorming "UI 다크모드 토글 위치 후보"`
- `/agentea-brainstorming "API 페이지네이션 전략"`
- `/agentea-brainstorming "이번 제품 이름 후보"`
- `/agentea-brainstorming "에러 처리 패턴 개선 아이디어"`

## CRITICAL 규칙

- 주제는 한 문장으로 명확하게 (긴 컨텍스트 필요 시 TOPIC_FILE에 직접 첨부)
- 각 에이전트 응답은 독립적으로 수집 (서로의 답을 보지 않음 = 다양성 확보)
- 통합 단계는 Claude가 담당 (중복 제거 + 추천 TOP)
