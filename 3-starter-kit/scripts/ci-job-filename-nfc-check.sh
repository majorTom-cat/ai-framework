#!/usr/bin/env bash
# 파일명 유니코드 정규화(NFC/NFD) 충돌 검사 — 차단형 (CI 묶음 잡 `repo-guards`)
# 종전 `.gitlab-ci.yml` `filename-nfc-check` 잡의 본문을 그대로 옮겼다.
# 기획자 웹 업로드(대개 NFC)와 맥 로컬 git add(NFD)가 **같은 표시명의 파일을 두 벌** 만든 실사고 방지(bnsone #85 — 이틀 잠복,
# 눈·grep·기존 CI 전부 못 잡음: 화면엔 한 파일로 보이고 grep 패턴은 한쪽 인코딩만 친다). 검사는 체크아웃 트리 전수.
# 차단은 "정규화하면 같은 경로가 되는 실물 두 벌"만 — 이 겹침은 항상 진짜 중복이라 오탐이 없다.
#   NFD 단독 존재(겹침 없음)는 경고만 낸다 — 맥 git 설정에 따라 정상 작업에서도 나올 수 있어 차단하면 오탐.
# 필요: python3
# `set -eo pipefail` — 러너가 인라인 스크립트에 걸던 설정이다. 파일로 옮기면 따라오지 않아 여기서 건다.
set -eo pipefail
python3 - <<'PY'
import os, sys, unicodedata
seen, dups, nfd = {}, [], []
for root, dirs, files in os.walk('.'):
    dirs[:] = [d for d in dirs if d != '.git']
    for f in files:
        p = os.path.relpath(os.path.join(root, f), '.')
        key = unicodedata.normalize('NFC', p)
        if p != key:
            nfd.append(p)
        if key in seen and seen[key] != p:
            dups.append((seen[key], p))
        else:
            seen[key] = p
if nfd and not dups:
    print(f"주의: NFD 인코딩 파일명 {len(nfd)}건(겹침 없음 — 통과). 맥에서 git config core.precomposeunicode true 권장:")
    for p in nfd[:10]: print("  -", p)
if dups:
    print("⛔ 같은 표시명의 파일이 두 벌 있습니다 — 유니코드 정규화(NFC/NFD) 충돌:")
    for a, b in dups:
        print(f"  · {a!r} ↔ {b!r}  (화면·grep에는 하나로 보입니다)")
    print("고치기: 두 벌의 내용을 대조해 최신 쪽만 남기고, 남길 파일 이름을 NFC로 통일(git mv). 경위는 bnsone #85 참조.")
    sys.exit(1)
print(f"파일명 정규화 충돌 0건 (검사 {len(seen)}개)")
PY
