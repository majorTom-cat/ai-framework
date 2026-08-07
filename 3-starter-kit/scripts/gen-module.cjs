// 모듈 생성기 — 본보기(src/modules/<본보기모듈>) 구조를 이름 치환해 찍는다 (/module 스킬 1단계 전용)
// 사용: npm run gen:module <모듈이름>   (이름 = 소문자 한 단어, 예: board)
// 카드 #67 (Day 6 — 본보기 모듈 + 생성기)
const fs = require('fs');
const path = require('path');

const name = process.argv[2];

function fail(msg) {
  console.error(`❌ ${msg}`);
  process.exit(1);
}

if (!name) fail('모듈 이름이 없다. 사용법: npm run gen:module <모듈이름>');
if (!/^[a-z][a-z0-9-]*$/.test(name)) {
  fail(`모듈 이름은 소문자 한 단어(하이픈 허용)여야 한다: "${name}" 불가 (예: board, work-log)`);
}

// board → Board, work-log → WorkLog (함수 이름용)
const pascal = name
  .split('-')
  .map((w) => w[0].toUpperCase() + w.slice(1))
  .join('');

const moduleDir = path.join('src', 'modules', name);
const indexFile = path.join(moduleDir, 'index.js');
const testFile = path.join('test', `${name}.test.js`);

// 이미 있는 모듈은 절대 덮어쓰지 않는다 (남의 모듈이 날아간다 — /module 0단계와 이중 방어)
// 예외: "아직 생성 전" 예약 폴더(README류만 있는 폴더)는 비우고 진행
if (fs.existsSync(moduleDir)) {
  const entries = fs.readdirSync(moduleDir);
  const onlyReadme = entries.every((e) => /^readme/i.test(e));
  if (!onlyReadme) fail(`src/modules/${name} 가 이미 있다 — 덮어쓰기 금지. 재생성은 소유자 확인 후에만.`);
  for (const e of entries) fs.rmSync(path.join(moduleDir, e));
  console.log(`ℹ 예약 폴더의 README를 지웠다: src/modules/${name}`);
}
if (fs.existsSync(testFile)) fail(`test/${name}.test.js 가 이미 있다 — 덮어쓰기 금지.`);

const indexSrc = `// [팀 규칙] 이 모듈은 index.js만 외부에 공개한다 (공개 인터페이스)
// [팀 규칙] 구현 패턴은 본보기 모듈(src/modules/<본보기모듈>)을 따른다 — 벗어나면 이유를 카드 댓글로
// ${name} — <이 모듈이 무엇을 하는지 한 줄로 채워라>
const { formatDate } = require('../../shared/format.js');

const store = [];

function add${pascal}(text) {
  if (!text || !text.trim()) throw new Error('${name} 내용은 비어 있을 수 없다');
  const item = { id: store.length + 1, text: text.trim(), createdAt: formatDate(new Date().toISOString()) };
  store.push(item);
  return item;
}

function list${pascal}s() {
  // 최신순(id 내림차순) — 본보기(<본보기모듈>)와 같은 기본 정렬
  return store.slice().sort((a, b) => b.id - a.id);
}

module.exports = { add${pascal}, list${pascal}s };
`;

// stub 테스트는 CRUD 이름을 못 박지 않는다 — 이름을 박으면 실제 API로 바꾸는 순간 깨져 생성 즉시
// 폐기된다(2026-08-06 approval 규모 실험 실측: 'addApproval is not a function'). 공개 API를 이름
// 비고정으로 1개 호출하는 형태라, 요구에 맞춰 index를 갈아엎어도 살아남는다.
const testSrc = `// [팀 규칙] 테스트는 모듈의 공개 인터페이스(index)만 부른다 — 본보기: test/<본보기모듈>.test.js
// 이 파일은 생성기 stub이다 — 요구가 정해지면 실제 동작 테스트를 여기에 추가하라(본보기: test/<본보기모듈>.test.js).
const { test } = require('node:test');
const assert = require('node:assert');
const api = require('../src/modules/${name}/index.js');

test('${name}: index가 공개 API를 노출하고, 하나는 호출 가능하다', () => {
  const fns = Object.entries(api).filter(([, v]) => typeof v === 'function');
  assert.ok(fns.length >= 1, 'index.js는 공개 함수를 최소 1개 export해야 한다');
  const [fnName, fn] = fns[0];
  try {
    fn(); // 인자 없는 호출 — 성공하거나, 입력 검증이 제대로 된 Error를 던지면 합격
  } catch (e) {
    assert.ok(e instanceof Error, \`\${fnName}() 호출이 Error 아닌 값을 던졌다\`);
  }
});
`;

fs.mkdirSync(moduleDir, { recursive: true });
fs.writeFileSync(indexFile, indexSrc);
fs.writeFileSync(testFile, testSrc);

console.log(`✅ 모듈 "${name}" 생성 완료 (본보기 구조):`);
console.log(`   - ${indexFile}  (공개 인터페이스 — add${pascal}/list${pascal}s)`);
console.log(`   - ${testFile}  (node --test)`);
console.log('다음: 파일 상단 [팀 규칙] 주석 확인 → .claude/rules/module-*.md 생성 → /dev {첫 카드번호} (커밋은 /dev가 담는다)');
