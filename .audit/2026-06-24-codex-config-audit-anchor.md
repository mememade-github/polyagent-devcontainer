# 정밀 감사 — Codex config WIP & 템플릿 전수 감사 (DAG)

> Frozen anchor (anchor-discipline P1). 사용자 dictation 외 AI 편집 금지.
> Task date: 2026-06-24 · Branch: main · 유일 tracked 변경: `.codex/config.toml`

---

## 0. Frozen anchor (verbatim)

**User thesis (verbatim):**
> `정밀 감사 보고 - 계획시 전수 감사 올바르게 되도록 DAG 계획 수립`

**Prior output (baseline to diff against):** 직전 턴의 "전체 수정 계획" 10단계 리스트
(선형 fix-list). 이 파일의 §3 gap matrix가 그 baseline ↔ 검증된 census 간 차이.

**Anchor elements (N=5) — primary-position 요구:**

| # | element (regex) | 위치 요구 |
|---|-----------------|-----------|
| E1 | `정밀\s*감사` (precision audit, not fix-list) | 산출물 프레이밍 |
| E2 | `전수` (census / 100% enumeration, not sample) | 커버리지 보증 노드 필수 |
| E3 | `올바르게` (correctness = 검증된 근거 + 분류) | 모든 finding에 file:line 근거 |
| E4 | `DAG` (의존성 구조, not linear list) | node/edge/topological layer |
| E5 | `계획시` (plan-time 보증) | 실행 전 게이트로 보증 |
| E6 | `당신은 감사만` — auditor-only (turn2 dictation) | R/실행·결정은 Codex 핸드오프; Claude는 finding+DAG만 |
| E7 | `전수` 확장 — vendor scope-membership 축 (turn2 dictation: `.cursor`) | 모든 top-level 벤더/툴 dir의 PROJECT.md 멤버십 검사 |

**Cycle 종료 조건:** anchor hit ≥ 80% AND 사용자 essence 승인(P4) AND
외부 cross-check(audit-discipline §4) 완료 AND commit-discipline 분할.

---

## 1. 프로토콜 자기점검 (P6) — 직전 턴

직전 10단계 plan에 적용되지 **않은** 프로토콜:
- P1 anchor-freeze 부재 · audit §1 negative-space 부재 · census enumeration 부재 ·
  DAG 구조 부재(선형) · single-vendor lens(Codex만) · 검증 없는 line# 상속.
- 드리프트 유형: **false-positive termination**(표본을 전수로 선언) +
  **quick-answer**(원인분석 없이 fix-list) + **auto-framing substitution**(감사→수정목록).

---

## 1b. CORRECTION — turn 2 (2026-06-24): scope error + 역할 정정

**(audit-discipline §1 end-clause)** 직전 감사의 negative-space(§3)에 **vendor/tool
scope-membership** 축이 covered도 excluded도 아닌 채 누락 → "전수" 주장이 그 축에서 과장.
사용자가 `.cursor`(PROJECT.md 정식 parity 미등재 벤더)를 외부 지적 → 이는 audit-discipline
§4가 예측한 **external cross-check가 self-audit의 scoping 맹점을 잡은** 사례. 신규 finding이
아니라 **scope error로 기록**. → 시정: A0 축 신설(§5) + 회귀 가드(R4).

**INTEGRITY 자기정정:** turn2에서 "karpathy-consistency-check.sh가 multi-variant(16/16/8)
카운트로 stale·실패"라는 가설 → **실행([26])하니 LEAF 모드 2/2/1 PASS** → 가설 기각, **F20 철회**.
(실행 전 단언했으면 unverified-claim 죄를 반복할 뻔.)

**역할 정정(E6):** Claude=감사 전용. config.toml·삭제·.cursor 처분 등 **모든 실행·결정은
Codex 핸드오프**. 본 문서 = finding + disposition + DAG 산출에 한정.

---

## 2. Census ground-truth (검증 완료)

| 사실 | 근거 | 직전 plan과 차이 |
|------|------|------------------|
| config.toml staged diff = **5개 추가 블록** | `git diff` L22-35 | plan은 2개(model/effort)만 언급 |
| `[projects."/workspaces"] trust_level="trusted"` | config.toml:28-29 | **누락** (보안 관련) |
| `[tui.model_availability_nux]` | config.toml:31-32 | **누락** (런타임 state 누수) |
| `[notice.model_migrations]` | config.toml:34-35 | **누락** (런타임 state 누수) |
| 누수 경로 = `~/.codex/config.toml` **심링크** → tracked 파일 | setup-env.sh:89-95 | **근본원인 미발견** |
| line# 부정확: 변경은 :22부터(:20=sandbox 불변) | config.toml | plan "config.toml:20" 오류 |
| `git-status.sh`/`completion-checker.sh`/`karpathy-*.sh` = 644 | `git ls-files -s` | 정확 |
| 직접경로 실행자 있음 → git-status(SKILL:24), completion-checker(SKILL:26) | grep | plan은 3개 일괄; 실제 2개만 contract 위반 |
| `karpathy-consistency-check.sh` 직접경로 호출자 **없음**(bash만) | grep | plan 오분류(불필요) |
| SKILL 직접exec 행은 :24 (plan "SKILL:15" 오류) | status/SKILL.md:24 | line# 오류 |
| `.serena/` 비어있지 않음(cache,memories) + **gitignored** | ls, check-ignore | plan "비어있음" 오류 |
| `.gitlab-ci.yml` present-but-**IGNORED**(not tracked) | check-ignore | 정상(ec39234 의도대로) — CLEAN |
| `variants/datascience/` = untracked, `.env`만 보유 | census | 삭제해도 repo 무영향(로컬 디스크) |
| Claude/Codex 훅 secret 패턴 동일, 둘 다 `sk-`류 없음 | 두 훅 grep | 향상은 **양쪽** 수정 필요 |
| push baseline: Codex 무조건/Claude 조건부 기록, **둘 다 push 전(PreToolUse)** | 두 훅 | 설계상 성공여부 불가지 |
| **verify-template.sh가 exec-bit·config hygiene 미검사** | verify-template.sh | gate가 결함을 통과시킴(§2 회귀공백) |
| cross-doc 카운트(2/4/5) 일관 | grep | CLEAN (단, 문서 수정 후 재검 필요) |

---

## 3. Negative-space 선언 (audit-discipline §1)

이 감사가 **다루지 않는** 축 (제외 사유):
- **런타임 동작 실측** — 컨테이너 빌드/실행 후 동작은 미실측(정적 감사). `claude/codex --version`, 실제 push 동작은 V-phase 실행 시점에만 확인.
- **상류(upstream) 동기화 무결성** — GitHub origin과 byte 비교 미수행(로컬 트리만).
- **MCP/외부 도구 신뢰성** — Serena 등 외부 MCP의 보안성은 범위 외(REFERENCE.md privilege-boundary 위임).
- **성능/비용 실측** — `xhigh`/`gpt-5.5`의 실제 토큰·지연 비용은 정책 판단으로만 다루고 벤치 미수행.
- **CI 파이프라인 실행** — `.gitlab-ci.yml`은 ignored이므로 파이프라인 동작 미검증.

**(turn2 추가 — 이제 COVERED, 더 이상 제외 아님):** vendor/tool **scope-membership**
= A0 축으로 승격(§5). 이전의 무선언 누락은 §1b에 scope error로 기록됨(.cursor가 그 누출).

이 중 하나라도 후속에서 문제로 드러나면 → **scope error로 기록**(신규 finding 아님).

---

## 4. 정밀 감사 보고 — 축별 분류

분류: **DEFECT**(결함) · **INTENTIONAL**(문서화된 의도) · **ENH**(향상) · **DECISION**(사용자 결정) · **CLEAN**.

| ID | 축 | 발견 | 근거 | 분류 |
|----|----|------|------|------|
| F1 | hygiene | config.toml에 Codex 런타임 state 2블록 누수(nux/migrations) | config.toml:31-35 | **DEFECT** |
| F2 | hygiene/root | 누수 경로 = ~/.codex 심링크 → tracked. 라인 삭제만으론 재발 | setup-env.sh:89-95 | **DEFECT(근본)** |
| F3 | security | `trust_level="trusted"` staged — 승인 우회 의미, 의도 불명 | config.toml:28-29 | **DECISION** |
| F4 | wip | model=gpt-5.5 / effort=xhigh staged — 채택? 실험? | config.toml:22-23 | **DECISION** |
| F5 | exec-contract | git-status.sh 644인데 SKILL:24가 직접경로 실행 | status/SKILL.md:24 | **DEFECT** |
| F6 | exec-contract | completion-checker.sh 644인데 verify/SKILL:26 직접경로 | verify/SKILL.md:26 | **DEFECT** |
| F7 | exec-contract | karpathy-*.sh 644이나 직접경로 호출자 없음(bash만) | grep | **CLEAN**(plan 오분류) |
| F8 | (fork) | F5/F6 수정 방향: chmod+x vs SKILL을 `bash <path>`로. 스크립트 self-doc은 `bash` 권장 | git-status.sh:9 | **DECISION** |
| F9 | parity/sec | secret 패턴에 `sk-`/`sk-ant-`/OpenAI 키 부재 — 양쪽 훅 수정 필요 | 두 pre-commit | **ENH** |
| F10 | sec/design | push baseline이 push 전에 갱신(PreToolUse) → 실패 push도 기준 변경. 설계 제약 | 두 pre-push | **DECISION** |
| F11 | gate-gap | verify-template.sh가 exec-bit·config hygiene 미검사 → 결함 무통과 | verify-template.sh | **DEFECT** |
| F12 | supply | Codex unpinned 설치 | Dockerfile:99 | **INTENTIONAL**(REFERENCE.md rolling) |
| F13 | supply | setup-env가 claude만 update, codex update 없음 | setup-env.sh:63-95 | **ENH**(opt) |
| F14 | cleanup | variants/datascience/ stale(untracked, .env만) | census | **DECISION**(삭제) |
| F15 | cleanup | .serena/ ignored auto-state(비어있지 않음) | census | **DECISION**(opt 삭제) |
| F16 | doc | 수정 결과 반영 위해 README/PROJECT/REFERENCE/AGENTS 갱신 + 카운트 회귀검사 | — | derived |
| F17 | cross-doc | 2/4/5 카운트 현재 일관 | grep | **CLEAN**(수정 후 재검) |
| F18 | trust-model | "isolated/sandbox" 표현 vs docker.sock 신뢰모델 | REFERENCE.md privilege-boundary | **CLEAN**(이미 정정됨) |
| F19 | scope(A0) | `.cursor/` = README/CLAUDE는 'config-only mirror' 벤더로 명시하나 PROJECT.md 정식 parity 표·tech-stack엔 **부재** → 문서 불일치 | README:3,5,7 / CLAUDE:5,32 vs PROJECT.md:9,19,24-27 | **DEFECT** |
| F20 | ~~oracle~~ | ~~karpathy oracle multi-variant 카운트로 stale~~ → 실행시 LEAF 2/2/1 PASS | [26] | **철회 WITHDRAWN** |
| F21 | rebrand | variants/datascience stale + F19 = single-variant 리브랜드(2794d65→2c6464a) 미완 잔재 cluster | git log | **DEFECT(cluster)** |
| F22 | scope(A0) | `.vscode/`(launch.json,settings.json) tracked이나 PROJECT.md 미선언 — 에디터 설정(경미) | [25] | **NOTE** |

---

## 5. DAG — node / edge / layer

**노드 표** (type: F=freeze, A=audit, T=triage, G=gate, R=remediate, V=verify, C=commit)

| ID | type | 내용 | depends-on | 상태 |
|----|------|------|-----------|------|
| N0 | F | anchor-freeze(이 파일) | — | DONE |
| N1 | F | negative-space 선언(§3) | — | DONE |
| N2 | F | 전수 census matrix(§2) | — | DONE |
| **A0** | **A** | **scope-membership**: top-level 벤더/툴 dir ↔ PROJECT.md parity (멤버십 먼저, 내용 나중) | N2 | **DONE(F19/F22)** |
| A1 | A | cross-doc 일관(카운트/버전/명령 + **벤더-set/README↔PROJECT 정합**) | N2,A0 | DONE(F17/F19) |
| A2 | A | entry-point + 벤더 parity | N2 | DONE(F9) |
| A3 | A | supply-chain 버전축 | N2 | DONE(F12/13) |
| A4 | A | trust-model 표현/`trust_level` | N2 | DONE(F3/F18) |
| A5 | A | tracked/ignored hygiene + 누수 근본원인 | N2 | DONE(F1/F2) |
| A6 | A | exec-bit / invocation-contract | N2 | DONE(F5-8) |
| A7 | A | mirror fidelity(.claude↔.agents, karpathy) | N2 | partial |
| A8 | A | security(secret패턴/push baseline) | N2 | DONE(F9/F10) |
| A9 | A | governance self-consistency + gate-gap | N2 | DONE(F11) |
| A10| A | WIP/working-tree intent(config diff) | N2 | DONE(F3/F4) |
| T1 | T | finding 통합·분류(§4) | A0..A10 | DONE |
| G1 | G | **GATE: config.toml intent 결정(Codex)** | A5,A10,T1 | **대기** |
| G2 | G | **GATE: 삭제(Codex 실행). variants/datascience=user 승인됨, .serena=유지** | A5,T1 | variants 승인 |
| G3 | G | **GATE: 외부 cross-check §4** — turn2에서 user가 .cursor로 부분 수행(맹점 적중) | T1 | 부분 |
| G4 | G | **GATE: `.cursor` 처분(Codex): reconcile(PROJECT.md에 config-only-mirror tier 추가) vs remove(.cursor+참조+oracle cursor-branch)** | A0,T1 | **대기** |
| R1 | R | .claude/ 그라운드트루스 결함수정(exec-contract F5/F6) | T1 | — |
| R2 | R | config.toml 정리(런타임 state strip + intent 반영) | G1 | — |
| R3 | R | 훅 parity 향상(.claude+.codex secret패턴; push설계) | T1,F10결정 | — |
| R4 | R | verify-template.sh 확장(exec-bit + config hygiene + **A0 멤버십 가드**: tracked 벤더 dir == PROJECT.md parity ∪ 화이트리스트{.devcontainer,.vscode,scripts}) | T1 | — |
| R5 | R | 로컬 삭제(variants/datascience만; .serena 유지) | G2 | user 승인 |
| R6 | R | **MIRROR 재싱크(sync-agents-mirror.sh)** | R1,R3,R4 | — |
| R7 | R | 문서 정합(README/PROJECT/REFERENCE/AGENTS/CLAUDE) + **.cursor 처분 반영**(G4) | R1,R2,R3,R4,G4 | — |
| V1 | V | verify-template.sh(확장본) | R1..R7 | — |
| V2 | V | sync --dry == clean | R6 | — |
| V3 | V | karpathy-consistency-check.sh | R1,R7 | — |
| V4 | V | bash -n(변경 스크립트) | R1,R3,R4 | — |
| V5 | V | census 재diff: 신규 tracked 누수 0(특히 config) | R2 | — |
| V6 | V | anchor gap-matrix ≥80% + cross-doc 카운트 회귀검사 | R7,N0 | — |
| V7 | V | 외부 cross-check sign-off(G3 해소) | V1..V6 | — |
| C1-6| C | commit-discipline 분할(config/exec/hook/verify-tmpl/docs/del) | V7 | — |

> **역할 경계(E6):** A0/A1..A10 + T1 + §1b = **Claude(감사)** 산출. G/R/V/C = **Codex 핸드오프**(결정·실행). 이 문서가 핸드오프 패키지.

**Topological layer**

```
L0 FREEZE/ENUM     L1 DISCOVER(∥)      L2 TRIAGE          L3 REMEDIATE          L4 VERIFY        L5 COMMIT
 N0 ┐               A1 cross-doc        T1 classify        R1 exec-fix ┐         V1 verify-tmpl   C1 config
 N1 ┼─ N2 census ─► A2 parity      ┐                   ┌─ R2 config(G1) │       V2 sync --dry    C2 exec
    ┘               A3 supply      │   ┌─ G1 config ───┤  R3 hook-parity ┼─ R6 ─►V3 karpathy      C3 hook
                    A4 trust-model ┼─► ├─ G2 deletion ─┤  R4 verify-ext  │ sync  V4 bash -n       C4 verify
                    A5 hygiene*    │   └─ G3 x-check ─┐ └─ R5 del(G2)     │       V5 census-rediff C5 docs
                    A6 exec*       │                  │     R7 docs ──────┘       V6 anchor+count  C6 del
                    A7 mirror      │                  │                           V7 x-check ◄── G3
                    A8 security    │                  └──────────────────────────────────────────┘
                    A9 governance  │   (* = plan 구성 중 이미 실행)
                    A10 wip*       ┘
```

**선형 plan이 놓친 critical edge (DAG에서만 표현됨)**
1. `G1 → R2`: config intent 결정 전 config.toml 편집 금지(차단).
2. `R1,R3,R4 → R6`: 미러 싱크는 **모든** .claude 편집 후 barrier. (선형 plan은 step9였으나 각 편집 의존 미인코딩.)
3. `R1,R2,R3,R4 → R7`: 문서는 수정 **후**(현실 반영). 역순이면 doc-drift.
4. `R4 → V1`: verify-template 확장이 **선행**되어야 V1이 결함을 잡음. 미확장 시 V1이 **거짓 통과**(F11). ← 선형 plan step10의 치명 결함.
5. `R7,N0 → V6`: 카운트 회귀검사(audit §2 adjacent-path) — 문서수정이 2/4/5 드리프트 유발 방지.
6. `V7 ← G3`: 외부 cross-check 미해소 시 commit 차단(audit §4, citable output).

---

## 6. 게이트(실행 전 사용자 결정 필요)

- **G1 config.toml intent** — (a) model/effort 채택? (b) trust_level 유지? (c) 런타임 state(nux/migrations) strip + 재발방지(F2). 셋은 독립 결정.
- **G2 삭제** — variants/datascience(+opt .serena). 대안(destructive-ops §1): 둘 다 ignored/untracked → repo 무영향, "유지"도 유효. narrower = .trash 이동 or 방치.
- **F8 exec-fix 방향** — chmod+x vs SKILL `bash <path>`. 권장: 스크립트 self-doc(`bash …`)에 맞춰 SKILL 측 정정(R1).
- **F10 push baseline** — PreToolUse 설계상 성공여부 불가지. 옵션: PostToolUse 이동 / 기록보류 / 현상유지.

*Last updated: 2026-06-24*
