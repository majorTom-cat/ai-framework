# main 오염 복구 — revert 레시피 (2026-08-06 파일럿 사본 리허설 실증)

> **킷 주의 — 값 스택별**: 레시피 **A는 스택 무관**(그대로 쓴다). **B는 Prisma 폴더형 예시**다 — 경로(`prisma/schema/migrations`)·역DDL 형태는 프로젝트의 마이그레이션 도구 것으로 치환하라. 원리(파일 복원 + 앞으로 가는 새 마이그레이션)는 도구 무관이다.

> 자동 로드 ❌. CLAUDE.md '금지' 절이 이 파일을 직접 가리키고, '스키마·데이터' 절은 `rules/migrations.md`(규칙 정본)를 거쳐 온다. 규칙 명령문은 그쪽에, 절차·근거는 여기.

## 왜 이 문서가 있나

main에 잘못된 것이 머지됐을 때 쓸 절차가 어디에도 없었고, **실전 main의 `git revert` 커밋은 0건**이다(2026-08-06 `git log --grep=Revert origin/main` 실측 — 아무도 해 본 적이 없다). 사고 순간에 감으로 하면 ①force push·`reset --hard`로 이력을 파괴하거나 ②되돌린 기능을 나중에 재머지했는데 **무충돌·무음으로 되살아나지 않는** 함정에 빠진다. 아래 A·B는 사본 clone에서 끝까지 실행해 확인한 절차다(원본 repo·원격 무수정).

**공통 전제**: main 직접 push 금지 — 되돌리기도 **브랜치 + MR**로 한다. `git revert`는 이력을 지우지 않고 "되돌리는 커밋"을 얹으므로 무엇을 왜 되돌렸는지가 남는다. force push·`reset --hard`는 어떤 경우에도 쓰지 않는다(되돌린 것을 되돌릴 수단까지 없어진다).

## A. 일반 머지 사고 (코드만 — 마이그레이션 없음)

1. `git fetch origin` → `git checkout -b fix/{카드}-revert origin/main`(호출을 나눠서)
2. `git revert -m 1 --no-edit <머지커밋>`
   — **`-m 1`이 없으면 실패한다**: `error: commit … is a merge but no -m option was given` / `fatal: revert failed`(exit 128, 실측). `-m 1` = "머지된 쪽이 아니라 main 쪽 부모를 남긴다".
3. `npm test` + 화면 확인 → MR(본문에 `관련: #카드`, `Closes` 금지) → 머지. 사고 경위와 되돌린 커밋 해시를 카드 댓글로 남긴다.
4. ★**되돌린 브랜치를 나중에 다시 살릴 때는, 재머지 *전에* `git revert <2단계에서 만든 revert 커밋>`을 먼저** 한다.
   - 순서를 어기고 그냥 재머지하면: 되돌린 파일을 브랜치가 다시 수정한 경우엔 `CONFLICT (modify/delete)`로 눈에 보이지만, **브랜치가 다른 파일만 건드렸으면 머지가 exit 0 무충돌로 성공하면서 원래 기능 파일은 그대로 부재**다(실측 n=2 경로). 실전의 "머지했는데 기능이 없다"가 이 경로다.
   - 이미 그렇게 잃었으면 사후 복구도 같은 명령이다: `git revert --no-edit <revert 커밋>` (git 2.50은 커밋 제목을 `Reapply "Merge branch …"`로 만든다 — 이 제목이 보이면 정상).

## B. 마이그레이션이 포함된 머지 (Prisma 예시 — 경로·명령은 스택 치환)

표준 `git revert -m 1`을 그대로 커밋하지 마라 — **머지된 마이그레이션 파일을 삭제한다**(실측: `delete mode 100644 prisma/schema/migrations/…/migration.sql`). 이는 '머지된 마이그레이션은 불변' 규칙과 정면 충돌하고, 이미 적용된 DB와 폴더가 어긋난다. 이 삭제는 2026-08-07 도입한 `migration-immutable` 잡(차단형)이 MR 파이프라인에서 잡는다 — 단 실 파이프라인 첫 발동은 미확인이니(§알려진 구멍) 빨간불에 기대지 말고 아래 2단계를 지켜라. 잡 도입 전(2026-08-06)엔 무검출이 실측됐다.

1. `git revert -m 1 --no-commit <머지커밋>` — 커밋하지 않고 워킹트리만 되돌린다
2. `git checkout <머지커밋> -- prisma/schema/migrations/<되돌릴폴더>` — 지워진 마이그레이션 파일을 원상 복원(**불변 유지**)
3. `prisma/schema/migrations/<YYYYMMDD_HHMMSS>_revert_<원이름>/migration.sql`에 **역DDL을 새로 쓴다** — 멱등·존재검사 형태(`ALTER TABLE "X" DROP COLUMN IF EXISTS "y";`). 되돌리기는 down이 아니라 "앞으로 가는 새 마이그레이션"이다
4. 선언형 스키마(`*.prisma`)는 1단계의 revert 결과를 그대로 두거나 전진 편집으로 정리한다 — 스키마 파일과 마이그레이션이 같은 방향을 가리켜야 한다
5. 커밋 메시지 `#카드 롤백 — 되돌리는 새 마이그레이션` → MR은 **고위험(DB 마이그레이션)** = 경고 레인: AI 경고 리뷰 + 증적 3종 후 `셀프승인` 라벨을 붙이고 **새 파이프라인**을 돌린다(절차 = `/done` `함정.md` §2-b). 그러면 `high-risk-gate` 가 ▶ 없이 통과한다 — 단 `.claude/**` 같은 되돌리기 어려운 경로는 여전히 사람이 ▶ 를 누른다. push 때 훅이 공통 영역 ask를 낸다(정상 동작이다 — 내용 확인 후 진행)
6. 검증: `npm test` 통과 확인 + 되돌린 폴더가 **남아 있고** 새 revert 폴더가 **추가됐는지** `git show --stat`으로 눈으로 본다(실측 결과: 2 files changed, +3/-2 — 삭제 0)

## 알려진 구멍 (이 절차를 믿기 전에 알 것)

- **force push의 기계 방어선은 훅 ask까지다**: settings deny는 명령 접두 기준이라 체이닝을 못 본다(실측). 2026-08-07 훅 확장으로 체이닝(`&& git push -f`)·`git -C`·전역옵션(`-c`·`--git-dir`) 변형에 **ask**가 뜬다 — 단 ask는 하드 차단이 아니고, auto/bypass 세션 훅은 미보장. 경위 `_reference/push-guard.md`.
- ~~머지된 마이그레이션의 삭제·수정을 감지하는 CI 검사가 없다~~ → 2026-08-07 `migration-immutable` 잡(차단형, `--diff-filter=DMR`) 도입 — B의 2단계를 빠뜨리면 이제 MR 파이프라인이 빨간불이다. 단 실 파이프라인 첫 발동은 미확인.
- 로컬에 `git push origin main`(main 직접 push)을 막는 장치가 없다 — 서버측 Protected branch(직접 push·force push 금지)로 걸어야 한다.
- **미검증**: Prisma의 실제 드리프트 에러 문구(사본에 DB 미기동 — "폴더에 없는 마이그레이션이 적용돼 있으면 실패한다"는 인과는 파일 삭제까지만 실증), 여러 MR이 얽힌 상태의 revert(리허설은 단일 머지 n=1씩), 권한 시스템이 체이닝 명령을 어떻게 평가하는지.
