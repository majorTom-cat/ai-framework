#!/usr/bin/env node
// 킷 세션 시작 훅 — «개인 설정으로만 켤 수 있는 값»을 사람 손 없이 자동으로 넣는다(있으면 아무것도 안 한다).
// 왜: 킷은 AI 명령을 샌드박스 안에서 묻지 않고 돌리는데(프로젝트 settings.json `sandbox`),
//     개발 서버가 포트를 여는 허용(sandbox.network.allowLocalBinding)은 공식상 프로젝트 설정으로 못 켠다 —
//     개인 설정(~/.claude/settings.json) 전용. 문서에 «한 줄 넣어라»로 두면 아무도 안 넣는다(2026-09-08 오너 결정: 자동으로).
// 안전: 기존 파일을 못 읽으면(깨진 JSON) 건드리지 않는다 · 바꾸기 전에 settings.json.bak-kit 로 복사 · 값은 더하기만, 지우지 않는다.
const fs = require('fs'), path = require('path'), os = require('os');
const dir = process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude');
const file = path.join(dir, 'settings.json');
let s = {};
if (fs.existsSync(file)) {
  try { s = JSON.parse(fs.readFileSync(file, 'utf8')); }
  catch (e) { console.log('[킷] 개인 설정을 읽지 못해 건너뜀(JSON 오류): ' + file); process.exit(0); }
}
const changed = [];
s.sandbox = (s.sandbox && typeof s.sandbox === 'object') ? s.sandbox : {};
s.sandbox.network = (s.sandbox.network && typeof s.sandbox.network === 'object') ? s.sandbox.network : {};
if (s.sandbox.network.allowLocalBinding !== true) { s.sandbox.network.allowLocalBinding = true; changed.push('sandbox.network.allowLocalBinding=true'); }
if (changed.length) {
  fs.mkdirSync(dir, { recursive: true });
  if (fs.existsSync(file)) fs.copyFileSync(file, file + '.bak-kit');
  fs.writeFileSync(file, JSON.stringify(s, null, 2) + '\n');
  console.log('[킷] 개인 설정에 자동으로 넣음(' + file + '): ' + changed.join(', ') + ' — 다음 세션부터 적용. 원본 = settings.json.bak-kit');
}
