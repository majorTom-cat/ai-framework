#!/usr/bin/env node
// bundle-guard — 한 Bash 호출에 명령을 여러 개 이으면 **사람에게 창을 띄우는 대신 AI 에게 되돌려 보낸다**(PreToolUse deny).
//
// 왜 있나: 규칙 「한 Bash 호출에 명령을 여러 개 잇지 마라」(rules/gitlab-cli.md)는 **글로만 있었다.**
//   2026-09-10: 킷 세션이 그 규칙을 직접 써 넣은 날, 바로 다음 세션에서 약 12번 묶어 보냈고
//   그중 하나(`rm -rf …; mkdir …; … cd … && bash …`)가 오너 화면에 확인 창을 띄웠다.
//   오너: 「하루에만 몇번이나 규칙을 어기는거지? 규칙을 뭐하러 세우고 수정하고 한건지 후회되네」 → 장치로 바꾼다(오너 「해」).
//
// ★deny 는 **사람에게 아무것도 안 띄운다** — 사유가 AI 에게 돌아가 AI 가 나눠 다시 보낸다. 창(ask)을 늘리는 장치가 아니다.
// ★규칙과 싸우지 않게 예외 셋(규칙이 스스로 시키는 형태):
//   ① 끝의 `; echo "EXIT=$?"` 하나 — rules/verify.md §1 이 시킨다(종료 코드를 눈으로 본다).
//   ② 맨 앞 `cd {폴더} &&` 하나 — 킷 자기시험은 «스크래치패드로 옮긴 뒤 절대경로로» 돌린다(rules/verify.md §3).
//      단 그 뒤가 `git` 이면 되돌린다 — 하네스가 «폴더를 옮긴 뒤 git» 경고 창을 세운다(2026-09-10 실측). `git -C` 로.
//   ③ 파이프는 **뒤 단계가 전부 허용 목록에 있으면** 통과 — 킷 문서 약 24곳이 `| jq`·`| head` 를 권한다.
//      허용 목록에 없는 단계(`cut`·`tr` …)가 끼면 뭉치 전체가 창을 띄우므로 되돌린다(2026-09-10 오너 사진 `| cut -c1-140`).
// 따옴표·`$( )`·백틱·heredoc 본문 «안»의 `&&`·`;`·`|` 는 세지 않는다(한 명령의 인자다).
// 규약: deny 아니면 무음. **이 훅이 스스로 죽으면 무음(통과)** — 장치 결함으로 일을 막지 않는다. 대신 회귀 시험이 지킨다.
// 연결: 킷 저장소 세션(ai-framework/.claude/settings.json) + 배포처(이 폴더의 settings.json → bnsone 등) — 오너 「bnsone에 당연히 되게 해야지」(2026-09-10).
//   matcher 는 Bash 만(PowerShell 은 연산자 규칙이 달라 이 파서로 판정하지 않는다).
'use strict';
const fs = require('fs');
const path = require('path');
const os = require('os');

function splitTop(cmd) {
  const segs = [];
  const ops = [];
  let cur = '';
  let pendingHeredocs = [];
  const n = cmd.length;
  let i = 0;
  const push = (op) => { segs.push(cur.trim()); cur = ''; if (op) ops.push(op); };
  while (i < n) {
    const c = cmd[i];
    if (c === '\\') { cur += cmd.slice(i, i + 2); i += 2; continue; }
    if (c === "'") { const j = cmd.indexOf("'", i + 1); const e = j < 0 ? n : j + 1; cur += cmd.slice(i, e); i = e; continue; }
    if (c === '"') {
      let j = i + 1;
      while (j < n && cmd[j] !== '"') {
        if (cmd[j] === '\\') { j += 2; continue; }
        // 큰따옴표 안의 $( … ) 는 괄호로 건너뛴다 — heredoc 커밋 본문의 따옴표 홀수가 짝을 깨지 않게(2026-09-10 리뷰 재현).
        if (cmd[j] === '$' && cmd[j + 1] === '(') {
          let d = 0;
          for (; j < n; j++) { if (cmd[j] === '(') d++; else if (cmd[j] === ')') { d--; if (d === 0) break; } }
          j++; continue;
        }
        j++;
      }
      cur += cmd.slice(i, j + 1); i = j + 1; continue;
    }
    // 줄 끝 주석(`# …`)은 줄바꿈까지 건너뛴다 — 주석 속 `;` 를 세지 않는다(2026-09-10 리뷰).
    if (c === '#' && (cur === '' || /\s$/.test(cur))) { const e = cmd.indexOf('\n', i); i = e < 0 ? n : e; continue; }
    if (c === '`') { const j = cmd.indexOf('`', i + 1); const e = j < 0 ? n : j + 1; cur += cmd.slice(i, e); i = e; continue; }
    if (c === '$' && cmd[i + 1] === '(') {
      let d = 0; let j = i + 1;
      for (; j < n; j++) { if (cmd[j] === '(') d++; else if (cmd[j] === ')') { d--; if (d === 0) break; } }
      cur += cmd.slice(i, j + 1); i = j + 1; continue;
    }
    if (c === '<' && cmd[i + 1] === '<' && cmd[i + 2] !== '<') {
      const m = /^<<-?\s*(['"]?)([A-Za-z_][A-Za-z0-9_]*)\1/.exec(cmd.slice(i));
      if (m) { pendingHeredocs.push(m[2]); cur += m[0]; i += m[0].length; continue; }
    }
    if (c === '\n') {
      let j = i + 1;
      for (const d of pendingHeredocs) {          // heredoc 본문은 통째로 건너뛴다
        while (j < n) {
          const e = cmd.indexOf('\n', j);
          const line = cmd.slice(j, e < 0 ? n : e);
          j = e < 0 ? n : e + 1;
          if (line.replace(/^\t+/, '').trim() === d) break;
        }
      }
      pendingHeredocs = [];
      push('\n'); i = j; continue;
    }
    if (c === '&' && cmd[i + 1] === '&') { push('&&'); i += 2; continue; }
    if (c === '|' && cmd[i + 1] === '|') { push('||'); i += 2; continue; }
    if (c === '|') { push('|'); i += (cmd[i + 1] === '&' ? 2 : 1); continue; }
    if (c === ';') { push(';'); i++; continue; }
    if (c === '&') {
      const prev = cur.replace(/\s+$/, '').slice(-1);
      if (prev === '>' || prev === '<' || cmd[i + 1] === '>') { cur += c; i++; continue; }   // 2>&1 · &>file
      push('&'); i++; continue;
    }
    cur += c; i++;
  }
  push(null);
  // segs[k] 앞의 연산자 = ops[k-1]. 빈 조각·주석 줄은 버린다.
  const out = [];
  segs.forEach((s, k) => { if (s && !s.startsWith('#')) out.push({ text: s, op: k === 0 ? null : ops[k - 1] }); });
  return out;
}

function firstWord(seg) {
  const toks = seg.replace(/^[({\s!]+/, '').split(/\s+/);
  let k = 0;
  while (k < toks.length && /^[A-Za-z_][A-Za-z0-9_]*=/.test(toks[k])) k++;
  return (toks[k] || '').replace(/^.*\//, '');
}

// 허용 줄을 «줄» 단위로 맞춘다 — 첫 낱말만 보면 `| bash` 가 `Bash(bash scripts/*)` 에, `| docker ps` 가
//   `Bash(docker compose *)` 에 묻어 통과했는데 실제로는 사람 창이 떴다(2026-09-10 리뷰 재현).
//   `X*` = 접두 · `X:*` = 옛 접두 표기 · 별표 없음 = 정확히 일치.
function allowPatterns() {
  const pats = [];
  const proj = process.env.CLAUDE_PROJECT_DIR || process.cwd();
  const files = [
    path.join(os.homedir(), '.claude', 'settings.json'),
    path.join(proj, '.claude', 'settings.json'),
    path.join(proj, '.claude', 'settings.local.json'),
  ];
  for (const f of files) {
    let j; try { j = JSON.parse(fs.readFileSync(f, 'utf8')); } catch { continue; }
    for (const a of ((j.permissions || {}).allow || [])) {
      const m = /^Bash\((.+)\)$/.exec(String(a).trim());
      if (!m) continue;
      const p = m[1].trim();
      if (p.endsWith(':*')) pats.push({ prefix: p.slice(0, -2) });
      else if (p.endsWith('*')) pats.push({ prefix: p.slice(0, -1) });
      else pats.push({ exact: p });
    }
  }
  return pats;
}
const stageOk = (pats, s) => {
  const t = s.trim();
  return pats.some((p) => (p.exact !== undefined ? t === p.exact : (t.startsWith(p.prefix) || t === p.prefix.trim())));
};

const deny = (why) => {
  process.stdout.write(JSON.stringify({ hookSpecificOutput: {
    hookEventName: 'PreToolUse', permissionDecision: 'deny',
    permissionDecisionReason: `⛔ 되돌려 보냄(사람에게는 창이 안 떴다 — 사람에게 묻지 말고 네가 나눠라): ${why} ` +
      '규칙 = rules/gitlab-cli.md «한 Bash 호출에 명령을 여러 개 잇지 마라». 서로 기다릴 필요가 없으면 같은 응답에 도구 호출을 여러 개 병렬로 보내라. ' +
      '꼭 여러 줄이면 Write 도구로 스크립트 파일을 만들어 `bash 그파일` 하나로. 예외 = 끝의 `; echo "EXIT=$?"` 하나 · 맨 앞 `cd 폴더 &&` 하나(뒤가 git 이 아닐 때) · 뒤 단계가 전부 허용 목록에 있는 파이프.',
  } }) + '\n');
  process.exit(0);
};

try {
  let input = '';
  try { input = fs.readFileSync(0, 'utf8'); } catch { process.exit(0); }
  let cmd;
  try { cmd = JSON.parse(input).tool_input.command; } catch { process.exit(0); }
  if (typeof cmd !== 'string' || !cmd.trim()) process.exit(0);

  let parts = splitTop(cmd);
  const preview = cmd.replace(/\s+/g, ' ').slice(0, 120);

  // 예외 ① 끝의 `; echo "EXIT=$?"`
  if (parts.length > 1) {
    const last = parts[parts.length - 1];
    // `echo "EXIT=$?"` · `echo 'EXIT='$?` · `echo "exit: $?"` — 종료 코드를 찍는 echo 면 모양을 가리지 않는다(2026-09-10 리뷰).
    if ((last.op === ';' || last.op === '\n') && /^echo\b.*\$\?/.test(last.text)) parts = parts.slice(0, -1);
  }
  // 예외 ② 맨 앞 `cd 폴더 &&` — 뒤가 git 이면 되돌린다
  if (parts.length > 1 && firstWord(parts[0].text) === 'cd' && parts[1].op === '&&') {
    if (firstWord(parts[1].text) === 'git') deny(`\`cd … && git …\` 은 하네스가 «폴더를 옮긴 뒤 git» 경고 창을 세운다 — \`git -C {폴더} …\` 로 보내라. [${preview}]`);
    parts = parts.slice(1);
  }
  if (parts.length <= 1) process.exit(0);

  // 파이프로만 이어졌나? 아니면 명령 여러 개다.
  const chained = parts.slice(1).filter((p) => p.op !== '|');
  if (chained.length > 0) deny(`한 호출에 명령 ${chained.length + 1}개를 이었다(\`&&\`·\`;\`·\`||\`·줄바꿈·\`&\`). [${preview}]`);

  // 예외 ③ 파이프 — 뒤 단계가 전부 허용 줄에 맞아야 한다(목록을 못 읽으면 판정하지 않는다).
  //   ★첫 단계는 안 본다 — 그게 허용 밖이면 나눠 보내도 똑같이 창이 뜬다(묶음 탓이 아니라 이 장치 몫이 아니다).
  const pats = allowPatterns();
  if (pats.length === 0) process.exit(0);
  const missing = [...new Set(parts.slice(1).filter((p) => !stageOk(pats, p.text)).map((p) => firstWord(p.text) || p.text))];
  if (missing.length) deny(`파이프 뒤 단계 \`${missing.join('`·`')}\` 가 허용 목록에 없어 뭉치 전체가 확인 창을 띄운다 — 그 단계를 빼거나, 출력을 스크래치 파일로 받은 뒤(\`>\`) 따로 걸러라. [${preview}]`);
  process.exit(0);
} catch {
  process.exit(0);
}
