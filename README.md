# 🫖 agentea — 3-Agent Tea Party for Claude Code

> Claude Code + Codex + Grok이 함께 코드리뷰 & 의사결정하는 다중 에이전트 협업 스킬

[![Claude Code Skill](https://img.shields.io/badge/Claude%20Code-Skill-blue)](https://claude.ai/claude-code)
[![cmux](https://img.shields.io/badge/requires-cmux-green)](https://cmux.com)

---

## 🎯 무엇인가요?

세 AI 에이전트가 같은 터미널 워크스페이스에서 **함께** 코드를 리뷰하고 의사결정합니다:

- **Claude Code** (오케스트레이터 + 코드 수정)
- **Codex** (GPT-5.5 기반 독립 리뷰어)
- **Grok** (xAI Grok 기반 독립 리뷰어)

셋 모두 LGTM을 줄 때까지 반복적으로 리뷰 → 수정 → 재리뷰합니다.

---

## ✨ 주요 기능

### 🔍 Review Loop
```
Round 1: Claude + Codex + Grok 동시 리뷰
         → 이슈 발견 시 Claude가 수정
Round 2: 세 에이전트 재리뷰
         → 모두 LGTM 시 완료 (최대 5라운드)
```

### 🏛️ Council 모드
아키텍처 결정, 버그픽스 전략 등 중요한 결정이 필요할 때 세 에이전트가 투표합니다.

### 🗂️ 파일 기반 통신
에이전트 응답을 `.agentea/` 폴더의 파일로 수집 — `read-screen` 폴링 없이 신뢰성 높은 협업.

### 🖥️ 자동 Pane 세팅
`/agentea on` 실행 시 cmux에서 Codex·Grok pane을 자동 생성합니다.

---

## 📋 Prerequisites

| 도구 | 설치 방법 |
|------|----------|
| [cmux](https://cmux.com) | macOS 앱 설치 |
| [Claude Code](https://claude.ai/claude-code) | npm i -g @anthropic-ai/claude-code |
| [Codex CLI](https://github.com/openai/codex) | npm i -g @openai/codex |
| [Grok CLI](https://github.com/xai-org/grok-cli) | Grok Build 설치 |

---

## 🚀 설치

```bash
# ~/.claude/skills/agentea/ 디렉토리에 설치
mkdir -p ~/.claude/skills/agentea
curl -fsSL https://raw.githubusercontent.com/thesun4sky/agentea/main/SKILL.md \
  -o ~/.claude/skills/agentea/SKILL.md
```

또는 git clone:
```bash
git clone https://github.com/thesun4sky/agentea ~/.claude/skills/agentea
```

---

## 🎮 사용법

### 세션 시작

```
/agentea on
```

cmux에서 현재 pane 우측에 Codex(위) + Grok(아래) pane이 자동 생성됩니다.

### 코드 리뷰

```
/agentea review
```

현재 `git diff`를 세 에이전트가 동시에 리뷰합니다.

### 특정 대상 리뷰

```
/agentea review src/auth.ts
/agentea review PR #42
/agentea review last commit
```

### 의사결정 (Council)

중요한 결정이 필요할 때:
```
/agentea task "A안(REST API) vs B안(GraphQL) 중 어떤 방식이 나을까요?"
```

### 세션 종료

```
/agentea off
```

---

## 📁 .agentea/ 폴더 구조

협업 파일이 프로젝트 루트의 `.agentea/`에 저장됩니다 (자동으로 `.gitignore` 추가):

```
.agentea/
  role_guide.md          # 에이전트 역할 안내
  review_r1.diff         # Round 1 리뷰 대상 (diff)
  codex_r1.md            # Codex 리뷰 결과
  grok_r1.md             # Grok 리뷰 결과
  issues_r1.md           # 통합 이슈 목록
  fixes_r1.md            # Claude 수정 내역
  council_1.md           # Council 안건
  codex_vote_1.md        # Codex 투표 결과
  grok_vote_1.md         # Grok 투표 결과
```

---

## 🔧 동작 원리

```
1. Claude가 리뷰 대상을 .agentea/review_r1.diff 에 저장
2. Codex에게: "이 파일 읽고 결과를 .agentea/codex_r1.md 에 저장해줘"
3. Grok에게:  "이 파일 읽고 결과를 .agentea/grok_r1.md 에 저장해줘"
4. 파일 생성 감지 → 읽기 → 이슈 통합
5. 이슈 있으면 Claude가 수정 → Round 2
6. 셋 모두 LGTM → 완료 🎉
```

**핵심 설계 원칙:**
- 코드 내용을 명령어에 직접 붙이지 않음 (Pasted Content 모드 방지)
- 응답은 파일로 수집 (화면 버퍼 잘림 없음)
- Codex·Grok은 읽기·제안 전용 — 파일 수정은 Claude Code만

---

## 💡 팁

- Grok은 `always-approve` 모드로 실행하면 자동 파일 저장이 원활합니다
- Codex는 `--yolo` 또는 auto-approve 모드 권장
- 리뷰 라운드가 길어질 경우 `.agentea/issues_rN.md` 에서 통합 이슈 확인 가능

---

## 🤝 기여

PR과 이슈 환영합니다!

- 새로운 에이전트 지원 (Claude.app, Cursor, etc.)
- 윈도우/리눅스 터미널 멀티플렉서 지원 (tmux, zellij)
- agentskills.io 등록

---

## 📄 라이선스

MIT License

---

*🫖 "코드리뷰는 혼자 하는 것보다 셋이 하는 게 낫습니다"*
