#!/usr/bin/env python3
"""«쌓이는 파일»을 통째로 갈아치우기 전에, 사라지는 항목이 있는지 기계가 막는다.

왜: GitLab API `POST repository/commits` 의 `update` 는 **병합이 아니라 갈아치우기**다.
    받아 둔 시점과 커밋 시점 사이에 남이 넣은 줄은 그대로 사라진다.
★2026-09-10 실사고: 이 대조를 «사람이 눈으로» 하게 했더니 실패했다 — 스크립트가
  「내 사본에 없는 main 줄 30개」라고 찍었는데, 내가 고친 줄이 29개인 것을 대조하지 않고
  «내가 고친 줄이면 정상»이라는 안내문만 보고 넘겼다. 남의 줄 하나가 그대로 지워졌다
  (다른 세션이 나중에 복구). ⇒ **숫자를 찍는 것으로는 부족하다. 다르면 멈춰야 한다.**

무엇을 보나: `^YYYY-MM-DD` 로 시작하는 «항목 줄»이 기준(before)에 있는데 새 판(after)에
  ①그대로 없고 ②앞 80자로 시작하는 줄도 없으면 = **사라진 항목**으로 보고 exit 1.
  (②가 있으면 «내가 그 줄을 고친 것»이다 — 뒤에 덧붙이는 형태가 이 파일의 규약이다.)
보조 파일로 «옮긴» 경우를 위해 `--moved-to <파일>` 을 주면 거기에 있는 항목은 통과시킨다.

사용: python3 check-append-only.py <기준파일> <새판파일> [--moved-to <보관파일>]
"""
import sys, re, os

args = [a for a in sys.argv[1:]]
moved = None
if "--moved-to" in args:
    i = args.index("--moved-to")
    moved = args[i + 1]
    del args[i:i + 2]
if len(args) != 2:
    print(__doc__)
    sys.exit(2)
before, after = args

entry = re.compile(r"^\d{4}-\d{2}-\d{2}")
def entries(p):
    if not p or not os.path.exists(p):
        return []
    return [l.rstrip("\n") for l in open(p, encoding="utf-8") if entry.match(l)]

b, a = entries(before), entries(after)
m = entries(moved)
a_set, m_set = set(a), set(m)

lost = []
for line in b:
    if line in a_set or line in m_set:
        continue
    head = line[:80]
    if any(x.startswith(head) for x in a) or any(x.startswith(head) for x in m):
        continue          # 내가 그 줄을 고친 것(뒤에 덧붙임) — 정상
    lost.append(line)

msg = f"기준 {len(b)}항목 · 새 판 {len(a)}항목"
if moved:
    msg += f" · 보관 {len(m)}항목"
print(msg)
if lost:
    print(f"⛔ 사라지는 항목 {len(lost)}개 — 올리지 마라. 기준을 다시 받아 편집을 다시 얹어라.")
    for l in lost:
        print("   잃음:", l[:140])
    sys.exit(1)
print("사라지는 항목 없음 — 올려도 된다")
