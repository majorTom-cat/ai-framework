#!/usr/bin/env python3
"""닫힌 마찰 줄을 «오래된 것부터» 보관 파일로 옮겨 작업 파일을 한도 밑으로 내린다.

왜 «지우기»가 아니라 «옮기기»인가: 마찰 줄은 규칙의 «영수증»이다. 규칙은 「이렇게 해라」만
말하고 왜 그런지는 그 줄에만 있다 — 2026-09-10 에 「bash -c 로 감싸라」가 틀렸다는 걸
뒤집을 수 있었던 근거가 바로 그 줄의 당시 실측이었다. 지우면 되돌릴 근거가 사라진다.

사용: python3 archive.py <friction.md> <보관.md> [한도글자수]
"""
import sys, re, os

LIMIT = int(sys.argv[3]) if len(sys.argv) > 3 else 20000
src, dst = sys.argv[1], sys.argv[2]

text = open(src, encoding="utf-8").read()
lines = text.split("\n")

def is_entry(l):
    return re.match(r"^\d{4}-", l) is not None

def is_closed(l):
    return "[닫힘" in l

head = []          # 첫 항목 줄 앞의 머리말
entries = []       # (index, line)
for i, l in enumerate(lines):
    if is_entry(l):
        entries.append((i, l))
first = entries[0][0] if entries else len(lines)
head = lines[:first]
tail_noise = [l for i, l in enumerate(lines) if i >= first and not is_entry(l)]

open_entries = [l for _, l in entries if not is_closed(l)]
closed_entries = [l for _, l in entries if is_closed(l)]

def size(head_lines, keep):
    return len("\n".join(head_lines + keep + open_entries)) + 1

# 오래된 닫힘부터 뺀다(파일은 시간순 append 라 리스트 앞이 오래된 것)
moved = []
keep = list(closed_entries)
while keep and size(head, keep) > LIMIT:
    moved.append(keep.pop(0))

if not moved:
    print(f"옮길 것 없음 — 이미 {size(head, keep):,}자 (한도 {LIMIT:,})")
    sys.exit(0)

# 보관 파일
if os.path.exists(dst):
    arch = open(dst, encoding="utf-8").read().rstrip("\n") + "\n"
else:
    arch = (
        "# 마찰 기록 보관 — 닫힌 줄의 «영수증»\n\n"
        "> ★**이 파일은 스캔 대상이 아니다.** `/todo` 0-c 가 세는 것은 `friction.md` 뿐이다.\n"
        "> **왜 지우지 않고 옮기는가**: 마찰 줄은 규칙의 «영수증»이다. 규칙은 「이렇게 해라」만 적고,\n"
        "> «왜 그런지»는 이 줄들에만 있다 — 2026-09-10 에 「`bash -c` 로 감싸라」가 틀렸다는 것을\n"
        "> 뒤집을 수 있었던 근거가 바로 그 줄에 적힌 당시 실측이었다. 지우면 되돌릴 근거가 사라진다.\n"
        "> **찾는 법**: 규칙이 이상해 보이면 그 규칙의 낱말로 이 파일을 `grep` 하라.\n"
    )
arch += f"\n## {os.path.basename(src)} 에서 옮김 (2026-09-10 · {len(moved)}줄)\n\n"
arch += "\n".join(moved) + "\n"
open(dst, "w", encoding="utf-8").write(arch)

# 작업 파일
new = head + keep + open_entries
open(src, "w", encoding="utf-8").write("\n".join(new).rstrip("\n") + "\n")

print(f"옮김 {len(moved)}줄 → {dst}")
print(f"작업 파일: {len(text):,}자 → {len(open(src, encoding='utf-8').read()):,}자")
print(f"남은 항목: 닫힘 {len(keep)} + 열림 {len(open_entries)}")
if tail_noise:
    print(f"⚠️ 항목 사이의 «날짜 아닌 줄» {len(tail_noise)}개는 버려졌다 — 확인하라:")
    for l in tail_noise[:5]:
        print("   ", l[:80])
