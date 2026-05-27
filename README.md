# 🫖 agentea — Multi-Agent Tea Party for Claude Code

> Claude Code + Codex + Grok + Antigravity(agy) 가 함께 코드리뷰·아이디에이션·의사결정하는 다중 에이전트 협업 스킬셋

[![Claude Code Skill](https://img.shields.io/badge/Claude%20Code-Skill-blue)](https://claude.ai/claude-code)
[![cmux](https://img.shields.io/badge/requires-cmux-green)](https://cmux.com)

---

## 🎯 무엇인가요?

여러 AI 에이전트가 같은 cmux 워크스페이스에서 **함께** 일하게 해주는 8개의 협업 스킬:

| 에이전트 | 역할 |
|---|---|
| **Claude Code** | 오케스트레이터 + 코드 수정 (유일하게 소스 파일을 직접 편집) |
| **Codex** (GPT-5.5) | 독립 리뷰어 |
| **Grok** (xAI) | 독립 리뷰어 |
| **Antigravity** (Google `agy`) | 독립 리뷰어 |

모든 명령은 기본적으로 **활성 에이전트 전체에 broadcast** 되며, 특정 에이전트만 타겟하려면 명시 지정합니다.

---

## ✨ 스킬셋 (8개)

| 명령 | 역할 |
|---|---|
| `/agentea` | ON — 모드(auto/manual) + 에이전트(codex/grok/agy) 선택 후 cmux pane 자동 생성, 로그인 확인, role_guide 전송 |
| `/agentea-status` | 활성 에이전트 주소 + 실시간 상태(✅ready / ⏳busy / 🔐login / 🔴error / 💀unreachable / ❓unknown) 조회 |
| `/agentea-ask` | 메시지 전송 (default: broadcast / 첫 토큰이 에이전트면 타겟 전송) |
| `/agentea-review` | (1+N)자 LGTM 코드 리뷰 루프 (최대 5라운드) |
| `/agentea-council` | 결정 안건 투표 — 합의 / 이견 자동 감지 (최대 3라운드) |
| `/agentea-brainstorming` | 다같이 아이디에이션 — 독립 응답 + Claude 통합 요약 |
| `/agentea-clear` | `.agentea/` 산출물 + state 히스토리 리셋 (pane은 유지) |
| `/agentea-off` | 각 pane에 Ctrl+C+exit → cmux pane 닫기 → state.mode=off |

### 모드

- **auto** — Claude가 작업 완료 후 description 키워드로 자동 트리거 (`/agentea-review`, `/agentea-council` 등)
- **manual** — 자동 트리거 차단, 사용자가 명시 호출만

---

## 📋 Prerequisites

| 도구 | 설치 방법 |
|------|----------|
| [cmux](https://cmux.com) | macOS 앱 |
| [Claude Code](https://claude.ai/claude-code) | `npm i -g @anthropic-ai/claude-code` |
| [Codex CLI](https://github.com/openai/codex) | `npm i -g @openai/codex` (ChatGPT Plus/Pro/Team 구독) |
| [Grok CLI](https://github.com/xai-org/grok-cli) | Grok Build 설치 (xAI 구독) |
| [Antigravity CLI](https://antigravity.google/download#antigravity-2) | 아래 설치 명령 참조 (Google 계정) |
| [GitHub CLI](https://cli.github.com/) | `brew install gh && gh auth login` (`/agentea-review pr` 사용 시 필요, GitHub 전용) |

**Antigravity CLI 설치** (macOS)
```bash
curl -fsSL https://antigravity.google/cli/install.sh | bash
```
설치 후 `agy` 명령으로 Google 계정 로그인을 완료합니다.

⚠️  모든 에이전트는 **구독 계정 OAuth** 방식으로 로그인합니다 (API key 아님).

---

## 🚀 설치

### Option A: git clone (권장)

```bash
# ~/.claude/agentea-src에 clone (skills/ 밖 → 스킬 로더 중복 인식 방지)
git clone https://github.com/thesun4sky/agentea ~/.claude/agentea-src
mkdir -p ~/.claude/skills

# 8개 스킬을 ~/.claude/skills/ 에 배치 (재설치 시에도 안전하게 덮어쓰기)
rm -rf ~/.claude/skills/agentea
ln -sfn ~/.claude/agentea-src ~/.claude/skills/agentea
for sub in status ask review council brainstorming clear off; do
  rm -rf ~/.claude/skills/agentea-$sub
  ln -sfn ~/.claude/agentea-src/agentea-$sub ~/.claude/skills/agentea-$sub
done
```

> ℹ️  원본은 `~/.claude/agentea-src`에 있고, `~/.claude/skills/` 에는 symlink만 생성됩니다. 스킬 로더가 `agentea-src` 자체를 노출하지 않습니다. 업데이트는 `cd ~/.claude/agentea-src && git pull`로 가능합니다.

### Option B: 수동 복사

```bash
git clone https://github.com/thesun4sky/agentea /tmp/agentea
mkdir -p ~/.claude/skills  # skills 디렉토리 없을 경우 생성
# 재설치 시 중첩 방지를 위해 기존 경로 제거 후 복사
rm -rf ~/.claude/skills/agentea
cp -r /tmp/agentea ~/.claude/skills/agentea       # SKILL.md + lib/
for sub in status ask review council brainstorming clear off; do
  rm -rf ~/.claude/skills/agentea-$sub
  cp -r /tmp/agentea/agentea-$sub ~/.claude/skills/agentea-$sub
done
```

설치 후 Claude Code를 재시작하거나 `/skills` 명령으로 새 스킬을 인식시킵니다.

---

## 🎮 사용법

### 1) 세션 시작

```
/agentea
```

→ 인터랙티브 모드: 모드(auto/manual) + 에이전트 멀티셀렉트(codex/grok/agy) 질문 → cmux pane 자동 생성 + CLI 실행 + 로그인 확인

또는 인자 직접 지정:
```
/agentea on auto codex grok agy
/agentea on manual codex
```

### 2) 상태 조회

```
/agentea-status
```

### 3) 메시지 전송

```
/agentea-ask "안녕하세요"              # 모든 활성 에이전트에 broadcast
/agentea-ask codex "이 함수 봐줘"      # codex만
/agentea-ask agy "리팩토링 의견 줘"    # antigravity(agy)만
```

### 4) 코드 리뷰 (1+N자 LGTM)

```
/agentea-review                        # 현재 git diff 리뷰
/agentea-review file src/auth.ts       # 특정 파일
/agentea-review pr 123                 # PR 리뷰
/agentea-review commit                 # 최근 커밋
```

### 5) 의사결정 (Council)

```
/agentea-council "REST API vs GraphQL 중 어느 쪽이 나을까요?"
```

### 6) 아이디에이션 (Brainstorming)

```
/agentea-brainstorming "다크모드 토글 위치 후보"
```

### 7) 작업 정리 / 종료

```
/agentea-clear      # .agentea/ 산출물 정리 (다음 작업 깨끗하게 시작)
/agentea-off        # 모든 pane 닫고 세션 종료
```

---

## 📁 .agentea/ 폴더 구조

협업 산출물이 프로젝트 루트의 `.agentea/`에 저장됩니다 (자동으로 `.gitignore`에 `.agentea/` 패턴 추가 → 모든 산출물은 커밋 제외됨):

```
.agentea/
  role_guide.md                 # 에이전트 역할 안내 (ON 시 생성)
  # Review Loop (라운드별)
  review_r1.diff                # 리뷰 대상 (git diff/commit 시 .diff, file 지정 시 원본 확장자 유지)
  claude_r1.md                  # Claude 응답
  codex_r1.md                   # codex 응답 (활성 시)
  grok_r1.md                    # grok 응답 (활성 시)
  antigravity_r1.md             # agy 응답 (활성 시)
  issues_r1.md                  # 통합 이슈
  fixes_r1.md                   # Claude 수정 내역
  # Council
  council_1.md                  # 안건
  codex_vote_1.md               # 투표
  grok_vote_1.md
  antigravity_vote_1.md
  # Brainstorming
  brainstorm_topic_1.md         # 주제
  brainstorm_claude_1.md        # Claude 아이디어
  brainstorm_<agent>_1.md       # 각 에이전트 아이디어
  brainstorm_summary_1.md       # Claude 통합 요약
```

---

## 🏗️ 아키텍처

### Source Repository Layout (저장소 루트)

> clone 후 폴더 이름은 자유 (`agentea`, `agentea-src` 등). 설치 시 symlink로 `~/.claude/skills/agentea/`에 연결됩니다.

```
agentea/                        # 저장소 루트 (clone 후 이름은 자유)
├── SKILL.md                    # /agentea 진입점 (symlink 후 Claude가 인식)
├── lib/
│   └── common.sh               # 공유 헬퍼 17개 함수 (전 서브스킬이 source)
├── agentea-status/SKILL.md
├── agentea-ask/SKILL.md
├── agentea-review/SKILL.md
├── agentea-council/SKILL.md
├── agentea-brainstorming/SKILL.md
├── agentea-clear/SKILL.md
└── agentea-off/SKILL.md
```

### Installed Layout (설치 후 `~/.claude/skills/`)

```
~/.claude/skills/
├── agentea/          → symlink to agentea-src/   (또는 복사)
├── agentea-status/   → symlink to agentea-src/agentea-status/
├── agentea-ask/      → ...
├── agentea-review/   → ...
├── agentea-council/  → ...
├── agentea-brainstorming/ → ...
├── agentea-clear/    → ...
└── agentea-off/      → ...
```

상태 파일: `~/.claude/agentea-state.json` (모든 서브스킬이 공유, v1 → v2 자동 마이그레이션).

### 핵심 설계 원칙

| # | 원칙 |
|---|---|
| P1 | **Broadcast가 default** — 명령은 활성 에이전트 전체로, 특정 지정은 옵션 |
| P2 | **각 서브커맨드를 독립 SKILL.md 파일로 분리하는 단일 책임 원칙 + `lib/common.sh` 공유** — 8개 독립 SKILL.md, 17개 공유 함수는 source |
| P3 | **단일 사용자/단일 세션 가정** — 락 메커니즘 없이 last-write-wins |
| P4 | **기존 사용자 마이그레이션 호환** — 구 스키마 자동 감지 + 자동 변환 (백업: `agentea-state.json.bak.<epoch>`) |
| P5 | **State 진입 체크로 게이팅** — `mode` + `interaction_mode` 두 축으로 분리 |

### CRITICAL 규칙

- 코드/diff를 명령어에 직접 붙이지 말 것 (Pasted Content 모드 방지) → 파일 경로 전달
- 멀티라인 메시지 금지 → 단일 라인만 (`cmux send` + `cmux send-key Return` 분리)
- 응답은 `.agentea/` 파일에 저장 → `read-screen` 잘림 없음
- 외부 에이전트(codex/grok/agy)는 소스 수정 금지 — `role_guide.md`로 안내

---

## 🔧 트러블슈팅

| 증상 | 원인 | 해결 방법 |
|---|---|---|
| `ERROR: agentea lib/common.sh not found` | 스킬 경로 불일치 | `ls ~/.claude/skills/agentea/lib/common.sh` 확인 후 재설치 |
| 에이전트 pane 생성 후 로그인 화면 | OAuth 세션 만료 | 해당 pane에서 직접 로그인 후 `/agentea` 재실행 |
| `_wait_file` 타임아웃 | 에이전트가 응답 파일 미저장 | `/agentea-status` 로 상태 확인, 에이전트 pane 직접 점검 |
| `cmux: command not found` | cmux 미설치 | [cmux.com](https://cmux.com) 에서 macOS 앱 설치 |
| `/agentea-review pr 123` 실패 | gh CLI 미설치/미로그인 | `brew install gh && gh auth login` 실행 |

---

## 🤝 기여

PR / 이슈 환영합니다.

- 새로운 에이전트 지원 (Cursor, Continue, Aider, …)
- tmux/zellij/Windows Terminal 지원 (현재 cmux only)
- 자동화된 통합 테스트 (현재는 수동 검증)

### 새 서브스킬 추가하기

```bash
# 1) 저장소 루트에 새 디렉토리 생성
mkdir agentea-mynewskill

# 2) SKILL.md 작성 (기존 agentea-ask/SKILL.md 참조)
cat > agentea-mynewskill/SKILL.md << 'EOF'
# /agentea-mynewskill — 설명
...
EOF

# 3) common.sh source 후 _require_on 가드 추가 (필수)
# 4) 설치 스크립트에 'mynewskill' 항목 추가
# 5) 이 README의 스킬셋 표에 신규 행 추가
```

---

## 📄 라이선스

MIT License

---

*🫖 "코드리뷰는 혼자 하는 것보다 넷이 하는 게 낫습니다"*
