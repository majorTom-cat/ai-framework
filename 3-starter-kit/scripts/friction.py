#!/usr/bin/env python3
"""마찰 기록 도구 — 항목 하나 = 파일 하나(`docs/friction/`). 등록·조회·닫기·보관을 한 곳에서.

왜: 여러 세션이 `docs/friction.md` 맨 위 같은 자리에 동시에 줄을 더하면 병합 충돌이 난다(배포처 bnsone #776,
    2026-10-21 MR 3건이 이 충돌로 필수 검사에서 실패). 고유 파일 이름에 각자 더하면 충돌이 없다.
    union 병합은 보관으로 옮긴 줄을 되살려서(충돌 14건 중 8건) 단독 해법이 못 된다.

파일: `docs/friction/<YYYY-MM-DD>-<카드번호|0>-<고유6자리>.md` · 내용 = 지금과 같은 «한 줄»(끝에 `[닫힘:…]` 규약 그대로).
옛 기록(`docs/friction.md`·`docs/friction-보관.md`)은 일괄 이동하지 않는다 — 조회·세기에서 함께 읽는다.

사용 (repo 루트에서. 킷 저장소 자신은 `--root 3-starter-kit`):
  python3 scripts/friction.py add [--card N] "<한 줄>"   등록. 날짜로 안 시작하면 오늘 날짜를 앞에 붙인다
  python3 scripts/friction.py list [--open|--closed|--blocked]   옛 파일 + 새 폴더를 합쳐 보여 준다
  python3 scripts/friction.py count                      「막힘 N / 안 닫힌 줄 M — 가장 오래된 날짜」 (`/todo` 0-c 값)
  python3 scripts/friction.py close <고유6자리|파일명> <값>   줄 끝에 ` [닫힘:값]` 을 붙인다
  python3 scripts/friction.py archive [--keep 5]         닫힌 파일을 최신 N개만 남기고 `보관/` 으로 옮긴다(삭제 아님)
종료: 0 정상 · 1 입력 오류 · 2 읽기 불능
"""
import sys, os, re, secrets, datetime, shutil

for _s in (sys.stdout, sys.stderr):      # Windows cp949 콘솔에서 «—»·«⚠️» 로 죽지 않게(check-append-only.py 와 같은 이유)
    try:
        _s.reconfigure(encoding="utf-8")
    except (AttributeError, ValueError, OSError):
        pass

ENTRY = re.compile(r"^\d{4}-\d{2}-\d{2}")
NAME = re.compile(r"^(\d{4}-\d{2}-\d{2})-(\d+|0)-([a-z0-9]{6})\.md$")
CLOSED = "[닫힘:"
LEGACY_SINCE = "2026-08-31"      # 옛 파일의 «안 닫힌 줄» 은 토큰 신설일 이후만 센다(/todo 0-c 와 같은 잣대)


def die(msg, code=1):
    print(msg, file=sys.stderr)
    sys.exit(code)


def parse_root(args):
    root = "."
    if "--root" in args:
        i = args.index("--root")
        if i + 1 >= len(args):
            die("--root 뒤에 폴더가 없다")
        root = args[i + 1]
        del args[i:i + 2]
    return root, args


def read_entry_file(path):
    """폴더 파일 하나 = 한 줄. 읽기 실패·형식 오류는 None 과 사유."""
    try:
        with open(path, encoding="utf-8") as f:
            text = f.read()
    except (OSError, UnicodeDecodeError) as e:
        return None, f"읽을 수 없다: {e}"
    lines = [l for l in text.split("\n") if l.strip() != ""]
    if len(lines) != 1:
        return None, f"한 줄이어야 한다(실제 {len(lines)}줄)"
    if not ENTRY.match(lines[0]):
        return None, "날짜(YYYY-MM-DD)로 시작하지 않는다"
    return lines[0].rstrip(), None


def legacy_lines(root, name):
    p = os.path.join(root, "docs", name)
    if not os.path.isfile(p):
        return []
    try:
        with open(p, encoding="utf-8") as f:
            return [l.rstrip("\n") for l in f if ENTRY.match(l)]
    except (OSError, UnicodeDecodeError) as e:
        die(f"⛔ 읽기 불능 — {p}: {e}", 2)


def folder_entries(root, sub=""):
    d = os.path.join(root, "docs", "friction", sub)
    out = []
    if not os.path.isdir(d):
        return out
    for n in sorted(os.listdir(d)):
        p = os.path.join(d, n)
        if not os.path.isfile(p) or not n.endswith(".md"):
            continue
        line, err = read_entry_file(p)
        if err:
            die(f"⛔ 읽기 불능 — {p}: {err}", 2)
        out.append((n, line))
    return out


def all_entries(root):
    """(출처, 줄) — 옛 friction.md · 옛 보관 · 새 폴더 · 새 보관. 출처 접두 `옛`/`새`."""
    res = []
    for src, name in (("옛", "friction.md"), ("옛보관", "friction-보관.md")):
        for l in legacy_lines(root, name):
            res.append((src, l))
    for n, l in folder_entries(root):
        res.append((f"새:{n}", l))
    for n, l in folder_entries(root, "보관"):
        res.append((f"새보관:{n}", l))
    return res


def is_closed(line):
    return CLOSED in line


def is_blocked(line):
    return "[막힘]" in line and not is_closed(line)


def cmd_add(root, args):
    card = "0"
    if "--card" in args:
        i = args.index("--card")
        if i + 1 >= len(args) or not args[i + 1].isdigit():
            die("--card 뒤에는 카드 번호(숫자)가 와야 한다")
        card = args[i + 1]
        del args[i:i + 2]
    if len(args) != 1 or not args[0].strip():
        die("사용: friction.py add [--card N] \"<한 줄>\"")
    line = args[0].strip()
    if "\n" in line:
        die("한 줄이어야 한다 — 줄바꿈이 들어 있다")
    today = datetime.date.today().isoformat()
    if not ENTRY.match(line):
        line = f"{today} {line}"
    d = os.path.join(root, "docs", "friction")
    os.makedirs(d, exist_ok=True)
    existing = {NAME.match(n).group(3) for n in os.listdir(d) if NAME.match(n)}
    sub = os.path.join(d, "보관")
    if os.path.isdir(sub):
        existing |= {NAME.match(n).group(3) for n in os.listdir(sub) if NAME.match(n)}
    for _ in range(50):
        uid = "".join(secrets.choice("abcdefghijklmnopqrstuvwxyz0123456789") for _ in range(6))
        if uid not in existing:
            break
    else:
        die("고유 ID 를 못 만들었다", 2)
    name = f"{line[:10]}-{card}-{uid}.md"
    path = os.path.join(d, name)
    if os.path.exists(path):
        die(f"이미 있는 파일이다(덮어쓰지 않는다): {path}", 2)
    with open(path, "x", encoding="utf-8") as f:     # "x" = 있으면 실패 — 무음 덮어쓰기 금지
        f.write(line + "\n")
    print(path)


def cmd_list(root, args):
    mode = args[0] if args else ""
    if mode not in ("", "--open", "--closed", "--blocked"):
        die("사용: friction.py list [--open|--closed|--blocked]")
    n = 0
    for src, line in all_entries(root):
        if mode == "--open" and is_closed(line):
            continue
        if mode == "--closed" and not is_closed(line):
            continue
        if mode == "--blocked" and not is_blocked(line):
            continue
        print(f"{src} | {line[:140]}")
        n += 1
    print(f"──── {n}건", file=sys.stderr)


def cmd_count(root, args):
    # ★경로가 없으면 «0건» 이 아니라 판정 불능이다 — 작업 폴더가 사라진 셸에서 «0·0» 을 «다 닫혔다» 로 읽는 사고(스캔상세 §2-c)
    if not os.path.isfile(os.path.join(root, "docs", "friction.md")) and not os.path.isdir(os.path.join(root, "docs", "friction")):
        die(f"⛔ 판정 불능 — 마찰 기록 경로가 없다: {os.path.abspath(root)}/docs/friction.md 도 docs/friction/ 도 없다(작업 폴더·--root 를 확인)", 2)
    blocked, opened, oldest = 0, 0, None
    for src, line in all_entries(root):
        if src.startswith("옛보관") or src.startswith("새보관") or is_closed(line):
            continue
        day = line[:10]
        if src == "옛" and day < LEGACY_SINCE:
            continue
        opened += 1
        if is_blocked(line):
            blocked += 1
        if oldest is None or day < oldest:
            oldest = day
    if oldest is None:
        print("막힘 0건 / 안 닫힌 줄 0건")
        return
    days = (datetime.date.today() - datetime.date.fromisoformat(oldest)).days
    print(f"막힘 {blocked}건 / 안 닫힌 줄 {opened}건 — 가장 오래된 {oldest}({days}일째)")


def find_open(root, ref):
    d = os.path.join(root, "docs", "friction")
    hits = []
    if os.path.isdir(d):
        for n in os.listdir(d):
            if n.endswith(".md") and os.path.isfile(os.path.join(d, n)) and (n == ref or n == ref + ".md" or NAME.match(n) and NAME.match(n).group(3) == ref):
                hits.append(n)
    return hits


def cmd_close(root, args):
    if len(args) != 2:
        die("사용: friction.py close <고유6자리|파일명> <값>")
    ref, val = args
    if not val or re.search(r"\s", val) or "]" in val:
        die("닫힘 값에 공백·`]`·줄바꿈을 넣지 마라(괄호를 끼우면 기계가 못 센다 — 부가정보는 콜론 뒤)")
    hits = find_open(root, ref)
    if len(hits) != 1:
        die(f"{ref} 에 맞는 열린 파일이 {len(hits)}개다 — 정확한 6자리나 파일명을 줘라")
    p = os.path.join(root, "docs", "friction", hits[0])
    line, err = read_entry_file(p)
    if err:
        die(f"⛔ {p}: {err}", 2)
    if is_closed(line):
        die(f"이미 닫혀 있다: {hits[0]}")
    with open(p, "w", encoding="utf-8") as f:
        f.write(f"{line} [닫힘:{val}]\n")
    print(p)


def cmd_archive(root, args):
    keep = 5
    if args:
        if len(args) == 2 and args[0] == "--keep" and args[1].isdigit():
            keep = int(args[1])
        else:
            die("사용: friction.py archive [--keep N]")
    closed = [(n, l) for n, l in folder_entries(root) if is_closed(l)]
    closed.sort(key=lambda x: x[0])          # 파일명이 날짜로 시작 — 오래된 것이 앞
    movable = closed[:-keep] if keep else closed
    if not movable:
        print("옮길 닫힌 파일 없음")
        return
    sub = os.path.join(root, "docs", "friction", "보관")
    os.makedirs(sub, exist_ok=True)
    for n, _ in movable:
        dst = os.path.join(sub, n)
        if os.path.exists(dst):
            die(f"보관에 같은 이름이 이미 있다(덮어쓰지 않는다): {dst}", 2)
        shutil.move(os.path.join(root, "docs", "friction", n), dst)
    print(f"{len(movable)}개를 보관/ 으로 옮겼다(삭제 아님)")


def main():
    args = sys.argv[1:]
    root, args = parse_root(args)
    if not args:
        print(__doc__)
        sys.exit(1)
    cmd, rest = args[0], args[1:]
    fn = {"add": cmd_add, "list": cmd_list, "count": cmd_count, "close": cmd_close, "archive": cmd_archive}.get(cmd)
    if fn is None:
        print(__doc__)
        sys.exit(1)
    fn(root, rest)


if __name__ == "__main__":
    main()
