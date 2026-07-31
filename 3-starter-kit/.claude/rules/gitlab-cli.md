# glab 여러 줄 본문 — Windows 안전 패턴 (실측 사고: bnsone #6)

- 카드·댓글·MR의 **여러 줄 본문을 PowerShell로 `-m`/`-d`에 직접 넘기지 마라** — 개행에서 인자가 쪼개져 `Accepts 1 arg(s), received N`으로 실패한다. `glab api -f body=@파일`도 금지 — gh(GitHub CLI) 전용 문법이라 glab에선 `@경로`가 **문자 그대로 본문에 올라간다**.
- 안전 패턴: 본문을 파일로 쓴 뒤 **Bash에서** `glab issue note {번호} -m "$(cat 파일)"` (issue/mr create의 `-d`도 동일. heredoc `-m "$(cat <<'EOF' … EOF)"`도 가능). **+생성·등록 명령엔 `</dev/null`로 stdin을 닫아라** — Windows에서 glab이 stdin을 물고 **무기한 행**에 걸린다(2026-07-29 실측 2회: 8분+ 행·출력 없음. 프롬프트를 기다리는 게 아니라 그냥 멈춘다). 타임아웃(60~90초)도 함께 걸면 행이 나도 세션이 살아난다.
- 바깥에 남긴 산출물(카드·댓글·MR 본문)은 **등록 직후 API로 재조회**해 본문이 의도대로인지 확인한다 — 무음 실패·깨짐은 조회로만 잡힌다.
