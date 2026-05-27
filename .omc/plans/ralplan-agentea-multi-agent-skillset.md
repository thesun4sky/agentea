# RALPLAN: agentea Multi-Agent Skillset Redesign

**Plan ID**: `ralplan-agentea-multi-agent-skillset`
**Date**: 2026-05-28
**Source Spec**: `.omc/specs/deep-dive-agentea-multi-agent-skillset.md`
**Ambiguity**: ~0.12 (threshold 0.2 통과)

---

## 1. Requirements Summary

현재 단일 SKILL.md(755줄, `~/.claude/skills/agentea/SKILL.md`)를 8개 독립 서브 스킬로 분해하고,
antigravity(agy)를 세 번째 에이전트로 추가한다. 공유 헬퍼 12개 함수를 `lib/common.sh`로 추출하여
모든 서브 스킬이 `source`하도록 한다. 모드 게이팅(`auto`/`manual`)을 도입하여 자동 트리거와
명시 호출을 분리하고, broadcast를 default 동작으로 설정한다. 기존 상태 파일(`codex_surface`,
`grok_surface` 평면 구조)에서 새 스키마(`agents.*` 중첩 구조)로 자동 마이그레이션을 지원하며,
Review Loop을 (1+N)자 LGTM 패턴으로 일반화한다. 신규 서브 스킬로 `/agentea-brainstorming`과
`/agentea-council`을 추가한다.

---

## 2. RALPLAN-DR Summary

### Principles (5)

| # | 원칙 | 근거 |
|---|---|---|
| P1 | **Broadcast가 default** | 모든 명령은 활성 에이전트 전체에 전송; 특정 에이전트 지정은 선택적 인자 |
| P2 | **ios-* 하이픈 네이밍 + 독립 SKILL.md 구조를 따르되, 상태 함수 12개 공유를 위해 `source lib/common.sh` 결합 추가** | ios-*는 코드 공유 0건이지만 agentea는 공유 state 함수 12개가 본질이므로 한 단계 높은 결합도 채택 (DRY 우선). ios-* 약결합 모델을 "준수"하는 것이 아니라 그 기반에서 의도적으로 확장한 것임을 명시. |
| P3 | **단일 사용자/단일 세션 가정** | 락 메커니즘 없이 last-write-wins; 기존 시스템 컨벤션과 동일 |
| P4 | **기존 사용자 마이그레이션 호환** | 구 스키마 자동 감지 + 자동 변환; 사용자 개입 없이 투명하게 업그레이드 |
| P5 | **State 진입 체크로 게이팅 일원화** | Hook 시스템 불필요; description 키워드 + `state.interaction_mode` 확인만으로 auto/manual 분리 |

### Decision Drivers (Top 3)

| 순위 | 드라이버 | 이유 |
|---|---|---|
| D1 | **유지보수성** | 755줄 모놀리스 → 8개 독립 파일 + 공유 라이브러리; 각 스킬 독립 수정 가능 |
| D2 | **사용자 경험 연속성** | 기존 `/agentea` 사용자가 별도 조치 없이 새 구조로 전환 |
| D3 | **에이전트 확장성** | N개 에이전트를 agents 맵으로 일반화; 향후 에이전트 추가 시 `_resolve_agent_cli`에 1줄 추가만 필요 |

### Viable Options

#### Decision Area 1: 공유 헬퍼 추출 방식

| 옵션 | 설명 | Pros | Cons |
|---|---|---|---|
| **A: `lib/common.sh` source** (선택) | `~/.claude/skills/agentea/lib/common.sh`에 12개 함수 정의, 각 서브 스킬이 `source` | DRY 원칙 완전 준수; 함수 수정 시 1곳만 변경; ios-* 등 기존 패턴과 정합(ios-*는 코드 공유 안 하지만 agentea는 상태 함수 공유가 필수) | 서브 스킬 실행 시 절대 경로 하드코딩 필요(`~/.claude/skills/agentea/lib/common.sh`); `source` 실패 시 전체 서브 스킬 동작 불능 |
| **B: 각 SKILL.md에 인라인 복사** | 12개 함수를 8개 SKILL.md 각각에 복제 | 각 스킬 완전 독립; source 경로 의존 없음 | 12함수 x 8파일 = 96개 복사본 유지; 버그 수정 시 8곳 동시 수정 필요; DRY 위반 심각 |

**결정: Option A**. Option B는 DRY 위반이 심각하고(12함수 x 8파일), 실제 운영에서 버그 수정 누락 위험이 높아 invalidate됨.

#### Decision Area 2: 마이그레이션 전략

| 옵션 | 설명 | Pros | Cons |
|---|---|---|---|
| **A: 자동 변환** (선택) | `/agentea` ON 시 구 스키마 감지 → 새 `agents.*` 구조로 in-place 변환 + 안내 출력 | 사용자 무개입; UX 끊김 없음; P4 원칙 직접 충족 | 변환 로직 추가 ~30줄; 엣지 케이스(corrupted JSON) 처리 필요 |
| **B: 사용자 안내 후 수동** | 구 스키마 감지 시 경고 출력 + 수동 변환 가이드 링크 제공 | 구현 간단; 변환 실패 위험 없음 | UX 단절; 사용자가 JSON 직접 편집해야 함; 대부분 사용자가 무시할 가능성 |

**결정: Option A**. Option B는 사용자에게 JSON 수동 편집을 요구하여 UX 단절이 불가피하고, P4 원칙에 위배. 자동 변환은 `codex_surface`/`grok_surface` 존재 여부로 명확히 감지 가능하므로 엣지 케이스가 제한적.

### ADR (Architectural Decision Record)

- **Decision**: `lib/common.sh` source 패턴 + 자동 마이그레이션 (timestamp backup)
- **Drivers**: 유지보수성(D1), 사용자 경험 연속성(D2), 에이전트 확장성(D3)
- **Alternatives considered**:
  - 인라인 복사 (Decision Area 1 Option B): rejected — 12 함수 × 8 파일 = 96 복사본 유지 비용 + 버그 수정 누락 위험
  - 수동 마이그레이션 (Decision Area 2 Option B): rejected — JSON 직접 편집 요구가 P4 원칙 위배
  - ouroboros 같은 플러그인 manifest 방식: rejected — 로컬 스킬은 marketplace 메커니즘 불가, 명명 컨벤션이 콜론(`:`)으로 강제됨
- **Why chosen**: DRY 원칙 + 무개입 UX가 기존 사용자 기반에서 가장 중요. correlated failure 위험은 guard clause + 명확한 에러 메시지로 mitigate.
- **Consequences**:
  - `source` 경로 하드코딩 의존 (`~/.claude/skills/agentea/lib/common.sh`)
  - common.sh 부재 시 모든 서브 스킬 동시 실패 (**correlated failure**) — Architect Steelman 인정
  - ios-* 약결합 모델과 다른 결합 강도 (P2에 명시)
- **Follow-ups**:
  - common.sh 존재 확인 guard를 각 서브 스킬 첫 줄에 추가
  - guard 에러 메시지 구체화: `"ERROR: agentea lib/common.sh not found at ~/.claude/skills/agentea/lib/common.sh — run /agentea to reinstall"`
  - 첫 실행 시 antigravity 화면 캡처 → `_classify_screen` 패턴 보강 (A1/A2)
  - 8 스킬 description 키워드 disambiguation 검토 (auto-trigger 정확도)
  - `agy` alias를 `_parse_ask_target`의 `KNOWN_AGENTS`에 포함 (사용자 단축어 지원)

---

## 3. Implementation Steps

### Phase A — Shared Foundation (lib + 새 state 스키마)

의존성: 없음 (첫 번째 phase)

#### A1: `~/.claude/skills/agentea/lib/common.sh` 작성

- **파일**: `~/.claude/skills/agentea/lib/common.sh` (신규)
- **규모**: ~250줄 (12개 함수 + 주석 + guard)
- **내용**:
  - 기존 SKILL.md에서 다음 함수 추출 및 일반화:
    - `_load_state` (L294-300 → agents 맵 기반으로 재작성)
    - `_save_state <key> <value>` (python3 heredoc 사용, agents 중첩 지원)
    - `_classify_screen <content>` — **머지 정책**: L571 버전을 기준(authoritative)으로 함. L571이 가진 패턴(`unreachable` 빈 content 처리, `working` busy 패턴, `ready(codex)`/`ready(grok)` 서브상태, `_status_icon` 매핑) 모두 유지. L97-only 패턴(`신뢰` trust, `api_key` login, `yes/no` confirm)을 L571에 추가 병합. agy 신규 패턴 추가: `gemini|agy|antigravity` 키워드 → `ready(antigravity)`, "Gemini CLI 설정 import 제안" → `import_offer` 신규 상태. 알 수 없는 비빈 content는 `unknown` 반환(`ready` 폴백 금지).
    - `_status_icon <status>` (L585-595)
    - `_check_agent_startup <surface> <agent_name>` (L108-211)
    - `_send_to_agent <name> <msg>` (기존 `_send_codex`/`_send_grok` 통합, name→surface 매핑)
    - `_broadcast <msg>` (L312-315, `_active_agents` 기반으로 일반화)
    - `_active_agents` (신규: state에서 enabled+ready 에이전트 이름 리스트 반환)
    - `_wait_file <path> [timeout]` (L339-345)
    - `_resolve_agent_cli <name>` (신규: codex→codex, grok→grok, antigravity→agy)
    - `_agent_login_guide <name> <surface>` (L155-173 일반화)
    - `_parse_ask_target <args...>` (신규: 첫 토큰이 알려진 에이전트인지 판단)
  - 파일 상단에 guard: `AGENTEA_COMMON_LOADED` 중복 source 방지
  - 상수 정의: `STATE_FILE="$HOME/.claude/agentea-state.json"`, `KNOWN_AGENTS=(codex grok antigravity)`
- **소스 참조**: 기존 SKILL.md L97-106, L108-211, L294-315, L339-345, L571-595

#### A2: state JSON 마이그레이션 함수

- **파일**: `~/.claude/skills/agentea/lib/common.sh` 내에 `_migrate_state_v1_to_v2` 함수 추가
- **규모**: ~30줄 (A1의 250줄에 포함)
- **내용**:
  - 구 스키마 감지: `codex_surface` 키 존재 + `agents` 키 부재
  - 변환: `codex_surface` → `agents.codex.surface`, `grok_surface` → `agents.grok.surface`
  - `interaction_mode` 없으면 `"auto"` default 설정
  - `antigravity` 엔트리 추가 (`enabled: false, surface: null, status: null`)
  - 원본 백업: `agentea-state.json.bak.$(date +%s)` (타임스탬프 포함 — 반복 마이그레이션 시 백업 덮어쓰기 방지)
  - 변환 완료 안내 출력

---

### Phase B — 진입점 재작성 (`/agentea` ON)

의존성: Phase A 완료 필수

#### B1: `~/.claude/skills/agentea/SKILL.md` 재작성

- **파일**: `~/.claude/skills/agentea/SKILL.md` (기존 755줄 → ~300줄로 축소)
- **규모**: ~300줄 (기존 대비 60% 감소)
- **내용**:
  - frontmatter: `name: agentea`, description에 auto/manual 모드 + codex/grok/agy 멀티에이전트 언급
  - `argument-hint: "[on [auto|manual] [codex] [grok] [agy]]"`
  - 첫 줄 bash 블록: `source ~/.claude/skills/agentea/lib/common.sh`
  - Step 1: 인자 파싱 — 인자 있으면 모드+에이전트 직접 설정 (AC2), 없으면 AskUserQuestion 2단계 (AC1)
    - AskUserQuestion 1: 모드 선택 (auto / manual)
    - AskUserQuestion 2: 에이전트 멀티셀렉트 (codex / grok / agy, 체크박스)
  - Step 2: 기존 pane 탐지 (`cmux tree` + `_classify_screen`)
  - Step 3: 없는 에이전트만 pane 생성 + CLI 실행 (`_resolve_agent_cli` 사용)
  - Step 4: `_check_agent_startup` 루프 (선택된 에이전트만)
  - Step 5: 역할 안내 파일 전송 (`role_guide.md`)
  - Step 6: 상태 저장 (새 `agents.*` 스키마)
  - Step 7: `_migrate_state_v1_to_v2` 호출 (구 스키마 감지 시)
  - CRITICAL 규칙 섹션 유지 (기존 Section 9)
  - 알려진 인터럽트 패턴 섹션 유지 + antigravity 추가 (기존 Section 10)
- **삭제 대상**: Section 2(파일 기반 응답 수집), 4(Council), 5(Review Loop), 6(STATUS), 7(OFF) — 각각 별도 서브 스킬로 이동

#### B2: 자동 마이그레이션 통합

- **파일**: `~/.claude/skills/agentea/SKILL.md` 내 Step 7
- **규모**: ~15줄 (B1의 300줄에 포함)
- **내용**: `/agentea` 실행 초기에 state 파일 존재 시 `_migrate_state_v1_to_v2` 호출, 변환 결과 안내

---

### Phase C — 서브 스킬 7개 신규 작성

의존성: Phase A 완료 필수 (common.sh 필요). Phase B와 병렬 가능.

#### C1: `/agentea-status`

- **파일**: `~/.claude/skills/agentea-status/SKILL.md` (신규)
- **규모**: ~120줄
- **내용**:
  - frontmatter: `name: agentea-status`, description에 "상태", "status", "세션 확인" 키워드
  - `source ~/.claude/skills/agentea/lib/common.sh`
  - `_load_state` → `mode != "on"` 체크 (AC5)
  - 각 활성 에이전트 루프: `cmux read-screen` → `_classify_screen` → `_status_icon`
  - antigravity 포함 N개 에이전트 동적 표시 (기존 Section 6, L552-631 기반)
  - `interaction_mode` 표시 추가

#### C2: `/agentea-ask`

- **파일**: `~/.claude/skills/agentea-ask/SKILL.md` (신규)
- **규모**: ~100줄
- **내용**:
  - frontmatter: `name: agentea-ask`, description에 "메시지", "전송", "ask", "send", "broadcast" 키워드
  - `source ~/.claude/skills/agentea/lib/common.sh`
  - `_load_state` → `mode != "on"` 체크 (AC5)
  - `_parse_ask_target` 호출: 첫 인자가 `codex`/`grok`/`antigravity`/`agy`이면 특정 전송 (AC9), 아니면 `_broadcast` (AC8)
  - 인자 없으면 AskUserQuestion으로 메시지 입력 요청
  - 전송 결과 안내 (어떤 에이전트에 전송했는지)

#### C3: `/agentea-review`

- **파일**: `~/.claude/skills/agentea-review/SKILL.md` (신규)
- **규모**: ~200줄
- **내용**:
  - frontmatter: `name: agentea-review`, description에 "code modifications", "review", "리뷰", "코드 봐줘" 키워드 + "when agentea is ON in auto mode" 문구 (자동 트리거용)
  - `source ~/.claude/skills/agentea/lib/common.sh`
  - `_load_state` → `mode != "on"` 체크 (AC5)
  - `interaction_mode == "manual"` 체크: 자동 트리거 시 "manual 모드입니다" 안내 후 종료 (AC6), 명시 호출 시 통과
  - Review Loop 전체 흐름 (기존 Section 5, L425-548 기반):
    - diff 준비 → `_broadcast` 리뷰 요청 → Claude 병렬 리뷰 → 응답 대기
    - (1+N)자 LGTM 감지 (AC15): Claude + `_active_agents` 전원
    - 이슈 통합 → 수정 → 다음 라운드 (최대 5라운드)
  - `.agentea/` 파일 구조: `review_rN.diff`, `claude_rN.md`, `<agent>_rN.md`, `issues_rN.md`, `fixes_rN.md`

#### C4: `/agentea-council`

- **파일**: `~/.claude/skills/agentea-council/SKILL.md` (신규)
- **규모**: ~150줄
- **내용**:
  - frontmatter: `name: agentea-council`, description에 "결정", "투표", "council", "아키텍처 선택" 키워드
  - `source ~/.claude/skills/agentea/lib/common.sh`
  - `_load_state` → `mode != "on"` 체크 (AC5)
  - Council 흐름 (기존 Section 4, L381-421 기반):
    - 안건 파일 작성 → `_broadcast` 투표 요청 → 응답 대기
    - N자 투표 집계 (`_active_agents` 기반) (AC14)
    - 합의/이견/Round 2/최종 결정 로직
  - `.agentea/council_<n>.md` + `<agent>_vote_<n>.md` 파일 구조

#### C5: `/agentea-brainstorming`

- **파일**: `~/.claude/skills/agentea-brainstorming/SKILL.md` (신규)
- **규모**: ~130줄
- **내용**:
  - frontmatter: `name: agentea-brainstorming`, description에 "아이디어", "brainstorm", "브레인스토밍" 키워드
  - `source ~/.claude/skills/agentea/lib/common.sh`
  - `_load_state` → `mode != "on"` 체크 (AC5)
  - 주제 인자 파싱 → `_broadcast` 아이디어 요청
  - 각 에이전트에 `.agentea/brainstorm_<agent>_<n>.md` 저장 지시 (AC13)
  - 응답 수집 후 Claude가 종합 정리 → `.agentea/brainstorm_summary_<n>.md`
  - `interaction_mode` 게이팅 (auto일 때만 자동 트리거, manual은 명시 호출만)

#### C6: `/agentea-clear`

- **파일**: `~/.claude/skills/agentea-clear/SKILL.md` (신규)
- **규모**: ~80줄
- **내용**:
  - frontmatter: `name: agentea-clear`, description에 "초기화", "clear", "클리어", "리셋" 키워드
  - `source ~/.claude/skills/agentea/lib/common.sh`
  - `_load_state` → `mode != "on"` 체크 (AC5)
  - `.agentea/` 내 산출물 삭제: `review_*.diff`, `*_r*.md`, `council_*.md`, `*_vote_*.md`, `brainstorm_*.md`, `issues_*.md`, `fixes_*.md`
  - `role_guide.md`는 유지
  - state JSON에서 `decisions`, `review_sessions` 배열 비우기
  - `mode`, `agents`, `interaction_mode` 유지 (AC11)
  - 삭제된 파일 수 안내

#### C7: `/agentea-off`

- **파일**: `~/.claude/skills/agentea-off/SKILL.md` (신규)
- **규모**: ~100줄
- **내용**:
  - frontmatter: `name: agentea-off`, description에 "종료", "off", "끄기", "비활성화" 키워드
  - `source ~/.claude/skills/agentea/lib/common.sh`
  - `_load_state` (mode 체크 없이 — off 상태에서도 호출 가능하도록)
  - 각 활성 에이전트 루프:
    - `cmux send-key --surface <surface> Ctrl+C` → `cmux send --surface <surface> "exit"` → `cmux send-key Return`
    - pane 닫기 시도
  - state 갱신: `mode="off"`, 각 `agents[*].surface=null`, `agents[*].status=null` (AC12)
  - `cmux tree` 확인 안내

---

### Phase D — antigravity 통합

의존성: Phase A 완료 필수 (common.sh에 추가). Phase B/C와 병렬 가능.

#### D1: `_classify_screen`에 agy 패턴 추가

- **파일**: `~/.claude/skills/agentea/lib/common.sh` 내 `_classify_screen` 함수
- **규모**: ~10줄 추가 (A1 작업의 일부)
- **내용**:
  - `gemini|agy|antigravity` 키워드로 ready 상태 분류 (AC10)
  - Gemini import 제안 패턴 감지: `"import.*Gemini|Gemini CLI.*settings|migrate.*config"` → 별도 상태 `"gemini_import_prompt"` 반환
  - `_status_icon`에 `gemini_import_prompt` → `"🔄"` 아이콘 추가

#### D2: `_check_agent_startup`에 Gemini import 처리

- **파일**: `~/.claude/skills/agentea/lib/common.sh` 내 `_check_agent_startup` 함수
- **규모**: ~15줄 추가 (A1 작업의 일부)
- **내용**:
  - `gemini_import_prompt` 상태 감지 시:
    - 자동 거절 시도 (n/no 전송) 또는
    - 사용자 안내: "Gemini CLI 설정 import 제안 — 거절 권장 (agentea는 독립 설정 사용)"
  - codex/grok과 동형인 trust/login/ready 패턴은 기존 로직 그대로 재사용

#### D3: ON 시 agy 선택 가능한 에이전트로 추가

- **파일**: `~/.claude/skills/agentea/SKILL.md` 내 AskUserQuestion 에이전트 목록
- **규모**: ~5줄 변경 (B1 작업의 일부)
- **내용**:
  - `_resolve_agent_cli` 매핑: `antigravity → agy`
  - `_agent_login_guide`에 antigravity 가이드 추가: "agy 실행 → Google OAuth 로그인"
  - `KNOWN_AGENTS` 배열에 `antigravity` 포함 (A1에서 이미 정의)

---

### Phase E — repo 동기화 + 문서

의존성: Phase B, C 완료 필수

#### E1: `/Users/teasunkim/work/agentea/` repo에 변경사항 반영

- **파일**: repo 내 디렉토리 구조 재구성
- **규모**: 파일 이동 + 신규 파일 생성
- **내용**:
  ```
  /Users/teasunkim/work/agentea/
  ├── SKILL.md                         # 기존 → ON 진입점으로 교체
  ├── lib/
  │   └── common.sh                    # 공유 헬퍼
  ├── subskills/
  │   ├── agentea-status/SKILL.md
  │   ├── agentea-ask/SKILL.md
  │   ├── agentea-review/SKILL.md
  │   ├── agentea-council/SKILL.md
  │   ├── agentea-brainstorming/SKILL.md
  │   ├── agentea-clear/SKILL.md
  │   └── agentea-off/SKILL.md
  ├── docs/
  │   ├── agents.md                    # 에이전트별 설치/시작 가이드
  │   └── migration.md                 # 마이그레이션 가이드
  ├── .agentea/
  │   └── role_guide.md
  └── README.md                        # 업데이트
  ```
  - repo는 개발/버전관리용; 실제 설치는 `~/.claude/skills/` 하위로 복사/심링크
  - 기존 단일 `SKILL.md`는 git history에 보존 (삭제 아닌 교체)

#### E2: 마이그레이션 가이드 + README 업데이트

- **파일**: `/Users/teasunkim/work/agentea/docs/migration.md` (신규), `/Users/teasunkim/work/agentea/README.md` (수정)
- **규모**: migration.md ~60줄, README.md ~100줄 변경
- **내용**:
  - migration.md: 구 → 신 스키마 차이, 자동 마이그레이션 동작 설명, 수동 복구 방법
  - README.md: 8개 서브 스킬 설명, 설치 방법 (`~/.claude/skills/` 복사 절차), 모드 설명

---

### Phase F — 테스트

의존성: Phase A, B, C, D, E 모두 완료 필수

#### F1: `/agentea` ON 인터랙션 검증

- **검증 대상**: AC1 (AskUserQuestion 표시), AC2 (인자 직접 입력 시 스킵)
- **방법**:
  - `/agentea` 인자 없이 실행 → AskUserQuestion 2단계 표시 확인
  - `/agentea on auto codex grok agy` 실행 → 인터랙션 없이 직접 진행 확인

#### F2: `/agentea-status` 검증

- **검증 대상**: AC3 (독립 파일 존재), AC5 (mode 체크)
- **방법**:
  - `ls ~/.claude/skills/agentea-status/SKILL.md` → 파일 존재 확인
  - agentea ON 후 `/agentea-status` → N개 에이전트 + interaction_mode 표시 확인
  - state.mode="off" 강제 설정 후 `/agentea-status` → "agentea가 꺼져 있습니다" 안내 확인

#### F3: `/agentea-ask` broadcast + 특정 에이전트 검증

- **검증 대상**: AC8 (broadcast), AC9 (특정 에이전트)
- **방법**:
  - `/agentea-ask "테스트 메시지"` → 모든 활성 에이전트 pane에 전송 확인
  - `/agentea-ask codex "codex 전용 메시지"` → codex pane만 전송, 다른 pane 변화 없음 확인

#### F4: `/agentea-review` 모드 게이팅 검증

- **검증 대상**: AC6 (manual 차단), AC7 (auto 자동 발동), AC15 (N자 LGTM)
- **방법**:
  - `interaction_mode="manual"` 설정 → 코드 수정 후 자동 review 발동 없음 확인 (AC6)
  - `interaction_mode="auto"` 설정 → 코드 수정 완료 직후 review 자동 발동 확인 (AC7)
  - 2 에이전트 활성 시 3자(Claude+2) LGTM 시나리오 실행 (AC15)

#### F5: `/agentea-clear`, `/agentea-off` 검증

- **검증 대상**: AC11 (clear 범위), AC12 (off 동작)
- **방법**:
  - `.agentea/`에 review/council/brainstorm 파일 생성 → `/agentea-clear` → 산출물 삭제 + mode/agents 유지 확인 (AC11)
  - `/agentea-off` → 각 pane에 Ctrl+C+exit → `cmux tree` 에서 pane 없음 확인 → state.mode="off" + agents[*].surface=null 확인 (AC12)

#### F6: antigravity 분류 검증

- **검증 대상**: AC10
- **방법**: `agy` 실행 화면 캡처 → `_classify_screen` 호출 → ready/trust/login 중 하나 반환 확인

#### F7: 마이그레이션 검증

- **검증 대상**: AC16
- **방법**: 구 스키마 state 파일 수동 생성 (`codex_surface`, `grok_surface` 구조) → `/agentea` 실행 → 새 `agents.*` 구조로 자동 변환 + 안내 출력 확인

#### F8: 전체 서브 스킬 파일 존재 검증

- **검증 대상**: AC3, AC4
- **방법**:
  - `ls ~/.claude/skills/agentea-{status,ask,review,council,brainstorming,clear,off}/SKILL.md` → 7개 + 본체 1개 = 8개 확인 (AC3)
  - `grep -l "source.*common.sh" ~/.claude/skills/agentea*/SKILL.md` → 8개 매칭 확인 (AC4)

#### F9: `/agentea-brainstorming` 검증

- **검증 대상**: AC13
- **방법**:
  - `/agentea-brainstorming "새로운 기능 아이디어"` 실행
  - 각 활성 에이전트에 brainstorm 요청 전송 확인 (cmux read-screen으로 각 pane 메시지 도달 확인)
  - `.agentea/brainstorm_<agent>_<n>.md` 파일 생성 확인 (활성 에이전트 수와 동일, 120초 이내)
  - (선택) `.agentea/brainstorm_summary_<n>.md` 통합 파일 생성 확인
- **기대 결과**: 활성 에이전트 N개 → N개 brainstorm 응답 파일 + 1개 통합 파일

#### F10: `/agentea-council` 검증

- **검증 대상**: AC14
- **방법**:
  - `/agentea-council "아키텍처 선택 안건 A vs B"` 실행
  - `.agentea/council_<n>.md` 안건 파일 생성 확인
  - 각 활성 에이전트별 투표 파일 `<agent>_vote_<n>.md` 생성 확인 (마지막 줄 `VOTE: A|B`)
  - 합의/이견 판정 로직 동작 확인 (모두 같은 표 → `✅ 합의`, 다르면 `⚡ 이견 → Round 2` 안내)
- **기대 결과**: 활성 에이전트 N개 → N개 투표 파일 + 합의/이견 판정 출력

#### F11: End-to-End 라이프사이클 회귀 테스트

- **검증 대상**: 통합 (전체 서브스킬 간 상태 정합성)
- **방법**: `/agentea on auto codex grok` → `/agentea-status` → `/agentea-ask "ping"` → `/agentea-review` → `/agentea-council "결정 테스트"` → `/agentea-brainstorming "아이디어 테스트"` → `/agentea-clear` → `/agentea-off` 순서로 실행
- **기대 결과**: 각 단계마다 state JSON 일관성 유지, .agentea/ 산출물 적절히 생성/정리, 마지막에 cmux pane 모두 닫히고 `mode == "off"`

---

## 4. Risks and Mitigations

| # | 가정 | 위험 수준 | 위험 설명 | 완화 전략 |
|---|---|---|---|---|
| A1 | agy first-run 인터럽트가 codex/grok과 유사 | Medium | Gemini import 제안, theme 선택 등 미확인 단계 존재 가능 | `_classify_screen`에 fallback "unknown_prompt" 분류 추가; 첫 실행 시 사용자 화면 캡처 → 패턴 보강 절차 문서화 |
| A2 | cmux가 agy TUI(alternate screen buffer)를 정상 캡처 | Medium | alternate screen buffer 사용 시 `read-screen`이 빈 내용 반환 가능 | 첫 실행 시 `cmux read-screen` 테스트; 실패 시 `_classify_screen`에 빈 내용 → "busy_or_alternate" 상태 추가 |
| A3 | Bash `source` 패턴이 Claude Code 슬래시 커맨드 환경에서 동작 | Low | Claude Code가 SKILL.md 내 bash 블록을 실행할 때 `source` 지원하지 않을 가능성 | `source` 전에 파일 존재 guard 추가; 실패 시 fallback으로 인라인 최소 함수 세트 제공 |
| A4 | 단일 사용자/단일 세션 사용 | Low | 동시 두 서브스킬 호출 시 state 충돌 | 가정으로 두고 진행; 문서에 "단일 세션 전용" 명시 |
| A5 | description 키워드 자동 트리거 안정성 | Low-Medium | Claude가 키워드를 인식하지 못하거나 과도하게 인식 | 기존 agentea description 패턴 재사용 (이미 검증됨); `interaction_mode` 게이팅으로 이중 안전장치 |
| A6 | `_parse_ask_target` 인자 파싱 규칙 | Low | 에이전트 이름과 동일한 단어가 메시지에 포함될 경우 오판 | 첫 토큰만 검사; 매칭 시 두 번째 토큰부터 메시지로 처리; 알려진 에이전트 목록(`KNOWN_AGENTS`)으로 한정 |

---

## 5. Verification Steps

| AC# | Acceptance Criteria | 검증 방법 | 측정 기준 |
|---|---|---|---|
| AC1 | `/agentea` → AskUserQuestion 모드+에이전트 표시 | Phase F1: 인자 없이 실행, AskUserQuestion 2단계 출현 확인 | AskUserQuestion이 2회 표시됨 (모드 1회 + 에이전트 1회) |
| AC2 | 인자 직접 입력 시 인터랙션 스킵 | Phase F1: `/agentea on auto codex grok agy` 실행 | AskUserQuestion 0회; 직접 pane 생성 진행 |
| AC3 | 8개 서브 스킬 독립 SKILL.md 존재 | Phase F8: `ls ~/.claude/skills/agentea*/SKILL.md` | 8개 파일 리스트 출력 |
| AC4 | `lib/common.sh` 존재 + 모든 서브 스킬이 source | Phase F8: `grep -l "source.*common.sh"` | 8개 파일 매칭 |
| AC5 | `mode != "on"` 시 안내 후 종료 | Phase F2: state 강제 변경 후 서브 스킬 호출 | "agentea가 꺼져 있습니다" 메시지 출력, 서브 스킬 로직 미실행 |
| AC6 | `manual` 모드에서 자동 review 안 됨 | Phase F4: manual 설정 후 코드 수정 | `/agentea-review` 자동 트리거 없음 (5분 관찰) |
| AC7 | `auto` 모드에서 review 자동 발동 | Phase F4: auto 설정 후 코드 수정 완료 | Claude가 `/agentea-review` 자동 호출 |
| AC8 | `/agentea-ask "msg"` → broadcast | Phase F3: 메시지 전송 후 모든 pane 확인 | `_active_agents` 수만큼 pane에 메시지 도착 |
| AC9 | `/agentea-ask codex "msg"` → codex만 전송 | Phase F3: 특정 에이전트 전송 후 타 pane 확인 | codex pane에만 메시지 도착; 다른 pane 변화 없음 |
| AC10 | `_classify_screen`이 agy 화면 분류 | Phase F6: `agy` 화면 캡처 → 분류 함수 호출 | `ready` \| `trust_prompt` \| `login_prompt` 중 하나 반환 (5초 이내) |
| AC11 | `/agentea-clear` 산출물 삭제 + mode/agents 유지 | Phase F5: 실행 전후 비교 | `.agentea/` 내 산출물 0개; state.mode/agents 변화 없음 |
| AC12 | `/agentea-off` pane 종료 + state 갱신 | Phase F5: 실행 후 `cmux tree` + state 확인 | pane 없음; state.mode="off"; agents[*].surface=null |
| AC13 | `/agentea-brainstorming` 파일 생성 | F9 (방금 추가) | `brainstorm_<agent>_<n>.md` 파일 N개 생성 (활성 에이전트 수와 동일, 120초 이내) |
| AC14 | `/agentea-council` 투표 파일 생성 | F10 (방금 추가) | `council_<n>.md` + `<agent>_vote_<n>.md` N개 생성 (120초 이내) |
| AC15 | (1+N)자 LGTM 시 Review Loop 종료 | Phase F4: LGTM 시나리오 | Claude + 활성 에이전트 N개 모두 LGTM → "완료" 메시지 출력 |
| AC16 | 기존 state 호환 마이그레이션 | Phase F7: 구 스키마 → 신 스키마 자동 변환 | `agents.*` 구조 확인; `codex_surface`/`grok_surface` 키 부재; 백업 파일 생성 |

---

## 6. Acceptance Criteria ↔ Phase 매핑

| AC# | 기준 | 충족 Phase |
|---|---|---|
| AC1 | `/agentea` → AskUserQuestion 모드+에이전트 멀티셀렉트 표시 | Phase B (B1) |
| AC2 | 인자 직접 입력 시 인터랙션 스킵 | Phase B (B1) |
| AC3 | 8개 서브 스킬 독립 SKILL.md 존재 | Phase B (B1) + Phase C (C1-C7) |
| AC4 | `lib/common.sh` 존재 + 모든 서브 스킬이 source | Phase A (A1) + Phase C (C1-C7) |
| AC5 | `mode != "on"` 시 안내 후 종료 | Phase C (C1-C7 각각) |
| AC6 | `manual` 모드에서 자동 review 안 됨 | Phase C (C3: agentea-review) |
| AC7 | `auto` 모드에서 review 자동 발동 | Phase C (C3: agentea-review) |
| AC8 | broadcast default | Phase A (A1: `_broadcast`) + Phase C (C2: agentea-ask) |
| AC9 | 특정 에이전트 전송 | Phase A (A1: `_parse_ask_target`) + Phase C (C2: agentea-ask) |
| AC10 | `_classify_screen` agy 분류 | Phase D (D1) |
| AC11 | `/agentea-clear` 산출물 삭제, mode/agents 유지 | Phase C (C6: agentea-clear) |
| AC12 | `/agentea-off` pane 종료 + state 갱신 | Phase C (C7: agentea-off) |
| AC13 | `/agentea-brainstorming` 파일 생성 | Phase C (C5: agentea-brainstorming) |
| AC14 | `/agentea-council` 투표 파일 생성 | Phase C (C4: agentea-council) |
| AC15 | (1+N)자 LGTM Review Loop 종료 | Phase C (C3: agentea-review) |
| AC16 | 기존 state 마이그레이션 | Phase A (A2) + Phase B (B2) |

---

## Phase 의존성 DAG

```
Phase A (Shared Foundation)
  ├──→ Phase B (진입점 재작성)  ──→ Phase E (repo 동기화)
  ├──→ Phase C (서브 스킬 7개)  ──→ Phase E (repo 동기화)
  └──→ Phase D (antigravity)    ──→ Phase E (repo 동기화)
                                          │
                                          ▼
                                    Phase F (테스트)
```

- A는 첫 번째 (의존 없음)
- B, C, D는 A 완료 후 병렬 가능
- E는 B, C, D 모두 완료 후
- F는 E 완료 후

---

## 규모 요약

| Phase | 신규/수정 파일 수 | 추정 총 줄 수 |
|---|---|---|
| A | 1 신규 (common.sh) | ~280줄 |
| B | 1 수정 (SKILL.md 교체) | ~300줄 (기존 755→300) |
| C | 7 신규 (서브 스킬) | ~880줄 (평균 ~126줄) |
| D | 1 수정 (common.sh 내) | ~25줄 추가 (A에 포함) |
| E | 2-3 신규/수정 (repo) | ~160줄 |
| F | 테스트 (파일 아님) | — |
| **합계** | **11-12 파일** | **~1,645줄** |

기존 755줄 모놀리스 → 총 ~1,580줄 (common.sh 280 + 진입점 300 + 서브 스킬 880 + 문서 160)
줄 수 증가는 함수 추출에 따른 boilerplate(frontmatter, source, guard)와 신규 기능(brainstorming, 마이그레이션)에 의한 것이며, 각 파일은 80-200줄로 관리 가능한 크기.

---

## Changelog — Consensus Iteration 1

### Architect Review (REVISE)
- ✅ R-Arch-1: P2 wording (`ios-* 약결합 모델 준수`) 정정 → "ios-* 하이픈+독립 구조 기반, lib 결합 추가"로 수정
- ✅ R-Arch-2: `_classify_screen` 머지 결정 명시 (L571 authoritative + L97-only 패턴 병합)
- ✅ R-Arch-3: 마이그레이션 backup 타임스탬프 추가 (`bak.$(date +%s)`)
- ✅ R-Arch-4: ADR Consequences에 correlated failure 명시 + guard 에러 메시지 구체화
- ⏳ R-Arch-5: 8 스킬 description 키워드 disambiguation — Follow-ups에 등재 (구현 단계 검토)

### Critic Review (REJECT → 4 required revisions)
- ✅ R1 (CRITICAL): P2 false claim 수정 (Architect R-Arch-1과 동일)
- ✅ R2 (MAJOR): F9, F10 신규 추가 (brainstorming, council 테스트)
- ✅ R3 (MAJOR): A1 `_classify_screen` 머지 정책 명시 (Architect R-Arch-2와 동일)
- ✅ R4 (MINOR): A2 backup 타임스탬프 (Architect R-Arch-3과 동일)

### Improvements Applied
- ✅ F11 End-to-End 회귀 테스트 추가 (Critic MINOR-1 권고)
- ✅ ADR Alternatives에 ouroboros plugin manifest 옵션 명시 + invalidation 사유
- ✅ ADR Follow-ups에 `agy` alias 지원, 키워드 disambiguation, 화면 캡처 보강 등재

### Open Items (구현 단계 결정)
- Install mechanism (`~/.claude/skills/` 동기화 방식: copy / symlink / 스크립트) — `open-questions.md` 참조
- Auto-trigger 키워드가 8 서브스킬 간 충돌하는지 첫 검증 단계에서 확인 (A5 + R-Arch-5)

### Final Verdict
- Architect 5 revisions → 4 적용 + 1 follow-up
- Critic 4 required revisions → 4 모두 적용
- 추가 개선 사항 → 3개 적용
- **Status**: 합의 1라운드로 수렴, 재평가 생략 가능 (모든 critical/major fix 적용 완료)
