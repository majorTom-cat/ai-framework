#!/usr/bin/env python3
"""`docs/friction/`(마찰 기록, 항목 하나 = 파일 하나)에서 항목을 잃거나 망가뜨렸는지 본다 — 차단형.

짝: `check-append-only.py` 는 옛 한 파일(`docs/friction.md`)의 «사라진 줄»을 본다. 이 검사기는 새 폴더를 본다.
    부르는 곳 = `check-append-only-git.sh`(CI 묶음 잡 `mr-checks` 의 `append-only-check`). 기준은 **대상 브랜치의 지금 tip**
    이다(merge base 가 아니다 — 같은 이유, 그 스크립트 머리 참조). 검사를 끄거나 merge base 로 바꾸지 마라.

막는 것(종료 1):
  • 삭제 — 기준에 있던 파일이 새 트리의 `docs/friction/` 에도 `보관/` 에도 없다
  • 덮어쓰기 — 내용이 «기준 줄» 그대로도, «기준 줄 + ` [닫힘:값]`» 도 아니다
  • 중복 — 같은 파일이 열린 쪽과 보관 둘 다에 있다 / 서로 다른 파일이 고유 6자리 ID 를 나눠 쓴다
  • 형식 — 이름이 `YYYY-MM-DD-<카드번호|0>-<6자리>.md` 가 아니다 / 한 줄이 아니다 / 날짜로 시작하지 않는다 /
    줄 날짜와 이름 날짜가 다르다 / 보관에 있던 파일이 보관 밖으로 나왔다
허용: 새 파일 추가 · 줄 끝에 `[닫힘:값]` 추가 · 닫힌 파일을 `보관/` 으로 이동(내용 그대로).
읽기 실패(utf-8 아님 등)·git 조회 실패는 «통과»가 아니라 **판정 불능(종료 2)**.

사용: python3 check-friction-dir.py <대상ref>      (repo 루트에서)
"""
import sys, os, re, subprocess

for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8")
    except (AttributeError, ValueError, OSError):
        pass

NAME = re.compile(r"^(\d{4}-\d{2}-\d{2})-(\d+|0)-([a-z0-9]{6})\.md$")
ENTRY = re.compile(r"^\d{4}-\d{2}-\d{2}")
CLOSE_TAIL = re.compile(r" \[닫힘:[^\]\s]+\]$")
D = "docs/friction"
ARCH = D + "/보관"


def unreadable(msg):
    print(f"⛔ 판정 불능 — {msg}")
    sys.exit(2)


def git(*a):
    r = subprocess.run(["git", *a], capture_output=True)
    if r.returncode != 0:
        return None
    return r.stdout


def parse_line(raw):
    """바이트 → 한 줄(없으면 None, 사유)."""
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        return None, "utf-8 이 아니다"
    lines = [l for l in text.split("\n") if l.strip() != ""]
    if len(lines) != 1:
        return None, f"한 줄이어야 한다(실제 {len(lines)}줄)"
    if not ENTRY.match(lines[0]):
        return None, "날짜(YYYY-MM-DD)로 시작하지 않는다"
    return lines[0].rstrip(), None


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    ref = sys.argv[1]
    if git("rev-parse", "--verify", "--quiet", ref) is None:
        unreadable(f"기준 ref '{ref}' 를 못 찾았다")

    # ── 기준(대상 브랜치 tip)의 파일들
    ls = git("ls-tree", "-r", "--name-only", ref, "--", D)
    if ls is None:
        unreadable(f"git ls-tree {ref} 실패")
    base = {}      # 경로 → 줄
    for p in ls.decode("utf-8").splitlines():
        if not p.endswith(".md"):
            continue
        raw = git("show", f"{ref}:{p}")
        if raw is None:
            unreadable(f"기준 파일을 못 읽었다: {p}")
        line, err = parse_line(raw)
        if err:      # 기준이 이미 깨져 있으면 이 MR 탓이 아니다 — 비교에서 뺀다(알린다)
            print(f"· 기준에서 이미 형식이 어긋난 파일(비교 제외): {p} — {err}")
            continue
        base[p] = line

    # ── 새 트리(작업 폴더)의 파일들
    cur = {}
    problems = []
    for root_dir in (D, ARCH):
        if not os.path.isdir(root_dir):
            continue
        for n in sorted(os.listdir(root_dir)):
            p = f"{root_dir}/{n}"
            if not os.path.isfile(p) or not n.endswith(".md"):
                continue
            try:
                with open(p, "rb") as f:
                    raw = f.read()
            except OSError as e:
                unreadable(f"새 파일을 못 읽었다: {p}: {e}")
            m = NAME.match(n)
            if not m:
                problems.append(f"형식: 이름이 YYYY-MM-DD-<카드번호|0>-<6자리>.md 가 아니다 — {p}")
                continue
            line, err = parse_line(raw)
            if err:
                problems.append(f"형식: {err} — {p}")
                continue
            if line[:10] != m.group(1):
                problems.append(f"형식: 줄 날짜({line[:10]})와 이름 날짜({m.group(1)})가 다르다 — {p}")
                continue
            cur[p] = line

    if not base and not cur and not problems:
        print(f"· 건너뜀 — {D}/ 가 기준에도 이 트리에도 없다(아직 안 쓰는 repo)")
        print(f"──── 검사 0건 · 건너뜀 1건")
        return 0

    # ── 중복 ID (서로 다른 파일이 6자리를 나눠 씀) · 같은 이름이 열린 쪽과 보관 둘 다에 있음
    by_id, by_name = {}, {}
    for p in cur:
        n = os.path.basename(p)
        by_id.setdefault(NAME.match(n).group(3), []).append(p)
        by_name.setdefault(n, []).append(p)
    for n, ps in by_name.items():
        if len(ps) > 1:
            problems.append(f"중복: 같은 파일이 열린 쪽과 보관 둘 다에 있다 — {n}")
    for uid, ps in by_id.items():
        if len({os.path.basename(x) for x in ps}) > 1:
            problems.append(f"중복 ID: 서로 다른 파일이 '{uid}' 를 나눠 쓴다 — {', '.join(ps)}")

    # ── 기준 파일이 어떻게 됐나
    checked = 0
    for p, bline in sorted(base.items()):
        checked += 1
        n = os.path.basename(p)
        was_archived = p.startswith(ARCH + "/")
        live, arch = f"{D}/{n}", f"{ARCH}/{n}"
        where = [x for x in (live, arch) if x in cur]
        if not where:
            if os.path.exists(live) or os.path.exists(arch):
                continue      # 있는데 형식 문제로 cur 에 못 든 것 — 위에서 이미 «형식» 으로 보고했다
            problems.append(f"삭제: 기준에 있던 파일이 사라졌다 — {p} (지우지 말고 보관/ 으로 옮겨라)")
            continue
        if was_archived and live in cur:
            problems.append(f"형식: 보관에 있던 파일이 보관 밖으로 나왔다 — {n}")
            continue
        now = cur[where[0]]
        if now == bline:
            continue
        if now.startswith(bline) and CLOSE_TAIL.fullmatch(now[len(bline):]) and CLOSE_TAIL.search(bline) is None:
            continue      # 닫힘 표시 추가만 허용
        problems.append(f"덮어쓰기: 내용이 기준 줄 그대로도 «기준 줄+닫힘 표시» 도 아니다 — {p}")

    new_files = [p for p in cur if f"{D}/{os.path.basename(p)}" not in base and f"{ARCH}/{os.path.basename(p)}" not in base]
    print(f"기준 {len(base)}개 · 새 트리 {len(cur)}개 · 새로 더한 {len(new_files)}개")
    print(f"──── 검사 {checked}건(기준 파일) + 형식·중복 전수")
    if problems:
        for pr in problems:
            print("⛔", pr)
        print(f"⛔ {len(problems)}건 — 기준을 다시 받아 편집을 다시 얹어라(_reference/append-only.md)")
        return 1
    print("마찰 폴더: 잃은 항목 없음 — OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
