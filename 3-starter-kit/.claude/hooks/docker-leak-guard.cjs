#!/usr/bin/env node
// docker-leak-guard — 이름 없는 도커 볼륨을 남기는 두 모양을 **사람에게 창을 띄우는 대신 AI 에게 되돌려 보낸다**(PreToolUse deny).
//
// 왜 있나: 이미지가 선언한 경로(postgres 의 데이터 폴더 등)는 `-v` 를 안 주면 **이름 없는 볼륨**이 생기고,
//   `docker rm -f` 는 그것을 지우지 않는다. 시험·확인으로 `docker run` 을 즉석에서 띄울 때마다 약 48MB 가 맥에 쌓였다
//   (2026-10-29 맥 56개 · 킷 이슈 #9 · rules/verify.md 의 «시험용으로 띄운 컨테이너는 볼륨까지 치워라» 절이 글로만 있었다).
// 되돌리는 모양 둘:
//   ① `docker run` 인데 `--rm` 도 볼륨 지정(`-v`·`--volume`·`--mount`)도 없다 → `--rm` 을 붙이거나 이름 있는 볼륨을 줘라.
//   ② `docker rm -f`(`--force`) 인데 `-v`(`--volumes`) 가 없다 → `docker rm -fv`.
// ★deny 는 사람에게 아무것도 안 띄운다 — 사유가 AI 에게 돌아가 AI 가 고쳐 다시 보낸다. 창(ask)을 늘리는 장치가 아니다.
// ★삭제는 하지 않는다 — 이미 쌓인 볼륨을 치우는 장치는 일부러 안 만들었다(주인을 이름으로 못 가린다 · 오너 결정 사항).
// 보는 자리: 명령 «위치»에 있는 `docker`(앞에 `sudo`·`xargs`·`env`·`FOO=1` 등이 와도 본다) + `$( … )`·백틱 안쪽.
//   따옴표·heredoc 본문 «안»의 `docker run` 글자는 보지 않는다(커밋 메시지·echo 를 막지 않게).
// ★알려진 구멍(통과해 버린다 — 시험은 이 목록을 «사실»로 적는다): `bash -c '…docker run…'`(따옴표 안 — 이 킷은 bash -c 를 금하지만 훅이 막지는 않는다) ·
//   `xargs -I {} docker rm -f {}`(`{}` 앞 공백형) · 설정파일/별칭으로 감싼 docker · `docker run` 뒤 컨테이너 명령 인자에 든 `-v` 는 볼륨 지정으로 오인해 통과.
//   단 `docker rm`(−f 없음) 과 `docker compose` 는 이 훅의 대상이 아니다.
// 규약: deny 아니면 무음. **이 훅이 스스로 죽으면 무음(통과)** — 장치 결함으로 일을 막지 않는다. 대신 회귀 시험이 지킨다.
// 파서는 bundle-guard.cjs 의 splitTop 을 빌린다 — 두 파일은 같이 배포된다.
'use strict';
const fs = require('fs');
const { splitTop } = require('./bundle-guard.cjs');

const WRAP = new Set(['sudo', 'command', 'xargs', 'exec', 'time', 'env', 'nohup', 'builtin', 'timeout', 'nice']);
// 제어문 키워드 뒤의 명령(`then docker run …` · `do docker rm -f …`)도 명령 자리다.
const CTRL = new Set(['if', 'then', 'else', 'elif', 'do', 'while', 'until']);
const ASSIGN = /^[A-Za-z_][A-Za-z0-9_]*=/;
const base = (s) => (s || '').replace(/^.*\//, '');

// `$( … )` 와 백틱 안쪽 문자열(한 겹) — `ID=$(docker run -d …)` 같은 모양을 놓치지 않으려고.
function inner(text) {
  const out = [];
  for (let i = 0; i < text.length; i++) {
    if (text[i] === '$' && text[i + 1] === '(') {
      let d = 0; let j = i + 1;
      for (; j < text.length; j++) { if (text[j] === '(') d++; else if (text[j] === ')') { d--; if (d === 0) break; } }
      out.push(text.slice(i + 2, j)); i = j;
    } else if (text[i] === '`') {
      const j = text.indexOf('`', i + 1);
      if (j < 0) break;
      out.push(text.slice(i + 1, j)); i = j;
    }
  }
  return out;
}

// 한 조각이 되돌릴 모양이면 «사유 키», 아니면 null.
function judge(seg) {
  const t = seg.replace(/^[({\s!]+/, '').split(/\s+/).filter(Boolean).map((x) => x.replace(/\\$/, ''));
  let k = 0;
  while (k < t.length && (CTRL.has(t[k]) || t[k] === '!')) k++;
  while (k < t.length && ASSIGN.test(t[k])) k++;
  while (k < t.length && WRAP.has(base(t[k]))) {
    k++;
    while (k < t.length && (t[k].startsWith('-') || ASSIGN.test(t[k]) || /^\d+$/.test(t[k]))) k++;
  }
  if (base(t[k]) !== 'docker') return null;
  k++;
  while (k < t.length && t[k].startsWith('-')) k += /^(-H|--host|--context|-c|--config|-l|--log-level)$/.test(t[k]) ? 2 : 1;
  let sub = t[k];
  if (sub === 'container') { k++; sub = t[k]; }
  const args = t.slice(k + 1);

  if (sub === 'run') {
    const hasRm = args.some((a) => a === '--rm' || a === '--rm=true');
    const hasVol = args.some((a) => /^--volume(=|$)|^--volumes-from/.test(a) || a === '--mount' || a.startsWith('--mount=')
      || (/^-[A-Za-z]+(=|$)/.test(a) && a.slice(1).split('=')[0].includes('v')));
    return hasRm || hasVol ? null : 'run';
  }
  if (sub === 'rm') {
    const flag = (re, ch) => args.some((a) => re.test(a) || (/^-[A-Za-z]+$/.test(a) && a.includes(ch)));
    const force = flag(/^--force$/, 'f');
    const vol = flag(/^--volumes$/, 'v');
    return force && !vol ? 'rm' : null;
  }
  return null;
}

function scan(cmd, depth) {
  for (const p of splitTop(cmd)) {
    const r = judge(p.text);
    if (r) return r;
    if (depth < 4) for (const s of inner(p.text)) { const q = scan(s, depth + 1); if (q) return q; }
  }
  return null;
}

const deny = (why, preview) => {
  process.stdout.write(JSON.stringify({ hookSpecificOutput: {
    hookEventName: 'PreToolUse', permissionDecision: 'deny',
    permissionDecisionReason: `⛔ 되돌려 보냄(사람에게는 창이 안 떴다 — 사람에게 묻지 말고 네가 고쳐 다시 보내라): ${why} [${preview}] ` +
      '규칙 = rules/verify.md 의 «시험용으로 띄운 컨테이너는 볼륨까지 치워라» 절(절 번호는 배포처마다 다르다). 이미 쌓인 볼륨을 지우는 건 이 훅의 일이 아니다 — 주인을 이름으로 못 가리니 지우지 말고 사람에게 알려라.',
  } }) + '\n');
  process.exit(0);
};

try {
  let input = '';
  try { input = fs.readFileSync(0, 'utf8'); } catch { process.exit(0); }
  let cmd;
  try { cmd = JSON.parse(input).tool_input.command; } catch { process.exit(0); }
  if (typeof cmd !== 'string' || !cmd.trim()) process.exit(0);
  const preview = cmd.replace(/\s+/g, ' ').slice(0, 120);
  const r = scan(cmd, 0);
  if (r === 'run') deny('`docker run` 에 `--rm` 도 `-v` 도 없다 — 이미지가 선언한 경로마다 이름 없는 볼륨이 생겨 컨테이너를 지워도 남는다. 시험용이면 `--rm` 을, 남길 데이터면 `-v 이름:경로` 를 줘라.', preview);
  if (r === 'rm') deny('`docker rm -f` 에 `-v` 가 없다 — 컨테이너만 지우고 이름 없는 볼륨은 남는다. `docker rm -fv` 로 보내라.', preview);
  process.exit(0);
} catch {
  process.exit(0);
}
