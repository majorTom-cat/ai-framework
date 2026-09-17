#!/usr/bin/env bash
# 기획자에게 보낼 «질문 묶음»을 만든다 — 모든 `_digest.md` 의 «미해결·질문» 절에서 아직 안 풀린 항목만 모은다.
#
# 왜 묶음인가: 기획 질문을 카드 댓글·멘션으로만 남기는 구조였는데 **기획자는 카드를 안 본다.** 2026-09-17 bnsone
#   실측: 질문 카드 5장이 회신 없이 멈춰 있었다. 그래서 질문의 정본을 digest «미해결·질문» 절로 두고(원래 그 절이
#   질문 자리다 — `rules/docs.md` 5항목), **오너가 이 묶음 하나를 기획자에게 전달**한다.
# 왜 `--stale` 인가: 반대 방향 고장도 있다 — 기획자가 원문을 고쳐 **이미 풀어 준 것**을 digest 가 여전히 «미정»으로
#   들고 있다(2026-09-17 bnsone 실측 약 25곳 · AI 오판의 직접 원인). 풀린 질문을 또 보내면 기획자가 묶음을 안 읽게 된다.
#
# 규칙(이 스크립트가 읽는 모양 — 바꾸면 여기도 고쳐라):
#   · 절 = 제목(`## `·`### `)에 «질문» 이 든 절. 다음 같은 급 이상 제목에서 끝난다.
#   · 항목 = 그 절의 맨 앞 `- ` 줄 + 그 밑의 들여쓴 줄.
#   · 뺀다 = 항목 첫 줄에 `해소`·`회신됨`·`확정됨`·`✅`·`~~`(취소선)이 있으면 풀린 것으로 본다(`/docs` 5단계의 «해소 표시»).
#   · `--stale` = 안 풀린 항목의 **식별자**(`W-06`·`CM-32`·`AA3-02` 모양)가 같은 STEP 폴더의 **기획자 원문**에서
#     «확정·해소·반영·정정·개정» 과 **같은 줄**에 나오면 «이미 풀렸을 후보»로 낸다. ⚠️후보다 — 판정은 사람·AI 가
#     그 줄을 읽고 한다(식별자 없는 항목은 이 방법으로 못 본다 — 그 수도 함께 찍는다).
#
# 사용: bash scripts/collect-planner-questions.sh [출력파일]      묶음(기본 = 표준출력)
#       bash scripts/collect-planner-questions.sh --stale        이미 풀렸을 후보 목록
# 종료: 묶음 = 0(0건이어도 «0건»이라고 적는다) · --stale = 0 후보 없음 / 1 후보 있음 · 2 = 판정 불능
set -u

MODE=bundle; OUT=/dev/stdout
case "${1:-}" in
  --stale) MODE=stale ;;
  "") ;;
  *) OUT="$1" ;;
esac

PREFIX=$(git rev-parse --show-prefix 2>/dev/null) || { echo "⛔ 판정 불능 — git 저장소 안이 아니다." >&2; exit 2; }
if [ -n "$PREFIX" ]; then
  echo "⛔ 판정 불능 — repo 루트가 아니라 '$PREFIX' 에서 돌았다. 루트로 옮겨 다시 돌려라." >&2; exit 2
fi
[ -d docs ] || { echo "⛔ 판정 불능 — docs/ 가 없다." >&2; exit 2; }

git -c core.quotepath=false ls-files docs | python3 -c '
import re, sys, os, datetime
# 스크립트가 죽으면 «후보 있음»(1)과 같은 모양이 된다 — 판정 불능(2)으로 가른다(rules/verify.md §1).
sys.excepthook = lambda *a: (sys.__excepthook__(*a), os._exit(2))
mode = sys.argv[1]
tracked = [l.strip() for l in sys.stdin if l.strip()]
digests = sorted(f for f in tracked if os.path.basename(f) == "_digest.md")
done = re.compile(r"해소|회신됨|확정됨|~~|✅")

def open_items(f):
    try:
        lines = open(f, encoding="utf-8").read().split("\n")
    except OSError:
        return []
    items, cur, in_q, qlevel = [], None, False, 0
    for i, line in enumerate(lines, 1):
        h = re.match(r"^(#{1,6})\s", line)
        if h:
            lvl = len(h.group(1))
            if in_q and lvl <= qlevel:
                in_q = False
            if not in_q and "질문" in line:
                in_q, qlevel = True, lvl
            if cur: items.append(cur); cur = None
            continue
        if not in_q:
            continue
        if line.startswith("- "):
            if cur: items.append(cur)
            cur = [i, [line]]
        elif cur and (line.startswith("  ") or line.startswith("\t")):
            cur[1].append(line)
        elif cur and line.strip() == "":
            items.append(cur); cur = None
    if cur: items.append(cur)
    return [it for it in items if not done.search(it[1][0])]

if mode == "bundle":
    out, total = [], 0
    for f in digests:
        its = open_items(f)
        if not its:
            continue
        out.append(f"## {f}  ({len(its)}건)\n")
        for n, body in its:
            out.append(f"<!-- {f}:{n} -->")
            out.extend(body)
            out.append("")
        total += len(its)
    head = ["# 기획 확인 요청 묶음", "",
            f"> 만든 날 {datetime.date.today().isoformat()} · 미회신 {total}건 · 출처 = 각 STEP `_digest.md` «미해결·질문» 절",
            "> 회신은 이 문서에 바로 적어 주시거나 오너에게 전해 주세요. 반영되면 그 항목에 «해소»가 붙고 다음 묶음에서 빠집니다.", ""]
    if total == 0:
        head.append("(미회신 질문 없음)")
    print("\n".join(head + out))
    sys.exit(0)

# --stale
idrx = re.compile(r"(?<![A-Za-z0-9])[A-Z]{1,4}[0-9]?-[A-Z]?[0-9]{1,3}[a-z]?(?![0-9])")
# «결정»은 뺐다 — 업무 문장(「부서원 결정」)과 겹쳐 후보가 부풀었다(bnsone 실측).
solved = re.compile(r"확정|해소|반영|정정|개정")
hits, noid, checked = [], 0, 0
for f in digests:
    step = os.path.dirname(f)
    originals = [t for t in tracked if t.startswith(step + "/") and t.endswith(".md")
                 and not os.path.basename(t).startswith("_")]
    texts = {}
    for o in originals:
        try:
            texts[o] = open(o, encoding="utf-8").read().split("\n")
        except OSError:
            pass
    for n, body in open_items(f):
        checked += 1
        ids = sorted(set(idrx.findall(" ".join(body))))
        if not ids:
            noid += 1
            continue
        for ident in ids:
            # 경계를 둔다 — 맨 부분 문자열이면 `C-1` 이 `C-13` 줄에 걸린다(bnsone 실측).
            exact = re.compile(r"(?<![A-Za-z0-9])" + re.escape(ident) + r"(?![0-9A-Za-z])")
            for o, lines in texts.items():
                for k, line in enumerate(lines, 1):
                    if exact.search(line) and solved.search(line):
                        frag = line.strip()
                        frag = frag[:90] + ("…" if len(frag) > 90 else "")
                        hits.append(f"{f}:{n}  [{ident}]  ← {o}:{k}: {frag}")
                        break
print(f"──── 미해결 항목 {checked}건 검사 · 식별자 없어 못 본 항목 {noid}건 · 이미 풀렸을 후보 {len(hits)}줄")
for h in hits:
    print(h)
if hits:
    print("⛔ 위 후보는 원문이 «확정·해소»를 적은 줄과 식별자가 겹친다. 그 줄을 읽고 풀렸으면 digest 항목에 «해소(→ 원문 위치)»를 붙여라.")
    sys.exit(1)
print("이미 풀렸을 후보 없음 — OK")
' "$MODE" > "$OUT"
