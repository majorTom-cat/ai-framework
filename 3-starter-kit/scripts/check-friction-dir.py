#!/usr/bin/env python3
"""마찰 기록(`docs/friction/` 항목별 파일 + 옛 `docs/friction.md`·`friction-보관.md`)에서 항목을 잃거나 망가뜨렸는지 본다 — 차단형.

짝: `check-append-only.py` 는 옛 한 파일의 «사라진 줄»을 본다. 이 검사기는 새 폴더를 본다 + 옛 파일에 «새 줄»이 더해지는 것을 막는다.
    부르는 곳 = `check-append-only-git.sh`(CI 묶음 잡 `mr-checks` 의 `append-only-check`). 기준은 **대상 브랜치의 지금 tip**
    이다(merge base 가 아니다 — 같은 이유, 그 스크립트 머리 참조). 검사를 끄거나 merge base 로 바꾸지 마라.

막는 것(종료 1):
  • 삭제 — 기준에 있던 파일이 새 트리의 `docs/friction/` 에도 `보관/`(월별 하위 폴더 포함) 에도 없다
  • 덮어쓰기 — 내용이 «기준 줄» 그대로도, «기준 줄 + ` [닫힘:값]`» 도 아니다
  • 중복 — 같은 이름 파일이 둘 이상의 자리에 있다 / 서로 다른 파일이 고유 6자리 ID 를 나눠 쓴다
  • 형식 — 이름이 `YYYY-MM-DD-<카드번호|0>-<6자리>.md` 가 아니다 / 한 줄이 아니다 / 날짜로 시작하지 않는다 /
    줄 날짜와 이름 날짜가 다르다 / 보관에 있던 파일이 보관 밖으로 나왔다 / 월별 폴더 이름이 YYYY-MM 이 아니다
  • 옛 파일에 새 줄 — 기준 tip 에 `docs/friction/` 가 이미 있는데(= 이 repo 가 새 방식을 쓴다) 옛 `friction.md`·`friction-보관.md` 에
    기준에 없던 항목 줄이 더해졌다. 새 기록은 `friction.py add` 로 폴더에 적는다. (줄 앞머리를 고친 정상 편집은 통과)
허용: 새 폴더 파일 · 줄 끝에 `[닫힘:값]` 추가 · 닫힌 파일을 `보관/` 또는 `보관/<YYYY-MM>/` 으로 이동(내용 그대로) ·
  옛 파일의 줄을 닫기 · 옛 파일에서 옛 보관 파일로 옮기기(기준에 있던 줄이므로 «새 줄»이 아니다).
오래된 브랜치(대상 tip 을 아직 안 품음)는 갈라진 지점의 기록만 기준으로 본다 — main 이 나중에 더한·닫은·보관한 기록은 막지 않는다.
옛 파일·입출력·git 조회 실패는 «통과»가 아니라 **판정 불능(종료 2)**. 새 폴더 파일이 utf-8 이 아닌 것은 형식 오류(종료 1).

사용: python3 check-friction-dir.py <대상ref>      (repo 루트에서)
"""
import sys, os, re, subprocess, difflib

for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8")
    except (AttributeError, ValueError, OSError):
        pass

NAME = re.compile(r"^(\d{4}-\d{2}-\d{2})-(\d+|0)-([a-z0-9]{6})\.md$")
ENTRY = re.compile(r"^\d{4}-\d{2}-\d{2}")
MONTH = re.compile(r"^\d{4}-\d{2}$")
CLOSE_TAIL = re.compile(r" \[닫힘:[^\]\s]+\]$")
D = "docs/friction"
ARCH = D + "/보관"
LEGACY = ("docs/friction.md", "docs/friction-보관.md")


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


def legacy_entries_text(raw, label):
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        unreadable(f"{label} 가 utf-8 이 아니다")
    return [l.rstrip("\r") for l in text.split("\n") if ENTRY.match(l)]


def matches_base(line, pool):
    """옛 파일의 현재 항목 줄이 기준에 있던 줄과 짝인가 — 같음 · 줄 끝 닫힘 추가 · 앞머리 고침(닮음). 짝을 pool 에서 소비한다."""
    if line in pool:
        pool.remove(line); return True
    for b in pool:
        if line.startswith(b) and CLOSE_TAIL.fullmatch(line[len(b):]):
            pool.remove(b); return True
    head = line[:80]
    for b in pool:
        if b.startswith(head) or line.startswith(b[:80]):
            pool.remove(b); return True
    best, score = None, 0.0
    for b in pool:
        if b[:10] != line[:10]:
            continue
        r = difflib.SequenceMatcher(None, line, b).ratio()
        if r > score:
            best, score = b, r
    if best is not None and score >= 0.7:
        pool.remove(best); return True
    return False


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    ref = sys.argv[1]
    if git("rev-parse", "--verify", "--quiet", ref) is None:
        unreadable(f"기준 ref '{ref}' 를 못 찾았다")

    # ── 기준 = 대상 브랜치 tip. 단 tip 을 아직 안 품은 «오래된 브랜치»는 갈라진 시점(merge base)에 있던 기록만 «지켰나» 로 본다
    #    (그 뒤 main 이 더한·닫은·보관한 기록은 브랜치 탓이 아니고 git 병합이 그대로 살린다 — bnsone dev 776). tip 을 품은 브랜치는 그대로 엄격하게 tip 기준.
    rc = subprocess.run(["git", "merge-base", "--is-ancestor", ref, "HEAD"], capture_output=True).returncode
    if rc == 0:
        basis = ref
    elif rc == 1:
        mb = git("merge-base", ref, "HEAD")
        if mb is None or not mb.strip():
            unreadable(f"'{ref}' 와 HEAD 의 갈라진 지점을 못 찾았다(얕은 clone 이면 이력을 더 받아라)")
        basis = mb.decode().strip()
        print(f"· 오래된 브랜치 — {ref} 를 품고 있지 않아 갈라진 지점({basis[:8]})의 기록을 기준으로 본다")
    else:
        unreadable(f"git merge-base --is-ancestor {ref} HEAD 실패")

    # ★`-z`: 없으면 git 이 한글 경로(`보관/`)를 «"\353\263…"» 로 따옴표 쳐 내서 `.md` 끝맺음이 깨지고 보관 안 파일이 통째로 검사에서 빠진다.
    tip_ls = git("ls-tree", "-r", "-z", "--name-only", ref, "--", D)
    if tip_ls is None:
        unreadable(f"git ls-tree {ref} 실패")
    ls = git("ls-tree", "-r", "-z", "--name-only", basis, "--", D)
    if ls is None:
        unreadable(f"git ls-tree {basis} 실패")
    base = {}      # 경로 → 줄
    for p in ls.decode("utf-8").split("\0"):
        if not p.endswith(".md"):
            continue
        raw = git("show", f"{basis}:{p}")
        if raw is None:
            unreadable(f"기준 파일을 못 읽었다: {p}")
        line, err = parse_line(raw)
        if err:      # 기준이 이미 깨져 있으면 이 MR 탓이 아니다 — 비교에서 뺀다(알린다)
            print(f"· 기준에서 이미 형식이 어긋난 파일(비교 제외): {p} — {err}")
            continue
        base[p] = line
    adopted = bool(tip_ls.strip())      # 기준 tip 에 폴더가 이미 있다 = 이 repo 는 새 방식을 쓴다

    # ── 새 트리(작업 폴더)의 파일들 — 열린 쪽은 바로 아래만, 보관은 월별 하위 폴더까지
    cur = {}
    problems = []
    scan = []
    if os.path.isdir(D):
        scan.append((D, False))
    if os.path.isdir(ARCH):
        for root_dir, dirs, _files in os.walk(ARCH):
            dirs.sort()
            scan.append((root_dir.replace(os.sep, "/"), True))
    for root_dir, is_arch in scan:
        if is_arch and root_dir != ARCH:
            sub = root_dir[len(ARCH) + 1:]
            if "/" in sub or not MONTH.match(sub):
                problems.append(f"형식: 보관 하위 폴더 이름이 YYYY-MM 이 아니다 — {root_dir}")
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

    if not base and not cur and not problems and not adopted:
        print(f"· 건너뜀 — {D}/ 가 기준에도 이 트리에도 없다(아직 안 쓰는 repo)")
        print(f"──── 검사 0건 · 건너뜀 1건")
        return 0

    # ── 중복 ID (서로 다른 파일이 6자리를 나눠 씀) · 같은 이름이 둘 이상의 자리에 있음
    by_id, by_name = {}, {}
    for p in cur:
        n = os.path.basename(p)
        by_id.setdefault(NAME.match(n).group(3), []).append(p)
        by_name.setdefault(n, []).append(p)
    for n, ps in by_name.items():
        if len(ps) > 1:
            problems.append(f"중복: 같은 이름 파일이 둘 이상의 자리에 있다(열린 쪽·보관·월별 폴더) — {', '.join(ps)}")
    for uid, ps in by_id.items():
        if len({os.path.basename(x) for x in ps}) > 1:
            problems.append(f"중복 ID: 서로 다른 파일이 '{uid}' 를 나눠 쓴다 — {', '.join(ps)}")

    # ── 기준 파일이 어떻게 됐나 (보관 안에서의 자리 이동은 허용 — 같은 이름이 보관 어딘가에 있으면 된다)
    checked = 0
    for p, bline in sorted(base.items()):
        checked += 1
        n = os.path.basename(p)
        was_archived = p.startswith(ARCH + "/")
        where = by_name.get(n, [])
        if not where:
            if os.path.exists(f"{D}/{n}") or any(os.path.exists(os.path.join(r, n)) for r, _, _ in os.walk(ARCH)):
                continue      # 있는데 형식 문제로 cur 에 못 든 것 — 위에서 이미 «형식» 으로 보고했다
            problems.append(f"삭제: 기준에 있던 파일이 사라졌다 — {p} (지우지 말고 보관/ 으로 옮겨라)")
            continue
        if len(where) > 1:
            continue      # 중복으로 이미 보고했다
        if was_archived and not where[0].startswith(ARCH + "/"):
            problems.append(f"형식: 보관에 있던 파일이 보관 밖으로 나왔다 — {n}")
            continue
        now = cur[where[0]]
        if now == bline:
            continue
        if now.startswith(bline) and CLOSE_TAIL.fullmatch(now[len(bline):]) and CLOSE_TAIL.search(bline) is None:
            continue      # 닫힘 표시 추가만 허용
        problems.append(f"덮어쓰기: 내용이 기준 줄 그대로도 «기준 줄+닫힘 표시» 도 아니다 — {p}")

    # ── 옛 파일(friction.md·friction-보관.md)에 «새 줄» 금지 — 이 repo 가 새 방식을 쓰는 경우만
    legacy_new = 0
    if adopted:
        pool = []
        for lp in LEGACY:
            raw = git("show", f"{basis}:{lp}")
            if raw is not None:
                pool += legacy_entries_text(raw, f"기준의 {lp}")
        for lp in LEGACY:
            if not os.path.isfile(lp):
                continue
            try:
                with open(lp, "rb") as f:
                    raw = f.read()
            except OSError as e:
                unreadable(f"{lp} 를 못 읽었다: {e}")
            for line in legacy_entries_text(raw, lp):
                if not matches_base(line, pool):
                    legacy_new += 1
                    problems.append(f"옛 파일에 새 줄: {lp} — {line[:70]}… (새 기록은 `python3 scripts/friction.py add` 로 docs/friction/ 에 적어라)")

    new_files = [p for p in cur if os.path.basename(p) not in {os.path.basename(b) for b in base}]
    print(f"기준 {len(base)}개 · 새 트리 {len(cur)}개 · 새로 더한 {len(new_files)}개" + (f" · 옛 파일에 더한 새 줄 {legacy_new}개" if adopted else ""))
    print(f"──── 검사 {checked}건(기준 파일) + 형식·중복 전수" + (" + 옛 파일 새 줄" if adopted else ""))
    if problems:
        for pr in problems:
            print("⛔", pr)
        print(f"⛔ {len(problems)}건 — 기준을 다시 받아 편집을 다시 얹어라(_reference/append-only.md)")
        return 1
    print("마찰 기록: 잃은 항목 없음 — OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
