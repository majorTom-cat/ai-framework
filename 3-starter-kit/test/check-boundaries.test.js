// check-boundaries.cjs 회귀 테스트 — 갈래3 매트릭스(정상 3·위반 7) + DB 4패턴 + ESM + 순환 (2026-08-07)
// 임시 디렉터리에 픽스처 모듈 구조를 만들고 검사기를 자식 프로세스로 실행해 exit code·출력을 단언한다.
// ★주의: 이 파일 자체가 검사기의 스캔 대상(test/)이다 — 픽스처의 import 구문을 아래 헬퍼로 조립해
//   이 파일 원문에는 require('...')·import ... from '...' 매칭 가능한 문자열이 남지 않게 한다.
const { test } = require('node:test');
const assert = require('node:assert');
const { spawnSync } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const CHECKER = path.join(__dirname, '..', 'scripts', 'check-boundaries.cjs');

// ── 픽스처 조립 헬퍼 — 키워드와 지정자를 분리해 이 파일이 자기 검사에 안 걸리게 한다 ──
const REQ = (s) => 'require(' + JSON.stringify(s) + ')';
const REQT = (s) => 'require(' + '`' + s + '`' + ')'; // 템플릿 리터럴 require(보간 없음)
const DYNIMP = (s) => 'import(' + JSON.stringify(s) + ')';
const IMPFROM = (s) => 'import x from ' + JSON.stringify(s) + ';';
const EXPFROM = (s) => 'export { y } from ' + JSON.stringify(s) + ';';

const POST_SCHEMA = 'model Post {\n  id Int @id\n  @@map("posts")\n}\n';
const STAFF_SCHEMA = 'model Staff {\n  id Int @id\n}\n';

function writeTree(base, files) {
  for (const [rel, content] of Object.entries(files)) {
    const p = path.join(base, rel);
    fs.mkdirSync(path.dirname(p), { recursive: true });
    fs.writeFileSync(p, content);
  }
}

function runChecker(dir) {
  return spawnSync(process.execPath, [CHECKER], { cwd: dir, encoding: 'utf8' });
}

function withFixture(files, fn) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'boundaries-'));
  try {
    writeTree(dir, files);
    return fn(runChecker(dir));
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

// 공용 골격 — board(내부 폴더 보유)·approval 두 모듈
const BASE = {
  'src/modules/board/index.js': 'const db = ' + REQ('../../shared/db.js') + ';\nmodule.exports = { listPosts: () => db.post.findMany() };\n',
  'src/modules/board/store/post-store.js': 'module.exports = { rows: [] };\n',
  'src/modules/board/services/index.js': 'module.exports = {}; // 하위 배럴 — 공개 인터페이스 아님\n',
  'src/shared/db.js': 'const { PrismaClient } = ' + REQ('@prisma/client') + ';\nmodule.exports = new PrismaClient();\n',
  'src/shared/format.js': 'module.exports = { formatDate: (s) => s };\n',
  'prisma/schema/board.prisma': POST_SCHEMA,
  'prisma/schema/hr.prisma': STAFF_SCHEMA,
};

test('정상 케이스 — 자기 하위·형제, 남의 루트 index, shared, 허용목록, 프래그마 전부 통과(오탐 0)', () => {
  withFixture({
    ...BASE,
    // 자기 모듈 형제 폴더 참조(구판 오탐 지점 A) + 자기 하위 참조
    'src/modules/approval/routes/doc-routes.js': 'const svc = ' + REQ('../services/draft-service.js') + ';\n',
    'src/modules/approval/services/draft-service.js': 'const store = ' + REQ('../store/doc-store.js') + ';\n',
    'src/modules/approval/store/doc-store.js': 'module.exports = {};\n',
    // 남의 모듈은 루트 index로만 + shared는 자유
    'src/modules/approval/index.js': 'const board = ' + REQ('../board/index.js') + ';\nconst f = ' + REQ('../../shared/format.js') + ';\nmodule.exports = {};\n',
    // 프래그마 탈출구 — 남의 모델(hr 소유 Staff)이지만 사유 주석과 함께 한시 허용
    'src/modules/approval/legacy.js': 'module.exports = (db) => db.staff.findMany(); // db-boundary-allow: 이관 전 한시 허용\n',
    // 진입점·테스트는 index 경유면 통과 (디렉터리 import = 루트 index)
    'server.js': 'const b = ' + REQ('./src/modules/board/index.js') + ';\nconst a = ' + REQ('./src/modules/approval') + ';\n',
    'test/board.test.js': 'const b = ' + REQ('../src/modules/board/index.js') + ';\n',
    // 오탐 대조군 — 모델명과 겹치는 평범한 프로퍼티(수신자 ui·ctx는 클라이언트풍이 아니다.
    // ctx는 tx$ 접미 매칭의 실측 오탐 지점 — Next 이식 픽스처에서 발견, 낙타등 경계로 수정)
    'src/modules/approval/benign.js': [
      'const ui = { staff: { update: () => 0 } };',
      'module.exports.a = ui.staff.update({});',
      'const ctx = { x: { update: () => 0 } };',
      'const key = "x";',
      'module.exports.b = () => ctx[key].update(1);',
    ].join('\n') + '\n',
  }, (r) => {
    assert.strictEqual(r.status, 0, '정상 구조가 빨간불이면 오탐이다:\n' + r.stderr);
    assert.match(r.stdout, /모듈 경계 OK/);
    // 경고(SCAN_FILES 부재·경계 면제)는 정상 산출물이다 — 위반 줄만 없어야 한다(2026-08-26)
    const stray = r.stderr.split('\n').filter((l) => l.trim() && !/경고\(막지 않음\)|SCAN_FILES 항목|경계 면제|DB 경계 검사 비활성/.test(l));
    assert.deepStrictEqual(stray, [], '정상 구조에서 위반이 없어야 한다(경고 줄은 허용)');
  });
});

test('import 위반 12형태 — 얕은·깊은 상대, 하위 배럴, ESM, .ts, 동적, 템플릿, 별칭, test/, server.js, shared 역전, 재수출', () => {
  withFixture({
    ...BASE,
    'src/modules/approval/store/doc-store.js': 'module.exports = {};\n',
    // 정상 대조군(오탐 검증용) — 형제 폴더·남의 루트 index
    'src/modules/approval/routes/doc-routes.js': 'const svc = ' + REQ('../services/draft-service.js') + ';\n',
    'src/modules/approval/services/draft-service.js': 'const store = ' + REQ('../store/doc-store.js') + ';\n',
    // v1 얕은 상대 + 정상 index import 동거
    'src/modules/approval/index.js': 'const ok = ' + REQ('../board/index.js') + ';\nconst bad = ' + REQ('../board/store/post-store.js') + ';\n',
    // v2 깊은 상대(../../ — 구판 최대 놓침) / v3 하위 배럴(services/index — 루트 index 아님)
    'src/modules/approval/routes/deep.js': 'const a = ' + REQ('../../board/store/post-store.js') + ';\nconst b = ' + REQ('../../board/services/index.js') + ';\n',
    // v4 .mjs 안의 ESM import / v5 .ts 확장자 없는 import / v6 동적 import / v7 템플릿 리터럴 require
    'src/modules/approval/esm.mjs': IMPFROM('../board/store/post-store.js') + '\n',
    'src/modules/approval/util.ts': IMPFROM('../board/store/post-store') + '\n',
    'src/modules/approval/dyn.js': 'const p = ' + DYNIMP('../board/store/post-store.js') + ';\n',
    'src/modules/approval/tpl.js': 'const t = ' + REQT('../board/store/post-store.js') + ';\n',
    // v8 별칭(@/) / v12 재수출(export-from)
    'src/modules/approval/alias.ts': IMPFROM('@/modules/board/store/post-store') + '\n',
    'src/modules/approval/reexport.js': EXPFROM('../board/store/post-store.js') + '\n',
    // v9 테스트가 내부 직접 참조 / v10 진입점이 내부 직접 참조 / v11 shared→모듈(역전 — index라도 금지)
    'test/sneaky.test.js': 'const s = ' + REQ('../src/modules/board/store/post-store.js') + ';\n',
    'server.js': 'const s = ' + REQ('./src/modules/board/store/post-store.js') + ';\n',
    'src/shared/uses-module.js': 'const b = ' + REQ('../modules/board/index.js') + ';\n',
  }, (r) => {
    assert.strictEqual(r.status, 1, '위반 12형태가 있는데 초록불이다:\n' + r.stdout);
    const out = r.stderr;
    for (const mark of ['approval/index.js', 'routes/deep.js', 'esm.mjs', 'util.ts', 'dyn.js', 'tpl.js', 'alias.ts', 'reexport.js', 'sneaky.test.js', 'server.js:', 'uses-module.js']) {
      assert.ok(out.includes(mark), `위반 누락: ${mark}\n${out}`);
    }
    assert.match(out, /의존 방향 역전/, 'shared→모듈은 index여도 역전 위반이어야 한다');
    // 오탐 0: 정상 대조군(형제 폴더 참조·남의 index import)이 위반으로 찍히면 안 된다
    assert.ok(!out.includes('doc-routes.js'), '자기 형제 폴더 참조 오탐:\n' + out);
    assert.ok(!out.includes('draft-service.js:'), '자기 하위 참조 오탐:\n' + out);
    const count = out.split('\n').filter((l) => l.includes('금지') || l.includes('import할 수 없다')).length;
    assert.strictEqual(count, 12, `위반 12건이어야 하는데 ${count}건:\n` + out);
  });
});

test('DB 경계 4패턴 — 남의 모델·생 SQL 테이블·동적 접근·PrismaClient 산개 (자기 소유·허용목록은 통과)', () => {
  withFixture({
    ...BASE, // board/index.js의 db.post.findMany()는 자기 소유(board.prisma) — 통과해야 한다
    'src/modules/approval/index.js': 'module.exports = {};\n',
    // d1 남의 모델 프로퍼티 접근 (Post 소유는 board)
    'src/modules/approval/db1.js': 'const db = ' + REQ('../../shared/db.js') + ';\nmodule.exports = () => db.post.findMany();\n',
    // d2 생 SQL이 남의 테이블(posts)에 접근 / d5 판별 불가 생 SQL은 경고
    'src/modules/approval/db2.js': 'module.exports = (db) => db.$queryRaw' + '`SELECT * FROM posts`' + ';\n',
    'src/modules/approval/db5.js': 'module.exports = (db, sql) => db.$queryRawUnsafe(sql);\n',
    // d3 동적 모델 접근 / d3c 캐스트 꼴(TS — 수신자가 괄호에 가려짐) / d4 모듈 안 new PrismaClient
    'src/modules/approval/db3.js': 'module.exports = (db, model) => db[model].findMany();\n',
    'src/modules/approval/db3c.js': 'module.exports = (db, model) => (db)[model].findMany();\n',
    'src/modules/approval/db4.js': 'const { PrismaClient } = ' + REQ('@prisma/client') + ';\nconst c = new PrismaClient();\n',
  }, (r) => {
    assert.strictEqual(r.status, 1, 'DB 위반 4패턴이 있는데 초록불이다:\n' + r.stdout);
    const out = r.stderr;
    assert.ok(out.includes('db1.js') && out.includes('직접 쿼리'), 'd1 남의 모델 접근 누락:\n' + out);
    assert.ok(out.includes('db2.js') && out.includes("'posts'"), 'd2 생 SQL 테이블 누락:\n' + out);
    assert.ok(out.includes('db3.js') && out.includes('동적 모델 접근'), 'd3 동적 접근 누락:\n' + out);
    assert.ok(out.includes('db3c.js') && out.includes('캐스트 꼴'), 'd3c 캐스트 동적 접근 누락:\n' + out);
    assert.ok(out.includes('db4.js') && out.includes('new PrismaClient()'), 'd4 클라이언트 산개 누락:\n' + out);
    assert.ok(out.includes('db5.js') && out.includes('경고'), 'd5 판별 불가 생 SQL은 경고여야 한다:\n' + out);
    // 오탐 0: 자기 소유 모델 접근(board)·허용목록(shared/db.js)이 위반으로 찍히면 안 된다
    assert.ok(!out.includes('board/index.js'), '자기 소유 모델 접근 오탐:\n' + out);
    assert.ok(!out.includes('shared/db.js:'), '허용목록(shared/db.js) 오탐:\n' + out); // 위치 표기(파일:줄)만 검사 — d4 안내문의 경로 언급과 구분
  });
});

test('순환 의존 — 모듈 index 간 양방향 참조를 DFS로 잡는다', () => {
  withFixture({
    'src/modules/cyc-a/index.js': 'const b = ' + REQ('../cyc-b/index.js') + ';\nmodule.exports = {};\n',
    'src/modules/cyc-b/index.js': 'const a = ' + REQ('../cyc-a/index.js') + ';\nmodule.exports = {};\n',
  }, (r) => {
    assert.strictEqual(r.status, 1, '순환 의존이 있는데 초록불이다:\n' + r.stdout);
    assert.ok(r.stderr.includes('순환 의존'), '순환 의존 보고 누락:\n' + r.stderr);
    assert.match(r.stderr, /cyc-a → cyc-b → cyc-a|cyc-b → cyc-a → cyc-b/, '순환 경로 표기가 없다:\n' + r.stderr);
  });
});
