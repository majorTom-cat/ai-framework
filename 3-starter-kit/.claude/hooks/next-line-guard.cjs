#!/usr/bin/env node
// Stop 훅 — 응답 마지막 «▶ 다음:» 줄에 AI 몫 명령(/inspect·/security-review)이 명령 형태로 들어 있으면 AI 에게 되돌려 보낸다.
// 왜 있나: «▶ 다음» 은 사람이 칠 명령 자리라, AI 가 할 화면 검사를 거기 적으면 사람에게 입력을 시키는 것으로 읽힌다.
// CLAUDE.md 글 규칙(«AI 몫 단계는 묻지 말고 실행»)이 긴 세션·압축 뒤에 풀려 재발했다(배포처 bnsone #708 3회 · dev 673 /done 8단계 3회 연속).
// 한 번만 되돌린다(stop_hook_active 면 통과 — 무한 반복 방지). 읽지 못하면 조용히 통과(응답을 막는 훅이 스스로 죽어 세션을 가두면 안 된다).
// 입력 = 공식 훅 문서 Stop: `last_assistant_message`(있으면) → 없으면 `transcript_path` JSONL 의 마지막 assistant 글.
'use strict';

const fs = require('fs');

// AI 몫 명령 — 스킬 본문이 «AI 가 직접 실행»으로 정한 것만. 사람이 고를 명령(/todo·/done·/dev 등)은 넣지 마라.
const AI_ONLY = /(^|[\s`'"(«:·,])\/(inspect|security-review)(?![\w-])/;
const NEXT = /^[\s>*_]*▶\s*다음/;

function lastAssistantText(input) {
  if (typeof input.last_assistant_message === 'string') return input.last_assistant_message;
  if (typeof input.transcript_path !== 'string') return '';
  let lines;
  try { lines = fs.readFileSync(input.transcript_path, 'utf8').split('\n'); } catch (e) { return ''; }
  for (let i = lines.length - 1; i >= 0; i--) {
    let e;
    try { e = JSON.parse(lines[i]); } catch (err) { continue; }
    if (!e || e.type !== 'assistant' || !e.message || !Array.isArray(e.message.content)) continue;
    const text = e.message.content.filter((c) => c && c.type === 'text').map((c) => c.text).join('\n');
    if (text.trim()) return text;
  }
  return '';
}

// 반환: null(통과) | 되돌릴 사유 문자열
function decide(input) {
  if (input.stop_hook_active) return null;
  const lines = lastAssistantText(input).split('\n').map((l) => l.trim()).filter(Boolean);
  const last = lines[lines.length - 1] || '';
  if (!NEXT.test(last)) return null;
  const m = last.match(AI_ONLY);
  if (!m) return null;
  return `마지막 «▶ 다음:» 줄에 AI 몫 명령 /${m[2]} 가 명령 형태로 들어 있다 — 사람에게 입력을 시키는 것으로 읽힌다(CLAUDE.md «스킬 본문이 AI 몫으로 적은 단계는 묻지 말고 실행»). `
    + `지금 실행할 수 있으면 직접 실행하고 결과로 끝내라. 기다리는 중이면 행동 문장으로 고쳐 써라(예: «▶ 다음: 배포가 끝나면 제가 화면 검사를 이어서 합니다 — 기다리시면 됩니다»). 명령 이름을 그 줄에 쓰지 마라.`;
}

let raw = '';
process.stdin.on('data', (c) => { raw += c; });
process.stdin.on('end', () => {
  let input = {};
  try { input = JSON.parse(raw); } catch (e) { process.exit(0); }
  let reason = null;
  try { reason = decide(input); } catch (e) { process.exit(0); }
  if (reason) process.stdout.write(JSON.stringify({ decision: 'block', reason }) + '\n');
  process.exit(0);
});
