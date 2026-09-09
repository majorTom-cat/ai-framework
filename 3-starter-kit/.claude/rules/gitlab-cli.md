# glab 여러 줄 본문 — Windows 안전 패턴 (실측 사고: bnsone #6)

- 카드·댓글·MR의 **여러 줄 본문을 PowerShell로 `-m`/`-d`에 직접 넘기지 마라** — 개행에서 인자가 쪼개져 `Accepts 1 arg(s), received N`으로 실패한다. `glab api -f body=@파일`도 금지 — gh(GitHub CLI) 전용 문법이라 glab에선 `@경로`가 **문자 그대로 본문에 올라간다**.
- 안전 패턴: 본문을 파일로 쓴 뒤 **Bash에서** `glab issue note {번호} -m "$(cat 파일)"` (issue/mr create의 `-d`도 동일. heredoc `-m "$(cat <<'EOF' … EOF)"`도 가능). **+생성·등록 명령엔 `</dev/null`로 stdin을 닫아라** — Windows에서 glab이 stdin을 물고 **무기한 행**에 걸린다(2026-07-29 실측 2회: 8분+ 행·출력 없음. 프롬프트를 기다리는 게 아니라 그냥 멈춘다). 타임아웃(60~90초)도 함께 걸면 행이 나도 세션이 살아난다.
- ⚠️**그 타임아웃은 macOS 에서 못 건다** — `timeout` 은 GNU coreutils 라 mac 에 기본 미설치다(`command not found` — 2026-09-01 bnsone 실측). `gtimeout`(coreutils 설치 시)을 쓰거나 **`</dev/null` 만으로** 간다. mac 에서 이 방어는 선택이다 — **행(hang) 사고는 Windows 에서 관측됐다.**
- **루프·배치 안의 glab 호출에도 `</dev/null`을 하나씩 다 붙여라** — 2026-08-04 실측: 루프에서 빠뜨린 `glab mr create` 2건이 출력 한 줄 없이 무음 실패(브랜치만 올라가고 MR 없음 — 루프는 에러도 안 보여준다).
- ★**이슈 본문(description) 갱신엔 위 수법이 안 통한다** — `-d`·`--description` 은 개행에서 잘려 «at least one parameter…» 로 무시되고, `glab api --field "description=…"` 는 **본문을 빈 값으로 덮어써 카드를 손상**시킨다(2026-09-01 bnsone 실측 — 복구함).
- 되는 형태 하나: `{"description": 본문}` JSON 파일 → `glab api --method PUT "projects/:id/issues/{번호}" -H "Content-Type: application/json" --input {파일} </dev/null`. ⚠️**PUT 은 통째로 갈아치운다 — 현재 본문을 받아 고친 «전체»를 넣어라.**
- ⚠️**도구가 권하는 «새 형식»을 그대로 따르지 마라** — `glab issue note -m` 이 deprecation 경고로 `note create` 를 권하는데 **그 형식은 여러 줄 본문에서 깨진다**(`Accepts 1 arg(s), received 2` — 위 줄이 경고하는 그 실패 모드다). 경고는 경고일 뿐 **위 안전 패턴이 정본**이다(2026-08-31 bnsone 실측).
- 바깥에 남긴 산출물(카드·댓글·MR 본문)은 **등록 직후 API로 재조회**해 본문이 의도대로인지 확인한다 — 무음 실패·깨짐은 조회로만 잡힌다.
- ★**`glab` 을 `for`·`while` 반복문 안에 넣지 마라** — 반복문은 울타리 밖 목록(`sandbox.excludedCommands`)에 안 걸려 통째로 샌드박스 안에서 돌고, `glab` 은 Go CLI 라 macOS Seatbelt 에서 인증서 검증이 깨진다(`OSStatus -26276` — 공식 문서가 아는 제약). **줄을 나눠 한 줄에 하나씩** 써라. 파이프·`;` 로 이은 것은 첫 낱말이 `glab` 이면 괜찮다(2026-09-09 실측 4형태). ★**나눌 수 없으면 `bash -c '…'` 로 감싸라** — 첫 낱말이 `bash` 라 목록에 걸린다. 이건 `glab` 만의 이야기가 아니다: `cd`·`export`·`for` 로 시작하는 모든 이어붙인 명령이 같은 이유로 울타리에 갇히고, 그때마다 사람에게 확인 창이 뜬다(루트 `CLAUDE.md` 울타리 절).
