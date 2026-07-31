# 동시 두 이슈 = 이슈별 워크트리 — 레시피·주의

> 자동 로드 ❌. CLAUDE.md '세션 규칙'이 가리킨다. 원칙(같은 클론에 세션 둘 금지, 트리마다 자기 포트·DB)은 CLAUDE.md에, 절차는 여기.

## 레시피
1. `git worktree add ../issue-13 -b feature/13-슬러그`
2. 그 폴더에서 `claude -n issue-13`
3. `CLAUDE.local.md`에 이 트리 전용 포트·DB명 기록 (안 그러면 두 세션이 같은 포트·DB를 무음으로 덮어쓴다)
4. 끝나면 `git worktree remove ../issue-13`

## 주의
- **Windows는 최신 Claude Code 필수** — 구버전은 워크트리 삭제 시 링크 대상이 지워지는 버그.
- 새 워크트리는 별도 폴더라 `/todo`·`/dev`·`/fix` 등 스킬이 그 폴더에서 **최초 1회 신뢰 확인**을 물을 수 있다 — "don't ask again for … in {폴더}"를 고르면 그 트리에선 다시 안 묻는다(정상 동작, 막힌 것 아님).
