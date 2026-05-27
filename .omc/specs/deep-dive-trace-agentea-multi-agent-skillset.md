# Deep Dive Trace: agentea-multi-agent-skillset-redesign

## Observed Result
사용자는 현재 단일 SKILL.md(755줄)로 구성된 agentea를 다음과 같이 재설계하고자 함:
1. 지원 에이전트에 **antigravity** 추가 (현재: codex, grok)
2. agentea 실행 시 **모드 선택** (auto / manual) + **에이전트 조합 선택** 인터랙션
3. 단일 스킬을 **다수의 서브 스킬**로 분해:
   - `/agentea` — ON (초기화)
   - `/agentea-status` — 현재 STATUS 분리
   - `/agentea-ask` — manual 모드에서 특정 에이전트에게 직접 요청
   - `/agentea-review` — manual 모드에서 직접 리뷰 트리거
   - `/agentea-clear` — `.agentea/` 폴더 초기화
   - `/agentea-off` — pane 정리 + 비활성화

## Ranked Hypotheses

| Rank | Hypothesis | Confidence | Evidence Strength | Why it leads |
|------|------------|------------|-------------------|--------------|
| 1 | 멀티 스킬 분해 + 공유 헬퍼 추출 패턴이 ios-* 그룹 사례로 검증 가능 | **High** | Strong | Lane 3: 90+개 로컬 스킬 중 ios-*, plan-*, design-* 등 다수의 하이픈-기반 multi-skill 그룹 실재. ios-*는 약결합(자연어 참조 + 외부 state) 모델 확립됨. agentea도 동일 패턴 따르면 됨. |
| 2 | antigravity-cli는 codex/grok과 유사한 통합 가능성 (TUI + OAuth) | **Medium-High** | Strong (간접) | Lane 2: Homebrew cask `antigravity-cli` v1.0.1 확정 (`agy` 바이너리), 브라우저 OAuth + device-code 폴백 + API 키 폴백 + TUI with `>` prompt 모두 확인. 단 공식 docs JS-only 페이지로 first-run 시퀀스 1차 출처 미확보. |
| 3 | 공유 헬퍼는 `lib/common.sh` 추출 후 `source`로 해결 (Bash 함수 공유 불가 문제) | **High** | Strong | Lane 1: `_load_state`, `_send_codex`, `_classify_screen`, `_wait_file` 등 명확한 공유 코드 식별. `_classify_screen`은 이미 SKILL.md 내 2회 중복 정의 — 분리 시그널. |

## Evidence Summary by Hypothesis

- **Hypothesis 1 (분해 가능성)**: 
  - `ios-{fix,clean,design-review,qa,sync}` (5개): 독립 SKILL.md, 자연어 상호 참조, 외부 StateServer 공유. 코드 공유 없음. 사용자가 슬래시 커맨드로 직접 invoke.
  - `plan-{ceo-review,eng-review,design-review,devex-review,tune}` (5개): 동일 패턴.
  - `design-{html,review,shotgun,consultation}` (4개): 동일 패턴.
  - **로컬 스킬은 콜론(`:`) 사용 불가** — `parent:child`는 플러그인 marketplace 전용 (ouroboros 사례). 사용자 요청의 `/agentea-*` 하이픈이 정확.

- **Hypothesis 2 (antigravity 통합)**:
  - `brew info antigravity-cli` 확정: v1.0.1, `antigravity → agy` 바이너리, 30일 설치 3,136건.
  - 인증 패턴 (커뮤니티 출처): OAuth 브라우저 자동 오픈 + Keychain 캐싱 (codex 동일), 헤드리스 환경에서 device-code URL 출력 (grok 유사), `ANTIGRAVITY_API_KEY` 폴백.
  - TUI 구조: scrollable conversation pane, `>` prompt, status bar — codex/grok과 동형.
  - **Gemini CLI sunset(2026-06-18)의 공식 후속** — 통합 가치 ↑.

- **Hypothesis 3 (공유 헬퍼 분리)**:
  - `_load_state()` (L294-300), `_send_codex/_send_grok/_broadcast` (L302-315), `_classify_screen()` (L97-106 + L571-583 **중복**), `_wait_file()` (L339-345): 명확한 공유 함수.
  - 각 서브 스킬은 독립 bash 프로세스로 실행될 가능성 높음 → 함수 정의를 파일로 추출 후 `source` 필수.
  - 상태 파일 `~/.claude/agentea-state.json`은 단일 사용자/단일 세션 가정 하 read-modify-write 락 불필요 (Lane 3 확인).

## Evidence Against / Missing Evidence

- **Hypothesis 1**: 
  - 반증 없음.
  - 빠진 증거: 사용자 요청 6개 서브 스킬에 **`council` 누락**, **`broadcast` 분류 모호** (Lane 3).

- **Hypothesis 2**:
  - 공식 docs(`antigravity.google/docs/cli-using`)가 WebFetch에서 빈 본문 (JS 렌더링 필요) — 1차 출처 미확보.
  - **first-run 인터럽트 순서/문구 미확인**: theme 선택? Gemini CLI 설정 import 제안? trust prompt 존재 여부?
  - WSL 인증 영속성 버그 존재 (포럼 리포트) — cmux 환경이 WSL이면 위험.
  - Desktop 앱과 PATH 충돌 가능성 (별도 cask 존재).

- **Hypothesis 3**:
  - 서브스킬 호출 시 환경변수 (`CMUX_SURFACE_ID` 등) 영속 여부 미검증.
  - JSON 동시 쓰기 보호 부재 — 사용자가 동시에 두 서브스킬 호출 시 corrupted state 가능 (저위험이지만).

## Per-Lane Critical Unknowns

- **Lane 1 (자산 분해)**: 서브스킬이 **독립 프로세스인지 같은 shell session인지** — 결정에 따라 `source` 전략이 달라짐. (Lane 1 직접 인용)
- **Lane 2 (antigravity)**: agy의 **first-run startup 시퀀스가 codex/grok 패턴과 정확히 어떻게 다른가** — 특히 "Gemini CLI 설정 import 제안" 같은 신규 인터럽트 단계 존재 여부. `_classify_screen`에 새 카테고리(`import_offer`) 필요할 수 있음.
- **Lane 3 (분해 컨벤션)**: 공통 헬퍼 함수를 **복사-붙여넣기(DRY 위반) vs `lib/common.sh` 추출 후 `source`** 중 어느 쪽을 택할지 — ios-* 그룹은 이 문제를 회피했지만 agentea는 회피 불가능.

## Rebuttal Round

- **Best rebuttal to leader (Hypothesis 1)**: Lane 1이 "고유 코드 vs 공유 코드 분리 가능"이라고 주장하지만, 만약 서브스킬이 매번 새 bash로 시작된다면 — 공유 함수는 매 호출마다 `source`해야 하고, 이는 ios-* 그룹에 존재하지 않는 패턴. 즉 "ios-* 모델 그대로 따라가면 됨"이 부분적으로만 사실.
- **Why leader held**: 그러나 `source ~/.claude/skills/agentea/lib/common.sh`는 표준 Bash 관용구라서 ios-* 모델을 한 줄로 보강하면 해결. 리더 가설 유지.

## Convergence / Separation Notes

- **수렴**: Lane 1 ("공유 코드 식별 가능") + Lane 3 ("ios-* 약결합 모델"): 같은 결론 — 공유 헬퍼는 `lib/common.sh`로 추출, 각 서브스킬은 `source` 후 자체 로직 실행.
- **수렴**: Lane 2 + Lane 3: 둘 다 "사용자가 직접 실행해서 확인 필요" 결정적 probe 제안. antigravity는 실제 화면 캡처, 분해 컨벤션은 사용자 의도 확정.
- **분기 유지**: Lane 2는 다른 lane들과 독립 영역 (외부 CLI 조사). 통합 시점에만 의존.

## Most Likely Explanation

사용자 요청은 **기술적으로 완전히 실현 가능**하며, ios-* 그룹의 약결합 멀티 스킬 모델 + `lib/common.sh` 공유 헬퍼 추출이 모범 답안. 단, 다음 3가지가 인터뷰에서 명확화 필요:

1. **antigravity 통합 범위**: 사용자 환경에 설치되어 있는가? 첫 화면을 실제로 캡처해서 `_classify_screen` 패턴을 확정할 수 있는가? 아니면 "스켈레톤만 만들고 사용자가 첫 실행 시 보완"으로 처리할 것인가?
2. **모드 게이팅의 정확한 의미**: "auto 모드"는 작업 완료 직후 자동 review 트리거인가? "manual"은 그게 꺼진 상태로 직접 명령만 받는 모드인가? 자동 트리거는 어떤 이벤트(SessionEnd hook? PostToolUse?)로 발동하는가?
3. **누락된 서브스킬 처리**: `council`은 `/agentea-council`로 분리할지, `/agentea-ask`에 흡수할지? `broadcast`는 `/agentea-ask all`로 통합할지, 별도 `/agentea-broadcast`로 둘지?

## Critical Unknown

**가장 결정적 단일 사실**: 사용자가 **antigravity-cli를 이미 설치했는지/사용 경험이 있는지**. 그 여부에 따라 통합 깊이가 결정됨:
- 설치 완료 + 경험 있음 → 실제 화면 캡처 가능 → 구체적 패턴 통합 가능
- 설치 안 됨 → 스켈레톤 + TODO 마커로 두고 향후 사용자가 첫 실행 시 보완

## Recommended Discriminating Probe

**Phase 4 인터뷰의 첫 번째 질문으로 이 4개를 한번에 묻기**:
1. antigravity-cli 설치 + 사용 경험 여부
2. auto/manual 모드의 정확한 의미 (자동 트리거 이벤트)
3. council 처리 방향
4. broadcast 처리 방향

이 4개로 critical unknown 3종이 모두 해소되며, 이후 인터뷰는 구현 디테일(파일 구조, 마이그레이션 전략)로 빠르게 수렴 가능.
