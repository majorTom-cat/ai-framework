#!/usr/bin/env python3
"""«쌓이는 파일»을 통째로 갈아치우기 전에, 사라지는 항목이 있는지 기계가 막는다.

왜: GitLab API `POST repository/commits` 의 `update` 는 **병합이 아니라 갈아치우기**다.
    받아 둔 시점과 커밋 시점 사이에 남이 넣은 줄은 그대로 사라진다.
★2026-09-10 실사고: 이 대조를 «사람이 눈으로» 하게 했더니 실패했다 — 스크립트가
  「내 사본에 없는 main 줄 30개」라고 찍었는데, 내가 고친 줄이 29개인 것을 대조하지 않고
  «내가 고친 줄이면 정상»이라는 안내문만 보고 넘겼다. 남의 줄 하나가 그대로 지워졌다
  (다른 세션이 나중에 복구). ⇒ **숫자를 찍는 것으로는 부족하다. 다르면 멈춰야 한다.**

무엇을 보나: `^YYYY-MM-DD` 로 시작하는 «항목 줄»이 기준(before)에 있는데
  새 판(after)에서도 보관 파일에서도 «짝»을 못 찾으면 = **사라진 항목**으로 보고 exit 1.
  짝짓기는 세 단계다: ①글자 그대로 같음 ②한쪽이 다른 쪽의 앞 80자로 시작(뒤에 덧붙였거나 뒤를 지웠다)
  ③같은 날짜 + 닮음 0.7 이상(**줄 앞머리를 고친 경우** — ②가 못 잡는 자리다).
★**짝은 «하나에 하나»로 소비한다.** 옛 판은 `any(...)` 라 한 줄이 여러 줄의 짝 노릇을 해서,
  닮은 두 줄 중 하나를 지워도 통과했다. 이제 짝지어진 줄은 후보에서 빠진다.
★2026-09-10 실측(#268): ③이 없어 **«줄 앞머리의 인용을 요지로 바꾸는» 정상 편집이 ⛔ 로 찍혔다**
  — 거짓 ⛔ 는 사람이 ⛔ 를 안고 올리게 만든다(실제로 그렇게 올라갔다).
보조 파일로 «옮긴» 경우를 위해 `--moved-to <파일>` 을 주면 거기에 있는 항목은 통과시킨다.

사용: python3 check-append-only.py <기준파일> <새판파일> [--moved-to <보관파일>]
"""
import sys, re, os, difflib

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

pool = list(a) + list(m)          # 짝 후보 — 짝지어진 것은 빼면서 쓴다(하나에 하나)
lost, edited = [], []

def take(line):
    """line 의 짝을 pool 에서 찾아 «소비»한다. 찾으면 (종류, 짝) 아니면 None."""
    if line in pool:
        pool.remove(line); return ("같음", line)
    head = line[:80]
    for x in pool:                                   # 뒤에 덧붙였거나 뒤를 지웠다
        if x.startswith(head) or line.startswith(x[:80]):
            pool.remove(x); return ("고침", x)
    day, best, score = line[:10], None, 0.0          # 앞머리를 고쳤다 — 같은 날짜 안에서 가장 닮은 줄
    for x in pool:
        if x[:10] != day:
            continue
        r = difflib.SequenceMatcher(None, line, x).ratio()
        if r > score:
            best, score = x, r
    if best is not None and score >= 0.7:
        pool.remove(best); return (f"고침(닮음 {score:.2f})", best)
    return None

for line in b:
    hit = take(line)
    if hit is None:
        lost.append(line)
    elif hit[0] != "같음":
        edited.append((hit[0], line, hit[1]))

msg = f"기준 {len(b)}항목 · 새 판 {len(a)}항목"
if moved:
    msg += f" · 보관 {len(m)}항목"
print(msg)
for kind, was, now in edited:      # ★«고친 것으로 봤다»를 눈에 보이게 — 짝이 틀렸으면 사람이 여기서 잡는다
    print(f"   {kind}: {was[:60]}…")
    print(f"        → {now[:60]}…")
if lost:
    print(f"⛔ 사라지는 항목 {len(lost)}개 — 올리지 마라. 기준을 다시 받아 편집을 다시 얹어라.")
    for l in lost:
        print("   잃음:", l[:140])
    sys.exit(1)
print("사라지는 항목 없음 — 올려도 된다")
