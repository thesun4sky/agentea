# Spec: agentea Multi-Agent Skillset Redesign

**slug**: `agentea-multi-agent-skillset-redesign`
**type**: brownfield
**source**: deep-dive
**ambiguity_score**: ~0.12 (threshold 0.2 통과)

---

## Goal

현재 단일 SKILL.md(755줄) 모놀리식 구조의 `agentea`를 다음으로 재설계:

1. 지원 에이전트 확장: `codex`, `grok`, **`antigravity` (agy) 추가**
2. 단일 스킬을 **8개 서브 스킬**로 분해:
   - `/agentea` — ON 진입점 (모드 + 에이전트 선택)
   - `/agentea-status` — 활성 에이전트 주소/상태 조회
   - `/agentea-ask` — 메시지 전송 (default: broadcast)
   - `/agentea-review` — 다중 에이전트 코드 리뷰
   - `/agentea-council` — 결정 안건 투표
   - `/agentea-brainstorming` — 아이데이션 세션 (신규)
   - `/agentea-clear` — `.agentea/` 산출물 + state 히스토리 리셋
   - `/agentea-off` — pane 종료 + 비활성화
3. **모드 게이팅**: `auto`(자동 트리거) vs `manual`(명시 호출만)
4. **broadcast가 default**: 모든 명령은 활성 에이전트 전체에게 전송, 특정 지정은 옵션

ios-* 그룹의 약결합 multi-skill 모델 + `lib/common.sh` 공유 헬퍼 추출 패턴 적용.

---

## Constraints

### 명명 컨벤션
- 모든 서브 스킬은 `agentea-<verb>` **하이픈** 패턴 (콜론은 플러그인 marketplace 전용으로 로컬 불가)
- ios-{fix,clean,design-review,qa,sync} 그룹과 동형

### 상태 공유
- **단일 상태 파일**: `~/.claude/agentea-state.json`
- 락 메커니즘 없음 — 단일 사용자/단일 세션 가정 (기존 시스템 컨벤션 따름)
- 모든 서브스킬 진입 시 `_load_state` 호출 → `mode != "on"`이면 안내 후 종료

### 공유 코드
- `~/.claude/skills/agentea/lib/common.sh`에 다음 함수 추출:
  - `_load_state`, `_save_state`
  - `_send_to_agent <name> <msg>`, `_broadcast <msg>`
  - `_classify_screen <content>` (trust/login/error/busy/ready 분류)
  - `_check_agent_startup <surface> <agent_name>`
  - `_wait_file <path> [timeout]`
  - `_status_icon <status>`
  - `_active_agents` (state에서 enabled+ready 에이전트 목록 반환)
- 각 서브 스킬 SKILL.md는 첫 줄에 `source ~/.claude/skills/agentea/lib/common.sh`

### 모드 게이팅
- frontmatter `mode` 필드는 **만들지 않음** (시스템 컨벤션상 부재)
- state JSON의 `"mode": "on|off|pending"`와 `"interaction_mode": "auto|manual"`로 표현
- 각 서브스킬은 진입 시 `mode == "on"` 확인
- `auto` 모드일 때만 Claude가 description 키워드 기반으로 자동 트리거 (`/agentea-review`, `/agentea-council` 등)
- `manual` 모드에서는 명시적 슬래시 커맨드만 동작

### Broadcast 우선 원칙
- `_send_to_agent`는 default가 broadcast (`/agentea-ask "메시지"`)
- 특정 에이전트만 지정: `/agentea-ask <agent> "메시지"` (예: `/agentea-ask codex "..."`)
- 같은 원칙이 review, council, brainstorming, clear, off 등 모든 서브스킬에 적용

### antigravity 통합 사양
- 실행 명령: `agy` (사용자 환경에 설치 확인됨)
- `_classify_screen`에 분류 단서 추가: `gemini|agy|antigravity` 키워드, Gemini CLI 설정 import 제안 패턴 (출현 시 자동 거절 또는 사용자 안내)
- OAuth 패턴은 codex/grok과 동형 (브라우저 자동 오픈 또는 device-code) — 기존 login_prompt 처리 로직 재사용

---

## Non-Goals

- ❌ codex/grok/antigravity 외 새 에이전트(claude-code 외부) 추가
- ❌ JSON 락 메커니즘 구현 (기존 시스템과 동일하게 last-write-wins)
- ❌ 자동 트리거를 위한 hook 시스템 구축 (description 키워드 + state.interaction_mode로 충분)
- ❌ ios-* 그룹처럼 외부 StateServer 도입
- ❌ frontmatter에 `mode: auto|manual` 같은 신규 필드 도입
- ❌ `/agentea-broadcast` 별도 스킬 (broadcast가 default이므로 불필요)

---

## Acceptance Criteria

| # | 기준 | 검증 방법 |
|---|---|---|
| AC1 | `/agentea` 실행 → AskUserQuestion으로 모드(auto/manual) + 에이전트 멀티셀렉트(codex/grok/agy) 인터랙션 표시 | 실제 실행 |
| AC2 | `/agentea on auto codex grok agy` 형태 인자 직접 입력 시 인터랙션 스킵 | 실제 실행 |
| AC3 | 8개 서브 스킬 모두 독립 SKILL.md 파일 존재 | `ls ~/.claude/skills/agentea-*/SKILL.md` |
| AC4 | `lib/common.sh` 존재 + 모든 서브 스킬이 `source` 함 | `grep -l "source.*common.sh" ~/.claude/skills/agentea*/SKILL.md` |
| AC5 | `mode != "on"`인 상태에서 서브 스킬 호출 시 안내 후 종료 | state 강제 변경 후 호출 |
| AC6 | `interaction_mode == "manual"`일 때 자동 review 트리거 안 됨 | manual 모드로 작업 → 자동 발동 없음 확인 |
| AC7 | `interaction_mode == "auto"`일 때 코드 수정 완료 직후 review가 자동 발동 | auto 모드 작업 → 자동 review 확인 |
| AC8 | `/agentea-ask "메시지"` → 모든 활성 에이전트 broadcast | state 확인 + 각 pane 전송 확인 |
| AC9 | `/agentea-ask codex "메시지"` → codex pane만 전송 | 다른 pane 변화 없음 확인 |
| AC10 | `_classify_screen`이 agy 시작 화면을 ready/trust/login 중 하나로 분류 | 실제 `agy` 실행 화면 캡처 후 분류 |
| AC11 | `/agentea-clear` 실행 시 `.agentea/` 산출물 + state.decisions/review_sessions 비워짐. mode·agents 유지 | 실행 전후 비교 |
| AC12 | `/agentea-off` 실행 시: 각 pane에 Ctrl+C+exit → cmux pane 닫힘 → state.mode="off" + agents[*].surface=null | 실행 후 `cmux tree` 확인 |
| AC13 | `/agentea-brainstorming "주제"` → 모든 활성 에이전트에 아이디어 요청, 각자 `.agentea/brainstorm_<agent>_<n>.md` 저장 | 파일 생성 확인 |
| AC14 | `/agentea-council "안건"` → 3자 투표 → `.agentea/council_<n>.md` + 각 vote 파일 생성 | 파일 생성 확인 |
| AC15 | Review Loop는 Claude 본인 + 활성 에이전트 모두 LGTM 시 종료 | 3자 LGTM 시나리오 실행 |
| AC16 | 기존 단일 SKILL.md → 멀티 스킬 마이그레이션 시 사용자 state 호환 (가능하면 마이그레이션, 안 되면 명확한 안내) | upgrade 시뮬레이션 |

---

## Assumptions Exposed

| # | 가정 | 위험 | 검증 시점 |
|---|---|---|---|
| A1 | antigravity의 first-run 인터럽트 시퀀스가 codex/grok과 유사 (trust/login/ready) | Medium — Gemini import 제안 등 신규 단계 존재 가능 | 구현 후 첫 실행 시 사용자가 화면 캡처 공유, `_classify_screen` 보강 |
| A2 | cmux가 agy의 TUI(alternate screen buffer)를 정상 캡처 | Medium — codex/grok에서는 검증됨 | 첫 실행 시 |
| A3 | Bash 함수 추출 + `source` 패턴이 Claude Code의 슬래시 커맨드 실행 환경에서 동작 | Low — 표준 Bash 관용구 | 첫 서브 스킬 테스트 시 |
| A4 | 단일 사용자/단일 세션 사용 (동시 두 서브스킬 호출 없음) | Low | 가정으로 두고 진행 |
| A5 | description 키워드 기반 자동 트리거가 Claude에게 안정적으로 인식됨 | Low-Medium — 현재 agentea도 이 패턴 | 기존 패턴 재사용 |
| A6 | `/agentea-ask` 인자 파싱: 첫 토큰이 알려진 에이전트 이름이면 특정 지정, 아니면 broadcast로 해석 | Low — 명확한 규칙 | 구현 시 |

---

## Technical Context

### 디렉토리 구조

```
~/.claude/skills/
├── agentea/
│   ├── SKILL.md              # /agentea — ON 진입점
│   ├── lib/
│   │   └── common.sh         # 공유 헬퍼 함수
│   └── docs/
│       └── agents.md         # 에이전트별 설치/시작 가이드
├── agentea-status/SKILL.md
├── agentea-ask/SKILL.md
├── agentea-review/SKILL.md
├── agentea-council/SKILL.md
├── agentea-brainstorming/SKILL.md
├── agentea-clear/SKILL.md
└── agentea-off/SKILL.md
```

### 상태 스키마

`~/.claude/agentea-state.json`:
```json
{
  "mode": "on|off|pending",
  "interaction_mode": "auto|manual",
  "work_dir": "/path/to/project",
  "my_surface": "<claude surface uuid>",
  "agentea_dir": "/path/to/project/.agentea",
  "agents": {
    "codex":       {"surface": "surface:N|null", "enabled": true|false, "status": "ready|busy|trust_prompt|login_prompt|error_state|unreachable|null"},
    "grok":        {"surface": "surface:N|null", "enabled": true|false, "status": "..."},
    "antigravity": {"surface": "surface:N|null", "enabled": true|false, "status": "..."}
  },
  "session_start": "ISO8601",
  "decisions": [],
  "review_sessions": []
}
```

활성 에이전트 정의: `agents[k].enabled == true && agents[k].status` ∈ `{ready, ready(codex), ready(grok), ready(antigravity), busy}`

### lib/common.sh 함수 목록 (확정)

```
_load_state                        # state JSON 읽어 환경변수에 로드
_save_state <key> <value>          # state JSON 부분 갱신 (python heredoc 사용)
_classify_screen <content>         # trust/login/error/busy/ready 분류
_status_icon <status>              # ✅⏳⚠️🔐🔴💀
_check_agent_startup <surf> <name> # 5회 재시도하며 ready까지 대기
_send_to_agent <name> <msg>        # 단일 에이전트 전송
_broadcast <msg>                   # 모든 활성 에이전트 전송
_active_agents                     # enabled+ready 에이전트 이름 리스트
_wait_file <path> [timeout]        # 파일 생성 대기
_resolve_agent_cli <name>          # name → 실제 CLI 명령어 (codex/grok/agy)
_agent_login_guide <name> <surf>   # 로그인 안내 메시지 출력
_parse_ask_target <args...>        # 첫 토큰이 에이전트인지 판단
```

### 자동 트리거 메커니즘

- 각 서브 스킬 SKILL.md `description`에 트리거 키워드 포함
- 예: `agentea-review` description: "Use after Claude completes code modifications when agentea is ON in auto mode. Triggers multi-agent code review."
- Claude는 키워드 매칭으로 스스로 트리거, 단 진입 시 `_load_state` 호출 → `interaction_mode == "manual"`이면 "manual 모드입니다. `/agentea-review`를 명시 호출하세요." 출력 후 종료
- 즉, 게이팅은 **state 진입 체크**로 일원화 (hook 시스템 불필요)

### 마이그레이션 전략

기존 사용자 호환:
1. `/agentea` 실행 시 기존 state 파일 감지
2. 구 스키마(`codex_surface`, `grok_surface` 단일 필드)면 새 스키마(`agents.*`)로 자동 변환
3. `interaction_mode` 없으면 default `auto`로 설정
4. 마이그레이션 완료 안내 출력

기존 단일 SKILL.md는 새 `~/.claude/skills/agentea/SKILL.md`(ON 진입점)로 대체. `/Users/teasunkim/work/agentea/` repo는 신규 디렉토리 구조 반영.

### Review Loop 변경 (활성 에이전트 N자 LGTM)

기존: 3자(Claude + Codex + Grok) LGTM
신규: **(1 + N)자 LGTM** — Claude + 활성 에이전트 N개 모두 LGTM

`.agentea/` 파일 구조:
```
review_r1.diff
claude_r1.md
codex_r1.md          (codex 활성 시)
grok_r1.md           (grok 활성 시)
antigravity_r1.md    (antigravity 활성 시)
issues_r1.md
fixes_r1.md
```

---

## Ontology

| 용어 | 의미 |
|---|---|
| **agent** | 협업 대상 외부 CLI: `codex` \| `grok` \| `antigravity` |
| **active agent** | `state.agents[k].enabled && status ∈ {ready, busy}` |
| **surface** | cmux pane 식별자 (예: `surface:16` 또는 UUID) |
| **mode** | 스킬 활성화 상태: `on` (동작 중) / `off` (비활성) / `pending` (설정 필요) |
| **interaction_mode** | 자동 트리거 여부: `auto` (Claude가 키워드로 자동) / `manual` (명시 호출만) |
| **broadcast** | 모든 활성 에이전트에 동일 메시지 전송 (default 동작) |
| **subskill** | `/agentea-<verb>` 형태의 독립 SKILL.md (8개) |
| **lib/common.sh** | 모든 subskill이 `source`하는 공유 헬퍼 |

### Ontology Convergence

- "mode"는 ON/OFF만 의미, "interaction_mode"가 auto/manual을 의미 — 2축으로 분리해야 혼동 없음
- "active"는 enabled + reachable 둘 다 — disabled 에이전트는 broadcast 대상이 아니고, error/unreachable 상태도 제외

---

## Trace Findings

### Per-Lane Outcomes

**Lane 1 (Strong)** — 자산 분해 가능성:
- 공유 함수 명확히 식별: `_load_state`, `_send_codex`, `_classify_screen`, `_wait_file` 등
- `_classify_screen` 이미 SKILL.md 내 2회 중복 (L97 + L571) — 추출 시그널
- 권장: `lib/common.sh` 추출 + 각 서브스킬 첫 줄에서 `source`

**Lane 2 (Strong, 간접)** — antigravity 통합:
- Homebrew cask `antigravity-cli` v1.0.1 확정, `agy` 바이너리
- 인증/TUI/`>` prompt 패턴이 codex/grok과 동형 (커뮤니티 출처)
- 인터뷰에서 사용자가 "설치되어 있고 agy로 실행" 확인 → first-run 인터럽트 시퀀스는 구현 후 첫 실행 시 보강

**Lane 3 (Strong)** — 분해 컨벤션:
- 하이픈 네이밍 검증 (ios-*, plan-*, design-* 다수 사례)
- 콜론은 플러그인 marketplace 전용으로 로컬 스킬에 사용 불가
- 모드 게이팅은 frontmatter 아닌 state JSON 필드로 표현 (기존 시스템 컨벤션)
- 누락 발견: `council` 별도 분리 필요, `broadcast`는 default 동작이라 별도 스킬 불필요

### Inter-Lane Convergence

- Lane 1 + Lane 3 수렴: 공유 헬퍼 추출 + ios-* 약결합 모델 = 정확히 일치
- Lane 2는 독립 영역, 통합 시점에 만 의존

### Resolved Critical Unknowns

| Lane | 미해결 사항 (이전) | 인터뷰 후 해소 |
|---|---|---|
| 1 | 서브스킬 독립 프로세스 여부 | `lib/common.sh` + `source` 패턴 채택으로 무관해짐 |
| 2 | agy first-run 시퀀스 | 사용자 환경에 설치 확인 → 구현 후 보강 전략 합의 |
| 3 | 공유 헬퍼 추출 vs 복사 | 추출 방식 확정 |

### Outstanding Risks (구현 단계 모니터링)

- A1, A2 (antigravity 화면 캡처 가능 여부) — 첫 실행 시 검증
- A5 (자동 트리거 안정성) — 기존 agentea의 description 패턴 재사용으로 위험 낮음

---

## Interview Transcript

**Round 1 — 4 핵심 질문 일괄 응답**:
- Q1 (antigravity 설치): "설치되어있고 agy 명령어 입력하면 실행됩니다"
- Q2 (auto/manual 의미): "네 맞습니다. (a)가 맞아요" (Claude가 description 기반 자동 트리거)
- Q3 (council 처리): "(a) 별도 분리, + /agentea-brainstorming 추가"
- Q4 (broadcast): "기본적으로 모든 활성 에이전트에 보내는 거 아닌가요?" — **핵심 통찰** — broadcast가 default로 재설계

**Round 2 — 4가지 디테일 합리적 기본값 확인**: 사용자 "OK"
- Q1 (ON 인터랙션): 인자 없으면 AskUserQuestion 2단계, 있으면 그대로
- Q2 (자동 트리거): description 키워드 + state.interaction_mode 게이팅
- Q3 (clear 범위): `.agentea/` 산출물 + state 히스토리만, pane/mode 유지
- Q4 (off 동작): Ctrl+C+exit → cmux pane 닫기 → state.mode="off" + agents[*].surface=null

**최종 모호성**: ~0.12 (threshold 0.2 통과)
