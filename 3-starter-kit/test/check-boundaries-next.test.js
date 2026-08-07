// check-boundaries-next.cjs 회귀 테스트 — Next.js(App Router) 매트릭스
// 정상·오탐 7계열(전부 통과해야) + 위반 11형태(전부 검출해야) + 순환 + 공용 테이블(PUBLIC_OWNERS)
const { test } = require('node:test');
const assert = require('node:assert');
const { spawnSync } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const CHECKER = path.join(__dirname, "..", "scripts", "check-boundaries-next.cjs");

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
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'bnext-'));
  try { writeTree(dir, files); return fn(runChecker(dir)); }
  finally { fs.rmSync(dir, { recursive: true, force: true }); }
}

// bnsone 축소 골격: boards·people 모듈 + shared 공용 테이블 + App Router
const BASE = {
  'src/modules/boards/index.ts': "import { db } from '../../shared/db';\nexport const listBoards = () => db.board.findMany();\n",
  'src/modules/boards/store/board-store.ts': 'export const rows: number[] = [];\n',
  'src/modules/people/index.ts': "import { db } from '../../shared/db';\nexport const listEmployees = () => db.employee.findMany();\nexport type Person = { id: number };\n",
  'src/modules/people/services/hr.ts': 'export const hr = 1;\n',
  'src/shared/db.ts': "import { PrismaClient } from '@prisma/client';\nexport const db = new PrismaClient();\n",
  'src/shared/format.ts': 'export const fmt = (s: string) => s;\n',
  'prisma/schema/boards.prisma': 'model Board {\n  id Int @id\n  @@map("boards")\n}\n',
  'prisma/schema/people.prisma': 'model Employee {\n  id Int @id\n  @@map("employees")\n}\nmodel Department {\n  id Int @id\n}\n',
  'prisma/schema/shared.prisma': 'model Setting {\n  id Int @id\n}\n',
  'middleware.ts': "export const config = { matcher: ['/((?!_next).*)'] };\n",
};

test('정상·오탐 계열 — App Router·별칭·type import·공용 테이블·적대 입력 전부 통과 (오탐 0)', () => {
  withFixture({
    ...BASE,
    // N1 route.ts가 모듈 루트 index를 별칭으로
    'src/app/api/boards/route.ts': "import { listBoards } from '@/modules/boards';\nexport async function GET() { return Response.json(listBoards()); }\n",
    // N2 자기 모듈 하위·형제 참조
    'src/modules/boards/services/svc.ts': "import { rows } from '../store/board-store';\nexport const n = rows.length;\n",
    // N3 남의 모듈 '루트 index'의 type import — 허용
    'src/app/people/page.tsx': "import type { Person } from '@/modules/people';\nexport default function P(){ return null as unknown as Person; }\n",
    // N4 공용 테이블(shared.prisma) 접근 — PUBLIC_OWNERS라 어느 모듈이든 허용
    'src/modules/boards/services/settings.ts': "import { db } from '../../../shared/db';\nexport const s = () => db.setting.findMany();\n",
    // N5 오탐 계열: 평범한 객체 프로퍼티가 모델명과 겹침 / 문자열 리터럴 예시 / 동적 수신자 비클라이언트 / 주석
    'src/modules/boards/services/benign.ts': [
      "const ui = { department: { update: (_: object) => 0 } };",
      "export const a = ui.department.update({});",
      "const msg = '예: prisma.employee.findMany() 는 금지';",
      "export const b = msg.length;",
      "const ctx: Record<string, { update: (n: number) => void }> = {};",
      "const key = 'x';",
      "export const c = () => ctx[key].update(1);",
      "const ctx2 = { department: { update: (_: number) => 0 } };",
      "export const d = ctx2.department.update(2);",
      "// import broken from '../../people/services/hr' — 주석은 무시돼야 한다",
      "",
    ].join('\n'),
  }, (r) => {
    assert.strictEqual(r.status, 0, `오탐 발생:\n${r.stdout}\n${r.stderr}`);
    assert.match(r.stdout, /DB 접근 포함/);
  });
});

test('위반 매트릭스 — Next 형태 11종 전부 검출', () => {
  withFixture({
    ...BASE,
    // V1 route.ts → 모듈 내부 파일
    'src/app/api/x/route.ts': "import { rows } from '@/modules/boards/store/board-store';\nexport async function GET(){ return Response.json(rows); }\n",
    // V2 남의 모듈 내부를 상대경로로 (.tsx)
    'src/modules/people/ui/List.tsx': "import { rows } from '../../boards/store/board-store';\nexport default function L(){ return rows.length; }\n",
    // V3 type-only import라도 내부 파일이면 위반
    'src/modules/people/services/t.ts': "import type { rows } from '../../boards/store/board-store';\nexport type R = typeof rows;\n",
    // V4 동적 import
    'src/app/dyn/page.tsx': "export default async function D(){ const m = await import('@/modules/people/services/hr'); return m.hr; }\n",
    // V5 재수출
    'src/shared/rex.ts': "export { rows } from '@/modules/boards/store/board-store';\n",
    // V6 shared → 모듈 (루트 index라도 역참조 금지)
    'src/shared/uses-module.ts': "import { listBoards } from '@/modules/boards';\nexport const u = listBoards;\n",
    // V7 남의 모델 직접 쿼리 (boards가 people의 Employee)
    'src/modules/boards/services/steal.ts': "import { db } from '../../../shared/db';\nexport const x = () => db.employee.findMany();\n",
    // V8 생 SQL로 남의 테이블
    'src/modules/boards/services/raw.ts': "import { db } from '../../../shared/db';\nexport const y = () => db.$queryRaw`SELECT * FROM employees`;\n",
    // V9 동적 모델 접근 (수신자 클라이언트풍)
    'src/modules/boards/services/dyn.ts': "import { db } from '../../../shared/db';\nexport const z = (name: string) => (db as any)[name].findMany();\n",
    // V10 모듈 안 new PrismaClient
    'src/modules/people/services/own-client.ts': "import { PrismaClient } from '@prisma/client';\nexport const p = new PrismaClient();\n",
    // V11 middleware(진입점)에서 모듈 내부 파일
    'middleware.ts': "import { rows } from '@/modules/boards/store/board-store';\nexport const config = { matcher: [] };\nexport const m = rows;\n",
  }, (r) => {
    assert.strictEqual(r.status, 1, `위반인데 초록:\n${r.stdout}`);
    const out = r.stderr + r.stdout;
    const expects = [
      ['V1 route→내부', /api\/x\/route\.ts.*내부 파일 직접 import/],
      ['V2 상대경로 내부', /List\.tsx.*내부 파일 직접 import/],
      ['V3 type import', /services\/t\.ts.*내부 파일 직접 import/],
      ['V4 동적 import', /dyn\/page\.tsx.*내부 파일 직접 import/],
      ['V5 재수출', /rex\.ts.*내부 파일 직접 import/],
      ['V6 shared 역참조', /uses-module\.ts.*shared는 모듈/],
      ['V7 남의 모델', /steal\.ts.*'Employee'.*직접 쿼리/],
      ['V8 생 SQL', /raw\.ts.*(employees|생 SQL|SQL)/],
      ['V9 동적 모델', /dyn\.ts.*동적 모델 접근/],
      ['V10 PrismaClient', /own-client\.ts.*new PrismaClient/],
      ['V11 middleware', /middleware\.ts.*내부 파일 직접 import/],
    ];
    for (const [name, re] of expects) assert.match(out, re, `${name} 미검출`);
  });
});

test('순환 의존 — 모듈 index 상호 참조 검출', () => {
  withFixture({
    ...BASE,
    'src/modules/boards/index.ts': "import '../people';\nexport const a = 1;\n",
    'src/modules/people/index.ts': "import '../boards';\nexport const b = 2;\n",
  }, (r) => {
    assert.strictEqual(r.status, 1);
    assert.match(r.stderr + r.stdout, /순환 의존/);
  });
});

test('DB 스키마 없는 스택 — 비활성을 소리 내어 알린다', () => {
  const { ['prisma/schema/boards.prisma']: _1, ['prisma/schema/people.prisma']: _2, ['prisma/schema/shared.prisma']: _3, ...noDb } = BASE;
  withFixture(noDb, (r) => {
    assert.strictEqual(r.status, 0, r.stdout + r.stderr);
    assert.match(r.stdout + r.stderr, /DB (경계 검사 비활성|검사 비활성)/);
  });
});
