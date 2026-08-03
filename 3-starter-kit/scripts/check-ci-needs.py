#!/usr/bin/env python3
# needs 함정 검사 — needs가 rules(changes)로 파이프라인에서 빠질 수 있는 잡을 가리키면
# 그 잡이 빠지는 순간 GitLab이 **파이프라인 생성 자체를 거부**한다(잡 0개 = 모든 게이트 무효).
# bnsone 2026-08-03 실사고: 문서만 바꾼 main 푸시 9회 전부 secret-scan·planner-guard 미실행.
# `glab ci lint`·`POST /ci/lint?dry_run=true` 둘 다 통과하므로(diff가 없으면 changes를 참으로 계산)
# 이 검사가 유일한 기계 방어다. 근거·재현: 파일럿 #90.
import sys

try:
    import yaml
except ImportError:
    # ★조용히 통과시키지 않는다 — 검사가 안 돈 걸 초록으로 보고하는 게 이 사고의 본질이었다.
    print("⛔ PyYAML이 없어 검사를 못 했다. CI: `apk add --no-cache py3-yaml` / 로컬: `pip install pyyaml`")
    sys.exit(1)


class Loose(yaml.SafeLoader):
    """!reference 등 GitLab 전용 태그를 만나도 죽지 않는다."""


Loose.add_multi_constructor("!", lambda loader, suffix, node: None)

RESERVED = {
    "stages", "variables", "default", "workflow", "include",
    "image", "services", "before_script", "after_script", "cache",
}

path = sys.argv[1] if len(sys.argv) > 1 else ".gitlab-ci.yml"
try:
    with open(path, encoding="utf-8") as f:
        doc = yaml.load(f, Loader=Loose)
except FileNotFoundError:
    print(f"{path} 없음 — 검사 생략")
    sys.exit(0)
except yaml.YAMLError as e:
    # 문법 자체가 깨진 건 glab ci lint의 몫이다. 여기서 중복 차단하지 않는다.
    print(f"YAML 파싱 실패 — 검사 생략(문법은 ci lint가 본다): {e}")
    sys.exit(0)

if not isinstance(doc, dict):
    sys.exit(0)

jobs = {
    k: v for k, v in doc.items()
    if isinstance(v, dict) and k not in RESERVED and not k.startswith(".")
}


def has_changes(job):
    """이 잡의 rules 중 하나라도 changes: 를 걸고 있으면 True (= 빠질 수 있다)."""
    rules = job.get("rules")
    if not isinstance(rules, list):
        return False
    return any(isinstance(r, dict) and "changes" in r for r in rules)


errors = []
for name, job in jobs.items():
    needs = job.get("needs")
    if needs is None:
        continue
    if "extends" in job:
        # extends는 여기서 해석하지 않는다 — 잘못된 단정보다 침묵이 낫다.
        print(f"ℹ {name}: extends 사용 — 이 잡은 건너뜀(수동 확인 필요)")
        continue
    if not isinstance(needs, list):
        needs = [needs]
    for n in needs:
        if isinstance(n, str):
            target_name, optional = n, False
        elif isinstance(n, dict) and "job" in n:
            target_name, optional = n["job"], bool(n.get("optional", False))
        else:
            continue  # needs: [{pipeline: ...}] 등 잡이 아닌 형태
        if optional:
            continue
        target = jobs.get(target_name)
        if target is None:
            errors.append(
                f"{name} → needs '{target_name}': 그런 잡이 없다. "
                f"파이프라인 생성이 거부된다."
            )
        elif has_changes(target) and not has_changes(job):
            errors.append(
                f"{name} → needs '{target_name}': '{target_name}'은 rules의 changes로 "
                f"빠질 수 있는데 '{name}'은 안 빠진다. "
                f"→ needs를 `- job: {target_name}` + `optional: true` 로 바꿔라."
            )

if errors:
    print("⛔ needs 함정 — 이 상태로 두면 파이프라인이 통째로 안 만들어지는 커밋이 생긴다:")
    for e in errors:
        print(f"  - {e}")
    print("  (왜 lint로는 안 잡히나: diff가 없으면 changes가 참으로 계산되어 needs가 충족돼 보인다)")
    sys.exit(1)

print(f"✓ needs 함정 없음 (검사한 잡 {len(jobs)}개)")
