# AI Working Framework — Playbook: Solo Mode (1인 프로젝트)

> **Type:** Playbook (Framework 확장)
> **Base:** AI Working Framework v1.0
> **적용 대상:** 1인이 수행하는 소규모 프로젝트

> 이 Playbook은 Framework를 **바꾸지 않는다.** STEP·원칙은 그대로 두고, **적용 무게만 조정**한다.
> Framework = 공통 기준(고정) / Playbook = 적용 방식(가변). (Framework Chapter 1.1)

---

## 1. 왜 Solo Mode가 필요한가

Framework는 **역할 분리**(만드는 사람 ≠ 검토하는 사람)를 전제로 설계되었다.
1인 프로젝트에서는 이 전제가 성립하지 않으므로, 두 가지가 달라진다.

| 구분 | 팀 프로젝트 | 1인 프로젝트 |
| --- | --- | --- |
| Human Review | 타인의 검토 | AI 질문을 통한 **자기 점검** |
| AI의 위치 | 보조 도구 | **팀원 겸 리뷰어** |

> 핵심 원칙: **STEP은 지키되, 산출물은 가볍게.**
> 혼자 일할수록 단계 생략(현황 없이 개발, 문제 정의 없이 요구사항)이 잦고, 그것이 재작업으로 돌아온다. STEP 순서는 1인일수록 지켜야 할 안전장치다.

---

## 2. 무엇을 지키고 무엇을 접는가

| 요소 | Framework (Full) | Solo Mode |
| --- | --- | --- |
| STEP 순서 (0~11) | 전부 수행 | **유지** (건너뛰지 않기) |
| Deliverable | STEP마다 공식 문서 | 핵심 STEP만 문서, 나머지는 메모 수준 |
| AI Interview | 필요 시 | **적극 활용** (팀원 대체) |
| Human Review | 타인 검토 | AI 질문으로 자기 점검 |
| AI Metadata | 전부 기록 | 생략 가능 |
| Done Criteria | 전부 체크 | 핵심 기준만 |
| 되돌림 루프 (Rework/Return) | 표준 | **그대로 유용** |

> 지키는 것: **STEP 순서, Deliverable→Input 사슬, 되돌림 루프, AI Interview.**
> 접는 것: **문서 형식의 무게(공식 문서·메타데이터·전체 Done Criteria).**

---

## 3. STEP 접기 (프로젝트 규모별)

작은 프로젝트일수록 STEP을 합치거나 생략할 수 있다. 단, **순서는 바꾸지 않는다.**

| STEP | Solo 권장 |
| --- | --- |
| STEP 0 Initialization | 간단히 (목표·범위 메모 1장) |
| STEP 1 현황 분석 | 유지 (생략 시 재작업 위험 큼) |
| STEP 2 문제 정의 | 유지 (혼자일수록 놓치기 쉬움) |
| STEP 3 요구사항 | 유지 |
| STEP 4 업무 설계 | STEP 5와 통합 가능 |
| STEP 5 UI/UX | STEP 4와 통합 가능 |
| STEP 6 기술 설계 | 규모에 따라 경량화 |
| STEP 7 개발 | 유지 |
| STEP 8 테스트 | 유지 (셀프 리뷰로 대체하지 말 것) |
| STEP 9 배포 | 유지 |
| STEP 10 운영 | 규모에 따라 경량화 |
| STEP 11 회고 | 생략 가능 (원래 Optional) |

> **접지 말 것:** STEP 1·2(현황·문제)와 STEP 8(테스트). 이 셋은 혼자일 때 가장 생략하기 쉽지만, 생략 비용이 가장 크다.

---

## 4. AI를 팀원처럼 쓰는 법

1인 프로젝트에서 AI Interview는 **없는 팀원을 대신하는 장치**다. 각 STEP의 질문을 형식이 아니라 실제 점검으로 쓴다.

- **초안은 AI, 판단은 나.** AI에게 STEP별 Deliverable 초안을 만들게 하고, 나는 AI가 던지는 Interview 질문에 답하며 내 생각을 검증한다.
- **자기 점검 = AI 질문 답하기.** "이 문제의 근본 원인은?" "성공을 어떻게 측정하나?"에 스스로 막히면, 그 STEP은 아직 완료가 아니다. 이것이 1인 프로젝트의 Human Review다.
- **되돌림은 그대로.** 테스트에서 문제가 나오면 개발로 되돌아간다. 혼자여도 이 루프는 유지한다 — 오히려 혼자라 놓친 것을 잡아주는 안전장치다.

---

## 5. Solo Mode 최소 체크리스트

프로젝트를 시작할 때 이것만 지켜도 Framework의 핵심은 살아 있다.

- [ ] STEP 순서를 건너뛰지 않았다 (합치는 것은 허용, 순서 바꾸기·생략은 지양).
- [ ] STEP 1·2(현황·문제)를 실제로 수행했다.
- [ ] 각 STEP에서 AI Interview 질문에 스스로 답해봤다.
- [ ] 각 STEP의 결과가 다음 STEP의 입력으로 이어진다.
- [ ] STEP 8(테스트)을 셀프 리뷰로 대충 넘기지 않았다.
- [ ] 문제 발생 시 이전 STEP으로 되돌아가는 것을 회피하지 않았다.

---

## 6. 이 Playbook의 의미

Solo Mode는 Framework/Playbook 구조의 **첫 실물 예시**다.

| 구분 | 대상 | 성격 |
| --- | --- | --- |
| Framework | STEP·원칙·표준 | 팀이든 1인이든 공통 (고정) |
| Playbook (Solo) | 적용 무게 조정 | 1인 프로젝트용 (가변) |

> 같은 방식으로 "대규모 프로젝트 Playbook", "특정 조직 Playbook", "모델별 Prompt Playbook"을 만들 수 있다.
> Framework는 하나, Playbook은 여럿이다.
