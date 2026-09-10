#!/usr/bin/env python3
"""마찰 로그를 «최신이 맨 위» 순서로 정리하고, 끝난 줄은 보관 파일로 옮긴다.

왜 «지우기»가 아니라 «옮기기»인가: 마찰 줄은 규칙의 «영수증»이다. 규칙은 「이렇게 해라」만
말하고 왜 그런지는 그 줄에만 있다 — 2026-09-10 에 「bash -c 로 감싸라」가 틀렸다는 걸
뒤집을 수 있었던 근거가 바로 그 줄의 당시 실측이었다. 지우면 되돌릴 근거가 사라진다.

왜 «최신이 위»인가: 잘려도(head·컴팩션·사람의 훑어보기) 살아남는 쪽이 최신이어야 한다.
append 전용이면 정확히 반대로 남는다(오너 지적 2026-09-10).

작업 파일에 남기는 것 = 머리말 + **열린 줄 전부**(최신 위) + **최근 닫힘 KEEP 줄**(최신 위).
그 밖의 닫힌 줄은 전부 보관 파일 맨 위로 간다.

사용: python3 archive-friction.py <friction.md> <보관.md> [남길_닫힘_줄수=5] [--oldest-first]
      --oldest-first = 「이 파일은 오래된 것이 위」라고 «부르는 쪽이» 말해 주는 것. 추측하지 않는다.
"""
import sys, re, os

_args = [a for a in sys.argv[1:] if a != "--oldest-first"]
OLDEST_FIRST = "--oldest-first" in sys.argv[1:]   # ★옛 순서 파일을 처음 옮겨올 때만
if len(_args) < 2:
    print(__doc__); sys.exit(2)
src = _args[0]
dst = _args[1]
KEEP = int(_args[2]) if len(_args) > 2 else 5

text = open(src, encoding="utf-8").read()
lines = text.split("\n")

entry = re.compile(r"^\d{4}-")
is_entry = lambda l: entry.match(l) is not None
is_closed = lambda l: "[닫힘:" in l          # ★기계가 보는 건 이 접두어뿐이다

idx = [i for i, l in enumerate(lines) if is_entry(l)]
if not idx:
    print("항목이 없다 — 아무것도 안 했다"); sys.exit(0)
head = lines[: idx[0]]
entries = [lines[i] for i in idx]
stray = [l for i, l in enumerate(lines) if i >= idx[0] and not is_entry(l) and l.strip()]

# ★파일 안 순서가 정본이다 — 다시 정렬하지 않는다.
#   왜: 날짜로 재정렬하면 **같은 날 줄의 앞뒤가 뭉개진다**(2026-09-10 실측 — 그날 적은 새 줄이
#   같은 날짜 5줄 뒤로 밀려 보관으로 딸려갔다). 날짜는 «하루» 단위라 그 안의 순서를 못 가른다.
#   규약이 «새 줄은 맨 위»이므로 파일 순서가 곧 최신순이다.
def key(l):
    return l[:10]
# ★뒤집을지는 **추측하지 않는다 — 부르는 쪽이 말한다.**
#   2026-09-10 에 추측이 두 번 틀렸다: ⑴«첫 줄 대 마지막 줄» 비교는 bnsone friction.md 처럼
#   **첫 줄도 마지막 줄도 같은 날짜**면 «최신이 위»로 오판한다 ⑵이웃 쌍을 세는 방식도 **동점**이면
#   같은 오판이 난다. 그 상태로 돌리면 **가장 오래된 닫힘 KEEP 줄이 남고 최신 닫힘이 보관으로 간다**
#   — 하려던 것의 정반대이고, 결과만 보면 정상처럼 보인다(항목 수는 맞으니까).
#   ⇒ 기본은 **파일 순서가 정본**(이 파일의 규약이 «새 줄은 맨 위»이므로 그것이 곧 최신순)이고,
#     옛 순서 파일을 처음 옮겨올 때만 `--oldest-first` 를 준다. 아래 경고가 그 자리를 알려 준다.
asc = sum(1 for a, b in zip(entries, entries[1:]) if a[:10] < b[:10])
desc = sum(1 for a, b in zip(entries, entries[1:]) if a[:10] > b[:10])
entries_new_first = list(reversed(entries)) if OLDEST_FIRST else list(entries)
if OLDEST_FIRST:
    print("ℹ️ --oldest-first: 옛 순서 파일로 보고 한 번 뒤집는다(이후로는 파일 순서를 그대로 쓴다)")
elif asc > 0:
    # ★«많으냐»가 아니라 «하나라도 있느냐»로 묻는다 — «최신이 맨 위»인 파일에는 날짜가 올라가는
    #   이웃 쌍이 **하나도 없어야** 한다. «asc > desc» 로 물으면 동점(1:1)에서 조용히 지나간다.
    print(f"⚠️ 날짜가 «올라가는» 이웃 쌍이 {asc}개 있다(내려가는 쌍 {desc}개) — 이 파일은 «최신이 맨 위»가 아니다.\n"
          "   그대로 두면 **가장 오래된 닫힘 줄이 남는다.** 처음 옮겨오는 파일이면 `--oldest-first` 를 붙여 다시 돌려라.")

open_e   = [l for l in entries_new_first if not is_closed(l)]
closed_e = [l for l in entries_new_first if is_closed(l)]
keep_c, move_c = closed_e[:KEEP], closed_e[KEEP:]

# ★구획 표시 — «어디를 봐야 하나»를 한 눈에(Anthropic 권고: 제목·태그로 구획을 나눠라).
#   `/todo` 0-c 는 `^\d{4}-` 로 세므로 제목 줄은 집계에 안 걸린다.
head = [l for l in head if not l.startswith("## 지금 살아 있는 것")
        and not l.startswith("## 최근에 끝난 것")]
while head and not head[-1].strip():
    head.pop()
body = ["", "## 지금 살아 있는 것 — 아직 안 고쳐진 줄"] + (open_e or ["(없음)"])
body += ["", f"## 최근에 끝난 것 (최신 {len(keep_c)}줄 — 그 앞은 `{os.path.basename(dst)}`)"] + keep_c
open(src, "w", encoding="utf-8").write("\n".join(head + body).rstrip("\n") + "\n")

if move_c:
    if os.path.exists(dst):
        old = open(dst, encoding="utf-8").read()
        i2 = [i for i, l in enumerate(old.split("\n")) if is_entry(l)]
        oldhead = "\n".join(old.split("\n")[: i2[0]]) if i2 else old.rstrip("\n")
        oldentries = [l for l in old.split("\n") if is_entry(l)]
    else:
        oldhead = (
            "# 마찰 기록 보관 — 끝난 줄의 «영수증» (최신이 맨 위)\n\n"
            "> ★**스캔 대상이 아니다.** `/todo` 0-c 가 세는 것은 `friction.md` 뿐이다.\n"
            "> **왜 지우지 않고 옮기나**: 마찰 줄은 규칙의 «영수증»이다. 규칙은 「이렇게 해라」만 적고\n"
            "> «왜 그런지»는 이 줄들에만 있다 — 규칙이 틀렸을 때 되돌릴 근거가 여기뿐이다.\n"
            "> **찾는 법**: 규칙이 이상해 보이면 그 규칙의 낱말로 이 파일을 `grep` 하라.\n"
        )
        oldentries = []
    seen, merged = set(), []
    for l in move_c + oldentries:      # 새로 옮긴 것이 위 — 보관 파일도 최신이 맨 위
        if l not in seen:
            seen.add(l); merged.append(l)
    open(dst, "w", encoding="utf-8").write(oldhead.rstrip("\n") + "\n\n" + "\n".join(merged) + "\n")

after = open(src, encoding="utf-8").read()
print(f"작업 파일: {len(text):,}자 → {len(after):,}자")
print(f"  남김 = 열림 {len(open_e)} + 최근 닫힘 {len(keep_c)}   /   보관으로 {len(move_c)}")
print(f"  항목 합계 {len(entries)} = {len(open_e) + len(keep_c)} + {len(move_c)} "
      f"→ {'손실 0' if len(entries) == len(open_e) + len(keep_c) + len(move_c) else '⛔ 수가 안 맞는다'}")
if stray:
    print(f"⚠️ 항목 사이의 «날짜로 시작하지 않는» 줄 {len(stray)}개는 버려졌다 — 확인하라:")
    for l in stray[:5]:
        print("   ", l[:80])
