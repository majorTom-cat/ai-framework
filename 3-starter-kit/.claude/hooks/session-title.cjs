#!/usr/bin/env node
// UserPromptSubmit 훅 — `/dev N`·`/fix N`·`/done N` 를 치면 세션 제목을 «dev N» 형태로 붙인다.
// 번호 있는 명령은 어떤 제목이든 덮어쓴다(Orca 자동 제목 «1 3» 과 사람이 지은 제목을 가를 수 없다 — 오너 결정 2026-10-16). 번호 없는 명령은 건드리지 않는다.
// 같은 카드의 뒤 명령(dev 660 → done 660)은 처음 제목을 유지하고, 카드가 다르면 갱신한다.
// 출력 형식 = 공식 훅 문서 UserPromptSubmit `hookSpecificOutput.sessionTitle`.
// Orca 탭 이름: Orca 는 Claude 세션 제목(sessionTitle)과 별개로 첫 프롬프트에서 «Todo»·«Dev 600» 같은 자동 이름을 만들어 상단 탭 바에 쓴다(2026-10-16 실측 Orca 1.4.226).
// Orca 안이면(ORCA_TERMINAL_HANDLE 있음) `orca terminal rename` 으로 탭 이름도 같이 맞춘다 — 직접 지은 이름이라 자동 이름보다 우선한다. 실패해도 조용히 통과(제목은 편의 기능).
'use strict';

const path = require('path');
const { spawn } = require('child_process');

const OURS = /^(dev|fix|done) (\d+)$/;
// 원문(`/dev 660`) 또는 스킬이 펼쳐진 형태(`<command-name>/dev</command-name><command-args>660</command-args>`)
const RAW = /^\s*\/(dev|fix|done)\s+#?(\d+)\b/;
const EXPANDED = /<command-name>\s*\/?(dev|fix|done)\s*<\/command-name>[\s\S]*?<command-args>\s*#?(\d+)\b/;

// 반환: null(건드리지 않음) | {title, emit} — emit=false 면 Claude 세션 제목은 그대로 두고 Orca 탭 이름만 맞춘다(같은 카드의 뒤 명령).
function decide(input) {
  const prompt = typeof input.prompt === 'string' ? input.prompt : '';
  const m = prompt.match(RAW) || prompt.match(EXPANDED);
  if (!m) return null;
  const title = `${m[1]} ${m[2]}`;
  const cur = typeof input.session_title === 'string' ? input.session_title.trim() : '';
  const mine = cur.match(OURS);
  if (mine && mine[2] === m[2]) return { title: cur, emit: false }; // 같은 카드의 뒤 명령 — 처음 제목 유지
  return { title, emit: true }; // 그 밖의 제목(Orca 자동 제목·직접 지은 제목 포함)은 갱신
}

// Orca 탭 이름 맞추기 — 훅을 막지 않게 떼어 내 실행한다(Electron 기동이 느리다). Orca 밖이면 아무것도 안 한다.
function renameOrcaTab(title) {
  const handle = process.env.ORCA_TERMINAL_HANDLE;
  if (!handle) return;
  const dir = process.env.ORCA_CLI_BIN_DIR;
  const bin = dir ? path.join(dir, 'orca') : 'orca';
  try {
    const child = spawn(bin, ['terminal', 'rename', '--terminal', handle, '--title', title], {
      detached: true,
      stdio: 'ignore',
    });
    child.on('error', () => {}); // 설치 안 됨·실행 불가 — 조용히
    child.unref();
  } catch (e) { /* 제목은 편의 기능 */ }
}

let raw = '';
process.stdin.on('data', (c) => { raw += c; });
process.stdin.on('end', () => {
  let input = {};
  try { input = JSON.parse(raw); } catch (e) { process.exit(0); } // 읽지 못하면 조용히 통과(제목은 편의 기능)
  const d = decide(input);
  if (d) {
    if (d.emit) {
      process.stdout.write(JSON.stringify({
        hookSpecificOutput: { hookEventName: 'UserPromptSubmit', sessionTitle: d.title },
      }) + '\n');
    }
    renameOrcaTab(d.title);
  }
  process.exit(0); // 떼어 낸 자식(orca)은 기다리지 않는다 — spawn 은 동기로 이미 떠 있다
});
