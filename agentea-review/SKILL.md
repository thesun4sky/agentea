---
name: agentea-review
description: Use after Claude completes code modifications when agentea is ON in auto mode — triggers a (1+N)-agent code review loop (Claude + every active external agent). In manual mode, only fires on explicit invocation. Reads diff, broadcasts review request, collects responses, integrates issues, iterates up to 5 rounds until everyone says LGTM. Keywords - "review the code", "리뷰해줘", "코드 봐줘", "PR 확인해줘".
argument-hint: "[<file-or-diff-path>]"
---

# /agentea-review — (1+N)자 LGTM 코드 리뷰 루프

## 동작

Claude + 모든 활성 외부 에이전트(N개)가 동일한 diff를 병렬 리뷰. 모두 LGTM이어야 종료.

```
Round N 시작
  ├─ 리뷰 파일 → .agentea/review_rN.* 저장
  ├─ Codex, Grok, Antigravity (활성) 에게 broadcast
  ├─ Claude 자신도 같은 파일 직접 리뷰 → .agentea/claude_rN.md
  └─ 응답 파일 대기
       ↓
  3+α 자 결과 통합 → .agentea/issues_rN.md
       ↓
  모두 LGTM? ──Yes──→ 🎉 완료
       │
      No
       ↓
  Claude가 이슈 수정 → .agentea/fixes_rN.md
       ↓
  Round N+1 (최대 5라운드)
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

# manual 모드에서 자동 트리거 차단 (명시 호출은 AGENTEA_EXPLICIT_CALL=1로 우회)
if [ "$INTERACTION_MODE" = "manual" ] && [ -z "${AGENTEA_EXPLICIT_CALL:-}" ]; then
  echo "ℹ️  manual 모드 — /agentea-review 를 직접 명시 호출하세요"
  echo "   (auto 모드 사용은 /agentea 재실행 후 모드 변경)"
  exit 0
fi
```

### 리뷰 대상 결정

| 사용자 의도 | 명령 | 저장 |
|---|---|---|
| 방금 수정한 변경 | (기본) | `git diff HEAD > .agentea/review_r1.diff` |
| PR #N | `/agentea-review pr 123` | `gh pr diff 123 > .agentea/review_r1.diff` |
| 최근 커밋 | `/agentea-review commit` | `git show HEAD > .agentea/review_r1.diff` |
| 특정 파일 | `/agentea-review file path/to/x.ts` | `cp file .agentea/review_r1.ext` |

### Round 실행

```bash
ROUND=1
REVIEW_FILE="$AGENTEA_DIR/review_r${ROUND}.diff"
git diff HEAD > "$REVIEW_FILE"   # 또는 위 표에 따라 준비

# 이전 라운드 잔여물 정리
rm -f "$AGENTEA_DIR/codex_r${ROUND}.md" \
      "$AGENTEA_DIR/grok_r${ROUND}.md" \
      "$AGENTEA_DIR/antigravity_r${ROUND}.md" \
      "$AGENTEA_DIR/claude_r${ROUND}.md"

# 활성 에이전트별 응답 파일 경로 결정
declare -A RESP_FILE
while IFS= read -r agent; do
  RESP_FILE[$agent]="$AGENTEA_DIR/${agent}_r${ROUND}.md"
done < <(_active_agents)

# 각 에이전트에 리뷰 요청 (broadcast 패턴이지만 응답 경로가 달라 개별 전송)
for agent in "${!RESP_FILE[@]}"; do
  _send_to_agent "$agent" \
    "🔍 REVIEW #${ROUND}: $REVIEW_FILE 읽고 결과를 ${RESP_FILE[$agent]} 에 저장 (ISSUE:/FIX: 형식 또는 마지막 줄 LGTM)"
done

# Claude도 같은 파일을 직접 Read하여 리뷰 → claude_rN.md Write
# (실제로는 Claude가 Read tool로 REVIEW_FILE 읽고 분석 후 Write)
```

### 응답 대기 + 통합

```bash
# 각 에이전트 응답 파일 대기 (180초 타임아웃)
for agent in "${!RESP_FILE[@]}"; do
  _wait_file "${RESP_FILE[$agent]}" 180
done

# LGTM 감지 함수
_has_lgtm() { grep -qiE 'LGTM' "$1" && echo "true" || echo "false"; }
_parse_issues() { grep -E 'ISSUE:|FIX:' "$1" | head -20; }

# 3+α 자 결과 통합
{
  echo "# Round $ROUND — Multi-Agent Review"
  echo ""
  echo "## Claude"
  _parse_issues "$AGENTEA_DIR/claude_r${ROUND}.md"
  for agent in "${!RESP_FILE[@]}"; do
    echo ""
    echo "## $agent"
    _parse_issues "${RESP_FILE[$agent]}"
  done
} > "$AGENTEA_DIR/issues_r${ROUND}.md"

# 모두 LGTM 확인
claude_lgtm=$(_has_lgtm "$AGENTEA_DIR/claude_r${ROUND}.md")
all_lgtm="$claude_lgtm"
for agent in "${!RESP_FILE[@]}"; do
  agent_lgtm=$(_has_lgtm "${RESP_FILE[$agent]}")
  [ "$agent_lgtm" != "true" ] && all_lgtm="false"
done

if [ "$all_lgtm" = "true" ]; then
  echo "🎉 (1+$(echo ${!RESP_FILE[@]} | wc -w))자 LGTM — Round $ROUND 종료"
else
  echo "⚡ 이슈 존재 → Claude 수정 후 Round $((ROUND+1))"
  echo "   통합 이슈: $AGENTEA_DIR/issues_r${ROUND}.md"
fi
```

### 수정 후 다음 라운드

수정 내역은 `.agentea/fixes_rN.md`에 기록. 다음 round는 새 diff로 같은 흐름 반복.

최대 5라운드. 5라운드 후에도 미합의면 사용자 개입 요청.

---

## CRITICAL 규칙

- 코드 직접 붙이지 말 것 — diff 파일 경로만 전달
- 응답 파일이 비어 있으면 라운드 무효 → 에이전트 상태 확인 (`/agentea-status`)
- 활성 에이전트가 0명이면 리뷰 불가 (Claude만 있어도 자체 리뷰는 가능하지만 의미 없음)

## .agentea/ 파일 구조 (라운드별)

```
.agentea/
  review_r1.diff      # 리뷰 대상
  claude_r1.md        # Claude 응답
  codex_r1.md         # codex 응답 (활성 시)
  grok_r1.md          # grok 응답 (활성 시)
  antigravity_r1.md   # agy 응답 (활성 시)
  issues_r1.md        # 통합 이슈
  fixes_r1.md         # Claude 수정 내역
```
