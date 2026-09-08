// 모듈 경계 검사 v2 — import 경계 + DB 경계 + 순환 의존 (2026-08-07 전면 재작성, 카드는 갈래3·DB갈래 실측 근거)
// 왜 재작성: 구판은 require() 정규식 문자열 매칭이라 ①자기 모듈 형제 폴더를 남의 모듈로 오독(오탐)
//   ②'../../' 깊이·ESM import·동적 import·.ts/.mjs 전부 통과(위반 7건 중 5건 놓침 — 2026-08-06 매트릭스 실측)
//   ③검사 범위가 src/modules뿐이라 test/·server.js·src/shared 경유 위반이 전부 무음 통과.
// 핵심 설계: 경로 문자열이 아니라 path 해석으로 "이 import가 실제 어느 모듈 폴더를 가리키나"를 판정한다.
// 한계(알고 쓰라): 변수 세탁(const c = prisma; c[x]...)·문자열 조립 SQL은 정적으로 못 잡는다 —
//   이 검사기는 실수 방지막이지 악의 방지막이 아니다. 진짜 강제는 DB 계정 권한(GRANT) 분리가 최종 수단.
//   여러 줄 체이닝(`prisma.employee\n  .findMany()`)도 무음 통과한다 — 줄 단위 매칭의 알려진 한계.
// ★값 스택별(킷 치환 지점): SCAN_FILES(진입점)·ALIAS(경로 별칭)·SCHEMA_DIR·SCHEMA_OWNER_OVERRIDES·
//   SHARED_DB_ALLOWLIST. **DB 경계 검사(3-1~3-4)는 Prisma 전용**(.prisma 파싱·PrismaClient·클라이언트 명명
//   휴리스틱) — 다른 ORM 스택에선 모델 맵이 비어 비활성된다(아래에서 경고로 알린다. DB 경계는 리뷰 몫).
//   import·순환 검사는 스택 무관.
const fs = require('fs');
const path = require('path');

const MODULE_ROOT = 'src/modules';
// 검사 범위: 모듈 + 공용(shared) + 라우트 계층(app/ — Next 이식 대비) + 진입점 + 테스트 (구판은 modules만 봤다)
const SCAN_ROOTS = [MODULE_ROOT, 'src/shared', 'app', 'test', 'scripts', 'prisma']; // scripts·prisma 포함: 시드·배치가 모듈 내부를 직접 파고들어도 잡는다(2026-08-19 감사 지적 → bnsone 선행 적용분 역수거)
const SCAN_FILES = ['server.js'];
const EXTS = new Set(['.js', '.jsx', '.ts', '.tsx', '.mjs', '.cjs']);
const ALIAS = { '@/': 'src/' }; // tsconfig "paths": {"@/*": ["./src/*"]} 기준 — 스택이 다르면 여기만 갱신
const SKIP_DIRS = new Set(['node_modules', '.next', '.git']);
// 경계 규칙을 면제할 경로 접두사 — **일회성**(데이터 이관·스파이크)만. 앱 코드에는 쓰지 마라.
// 왜 필요한가: scripts/ 를 스캔 범위에 넣으면(2026-08-26) 여러 모듈 테이블을 가로지르는 것이 정상인
// 일회성 도구가 위반으로 잡힌다. 면제는 **한 줄 사유와 함께** 열거한다 — 비면 면제 없음.
const SCAN_SKIP_PREFIXES = [];

const violations = [];
const warnings = [];

function toPosix(p) { return p.split(path.sep).join('/'); }

function walk(dir) {
  const out = [];
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (SKIP_DIRS.has(e.name)) continue;
    const p = path.join(dir, e.name);
    if (e.isDirectory()) out.push(...walk(p));
    else if (EXTS.has(path.extname(e.name)) && !e.name.endsWith('.d.ts')) out.push(p);
  }
  return out;
}

const allFiles = [];
for (const root of SCAN_ROOTS) if (fs.existsSync(root)) allFiles.push(...walk(root));
if (SCAN_SKIP_PREFIXES.length) {
  const before = allFiles.length;
  for (let i = allFiles.length - 1; i >= 0; i--) {
    if (SCAN_SKIP_PREFIXES.some((p) => allFiles[i].split(path.sep).join('/').startsWith(p))) allFiles.splice(i, 1);
  }
  // 면제는 조용히 지나가면 안 된다 — 몇 개를 안 봤는지 알린다(면제가 늘어나는 것을 사람이 보게)
  if (before - allFiles.length > 0) warnings.push(`경계 면제 ${before - allFiles.length}개 파일(SCAN_SKIP_PREFIXES: ${SCAN_SKIP_PREFIXES.join(', ')})`);
}
for (const f of SCAN_FILES) {
  if (fs.existsSync(f)) allFiles.push(f);
  // 없는 파일을 조용히 건너뛰면 설정 드리프트가 무음이 된다 — 소리를 낸다(스택마다 진입점 이름이 다르다)
  else warnings.push(`SCAN_FILES 항목 '${f}' 가 없다 — 진입점이 이동·개명됐는지 확인하라(검사가 그만큼 덜 본다)`);
}

// 주석 제거(줄 수 보존) — 주석 속 require('...')·$queryRaw 언급이 오탐되는 것 방지.
// 블록 주석은 개행만 남기고, 줄 주석은 앞이 ':'가 아닐 때만 지운다(문자열 속 URL의 //는 살아남는다).
// ★CRLF 안전: `/\r?\n/`로 쪼갠다(#73). `.split('\n')`이면 줄끝에 `\r`가 남는데, JS 정규식에서 `.`은
//   `\r`을 매치 못 하고 `m` 없는 `$`도 `\r` 앞에서 안 걸려 `\/\/.*$`가 CRLF 줄에서 매치 실패 →
//   주석이 살아남아 오탐한다(Windows 로컬 체크아웃에서 정상 코드 push가 막혔다). join은 LF로 통일한다.
function stripComments(code) {
  return code
    .replace(/\/\*[\s\S]*?\*\//g, (m) => m.replace(/[^\n]/g, ''))
    .split(/\r?\n/)
    .map((l) => l.replace(/(^|[^:])\/\/.*$/, '$1'))
    .join('\n');
}

// 문자열 리터럴을 같은 길이의 따옴표로 덮는다(줄·열 보존). **DB 검사에만 쓴다.**
// ★import 검사에는 쓰면 안 된다 — require('../foo') 의 경로까지 지워져 검사가 통째로 죽는다(2026-08-07 실측).
// 왜 필요한가: 문서·에러메시지 안의 `"예: prisma.employee.findMany() 는 금지"` 가 위반으로 잡혔다.
//   규칙을 설명하는 문장이 그 규칙 위반이 되는 꼴이다.
// 한계: 정규식 리터럴과 나눗셈을 구분하지 않는다(정적 파서가 아니다).
function stripStrings(line) {
  return line.replace(/(['"`])(?:\\.|(?!\1)[^\\])*\1/g, (m) => m[0].repeat(m.length));
}

// import·require의 모든 지정자(specifier)를 긁는다 — CJS·ESM 정적·동적·재수출·부수효과, 백틱(보간 없는 것)까지.
// 보간(${}) 든 템플릿은 정적 판별 불가라 제외 — '변수 세탁' 한계와 같은 항목이다.
const SPEC_PATTERNS = [
  /\brequire\s*\(\s*(['"`])([^'"`\n$]+)\1\s*\)/g,          // require('x') · require(`x`)
  /\bimport\s*\(\s*(['"`])([^'"`\n$]+)\1/g,                // import('x') 동적
  /\bimport\s+[^'";]*?\bfrom\s*(['"])([^'"\n]+)\1/g,       // import y from 'x' (type import 포함 — 타입 의존도 경계 위반)
  /\bimport\s*(['"])([^'"\n]+)\1/g,                        // import 'x' 부수효과
  /\bexport\s+[^'";]*?\bfrom\s*(['"])([^'"\n]+)\1/g,       // export { y } from 'x' 재수출
];

function specifiersOf(code) {
  const seen = new Set();
  const out = [];
  for (const re of SPEC_PATTERNS) {
    re.lastIndex = 0;
    let m;
    while ((m = re.exec(code))) {
      const line = code.slice(0, m.index).split('\n').length;
      const key = `${line}:${m[2]}`;
      if (!seen.has(key)) { seen.add(key); out.push({ spec: m[2], line }); }
    }
  }
  return out;
}

// 지정자 → repo 상대 경로(정규화). 외부 패키지·빌트인이면 null
function resolveSpec(spec, fromFile) {
  let p = null;
  if (spec.startsWith('.')) p = path.join(path.dirname(fromFile), spec);
  else {
    for (const [a, real] of Object.entries(ALIAS)) if (spec.startsWith(a)) p = real + spec.slice(a.length);
    if (!p && (spec === 'src' || spec.startsWith('src/'))) p = spec;
  }
  return p ? toPosix(path.normalize(p)) : null;
}

// 이 파일이 속한 모듈 이름 (src/modules/<m>/** 안이면 <m>, 아니면 null)
function moduleOf(file) {
  const m = toPosix(file).match(/^src\/modules\/([^/]+)(?:\/|$)/);
  return m ? m[1] : null;
}

// ── 1) import 경계 ────────────────────────────────────────────────
const moduleEdges = new Map(); // 모듈 → 참조하는 모듈들 (순환 검출용 — index 경유든 내부 직참조든 의존은 의존)

for (const file of allFiles) {
  const own = moduleOf(file);
  const code = stripComments(fs.readFileSync(file, 'utf8'));
  for (const { spec, line } of specifiersOf(code)) {
    const resolved = resolveSpec(spec, file);
    if (!resolved) continue;
    const hit = resolved.match(/^src\/modules\/([^/]+)(?:\/(.*))?$/);
    if (!hit) continue; // 모듈 밖(shared·자기 상대경로 등)을 가리키면 자유
    const [, target, restRaw] = hit;
    if (own === target) continue; // ★자기 모듈 하위·형제 폴더는 자유 — 구판 최대 오탐 지점
    const rest = (restRaw || '').replace(/\.(js|jsx|ts|tsx|mjs|cjs)$/, '');
    const isRootIndex = rest === '' || rest === 'index'; // ★공개 인터페이스 = 모듈 루트 index만 (services/index 등 하위 배럴 불인정)
    const at = `${toPosix(file)}:${line}`;
    if (!isRootIndex) {
      const who = own ? `다른 모듈(${target})` : `모듈 밖에서 모듈(${target})`;
      violations.push(`${at}: '${spec}' — ${who}의 내부 파일 직접 import 금지 (모듈 루트 index만)`);
    } else if (toPosix(file).startsWith('src/shared/')) {
      violations.push(`${at}: '${spec}' — shared는 모듈(${target})을 import할 수 없다 (의존 방향 역전)`);
    }
    if (own) (moduleEdges.get(own) || moduleEdges.set(own, new Set()).get(own)).add(target);
  }
}

// ── 2) 순환 의존 (DFS) ────────────────────────────────────────────
// 모듈 index 간 양방향 참조는 로드 순서에 따라 무음 실패한다('not a function' — 2026-08-06 실측).
// 발견 시: 한쪽을 지연 참조(함수 안 require)로 바꾸거나 단방향+이벤트로 재설계 — 표준은 ADR로 정한다.
{
  const color = new Map(); // 1=방문중 2=완료
  const dfs = (mod, stack) => {
    color.set(mod, 1);
    stack.push(mod);
    for (const next of moduleEdges.get(mod) || []) {
      if (color.get(next) === 1) {
        const cyc = [...stack.slice(stack.indexOf(next)), next].join(' → ');
        violations.push(`순환 의존: ${cyc} — 지연 참조 또는 단방향 재설계로 끊어라`);
      } else if (!color.get(next)) dfs(next, stack);
    }
    stack.pop();
    color.set(mod, 2);
  };
  for (const mod of moduleEdges.keys()) if (!color.get(mod)) dfs(mod, []);
}

// ── 3) DB 경계 — 남의 모듈 소유 테이블 직접 쿼리 금지 (CLAUDE.md 소유 경계 절) ──
// prisma/schema/*.prisma → "모델 → 소유 모듈" 맵. 기본 규칙: 스키마 파일명 = 소유 모듈명
// (base.prisma "각 모듈은 자기 .prisma 파일만 편집"과 동일). 모듈이 없으면 소유자 부재 = 모두의 접근이 위반.
// 예외(파일명≠모듈명)는 여기 명시 — CLAUDE.md 소유 경계 표와 같은 커밋에서 갱신할 것.
const SCHEMA_OWNER_OVERRIDES = {
  // 'people.prisma': 'todos',   // ← 예시: people 스키마를 todos 모듈이 소유하게 됐을 때
};
const SCHEMA_DIR = 'prisma/schema';
const SHARED_DB_ALLOWLIST = ['src/shared/db.js']; // 공용 클라이언트 래퍼 자리 — 여기서만 new PrismaClient 허용
// 앱 프로세스 밖에서 도는 독립 스크립트(시드·점검 배치)는 자기 클라이언트를 만들어야 한다 — 여기 열거한 것만 예외.
// 비우면 예외 없음. 스택 값(2026-08-26 bnsone 선행 적용분 역수거)
const STANDALONE_DB_SCRIPTS = [];

const PRISMA_OPS = [
  'findMany', 'findUnique', 'findUniqueOrThrow', 'findFirst', 'findFirstOrThrow',
  'create', 'createMany', 'createManyAndReturn', 'update', 'updateMany', 'upsert',
  'delete', 'deleteMany', 'count', 'aggregate', 'groupBy',
];
const OPS_ALT = PRISMA_OPS.join('|');
// Prisma에만 있는 메서드 — 수신자가 무엇이든 Prisma로 본다. update·count·create·delete 처럼
// 평범한 객체에도 흔한 이름은 넣지 마라(오탐이 차단으로 이어진다).
const DISTINCT_OPS_ALT = 'findMany|findUnique|findUniqueOrThrow|findFirst|findFirstOrThrow|createMany|createManyAndReturn|updateMany|deleteMany|upsert|aggregate|groupBy';

const modelOwner = new Map(); // clientProp(소문자 시작) → { model, owner, table, file }
// ★2026-09-09: Prisma 기본값은 폴더가 아니라 한 파일(prisma/schema.prisma)이다 — 폴더만 보면 그런 repo 는
//   DB 경계 검사가 통째로 꺼진 채 «✅ 초록» 이 나온다(실측: 남의 모델 직접 쿼리가 EXIT=0). 폴더가 없으면 그 파일도 읽는다.
const SCHEMA_ENTRIES = fs.existsSync(SCHEMA_DIR)
  ? fs.readdirSync(SCHEMA_DIR).map(f => [f, path.join(SCHEMA_DIR, f)])
  : (fs.existsSync('prisma/schema.prisma') ? [['schema.prisma', 'prisma/schema.prisma']] : []);
if (SCHEMA_ENTRIES.length) {
  for (const [f, full] of SCHEMA_ENTRIES) {
    if (!f.endsWith('.prisma')) continue;
    const src = fs.readFileSync(full, 'utf8');
    const owner = SCHEMA_OWNER_OVERRIDES[f] || f.replace(/\.prisma$/, '');
    let mb;
    const blockRe = /model\s+(\w+)\s*\{([\s\S]*?)\n\}/g;
    while ((mb = blockRe.exec(src))) {
      const model = mb[1];
      const mapM = mb[2].match(/@@map\(["'`]([^"'`]+)["'`]\)/);
      const prop = model[0].toLowerCase() + model.slice(1); // prisma 클라이언트 프로퍼티명
      modelOwner.set(prop, { model, owner, table: mapM ? mapM[1] : model, file: f });
    }
  }
}

if (modelOwner.size) {
  const propAlt = [...modelOwner.keys()].join('|');
  for (const file of allFiles) {
    const posix = toPosix(file);
    // test/ 는 DB 소유 검사에서 제외 — 테스트의 모듈 귀속은 파일명 불문율뿐이라 소유 판정이 오탐을 만든다
    // (import 경계 검사는 위 1)에서 이미 본다). 테스트의 DB 접근 관례는 DB 본보기 모듈이 생길 때 함께 정한다.
    if (posix.startsWith('test/')) continue;
    if (SHARED_DB_ALLOWLIST.includes(posix)) continue;
    const me = moduleOf(file) || '(공용)'; // 공용 코드(server.js·shared·app)도 모듈 소유 테이블은 직접 못 만진다
    const rawLines = fs.readFileSync(file, 'utf8').split('\n');
    const lines = stripComments(rawLines.join('\n')).split('\n');
    lines.forEach((rawLine, i) => {
      let line = rawLine;
      if (rawLines[i].includes('db-boundary-allow')) return; // 탈출구 — 사유 주석과 함께만 쓸 것
      const at = `${posix}:${i + 1}`;
      line = stripStrings(line); // 문서·에러메시지 안의 예시 코드가 위반으로 잡히지 않게

      // 3-1) 남의 모델 프로퍼티 접근 — `prisma.employee.findMany(` 꼴. 재수출·별칭(db.·tx.)도 잡는다.
      //   ★수신자 불문으로 두면 안 된다(2026-08-07 실측): `ui.department.update({...})`·`emp.employee.count()`
      //   처럼 모델명과 겹치는 평범한 프로퍼티가 전부 위반으로 잡혔다. 차단형이라 정상 MR이 막힌다.
      //   그래서 둘 중 하나일 때만 위반으로 본다:
      //     ⓐ 수신자가 클라이언트풍(prisma·db·tx·client·conn·orm) — 별칭·재수출을 덮는다
      //     ⓑ 메서드가 Prisma 고유명(findMany·deleteMany·upsert…) — 수신자가 뭐든 Prisma다
      //   `update`·`count`·`create`·`delete`는 평범한 객체에도 흔해 ⓑ에 넣지 않는다.
      const accRe = new RegExp(`(?:([A-Za-z_$][\\w$]*)\\s*)?\\.\\s*(${propAlt})\\s*\\.\\s*(${OPS_ALT})\\s*\\(`, 'g');
      let a;
      while ((a = accRe.exec(line))) {
        const recv = a[1] || '';
        // ★접미 매칭에 소문자 경계 없이 tx$를 쓰면 `ctx`가 걸린다(Next 이식 픽스처 실측 오탐 — React/Next에서 ctx는 일상 변수).
        //   정확 일치 또는 낙타등 접미(myDb·prismaTx)만 클라이언트풍으로 본다.
        const clientish = /^(prisma|client|db|tx|conn|orm)$/i.test(recv) || /(Prisma|Client|Db|DB|Tx|Conn|Orm)$/.test(recv);
        const distinct = new RegExp(`^(${DISTINCT_OPS_ALT})$`).test(a[3]);
        if (!clientish && !distinct) continue; // 평범한 객체 — 오탐 억제
        const info = modelOwner.get(a[2]);
        if (info.owner !== me) {
          violations.push(`${at}: prisma 모델 '${info.model}'(${info.file}, 소유: ${info.owner}) 직접 쿼리 — 소유 모듈의 index 공개 함수로 요청하라`);
        }
      }

      // 3-2) 생 SQL — $queryRaw 류. SQL 텍스트에서 남의 테이블명이 보이면 위반, 판별 불가면 경고(막지 않음).
      if (/\$(queryRawUnsafe|executeRawUnsafe|queryRaw|executeRaw)\b/.test(line)) {
        const ctx = lines.slice(i, i + 12).join('\n');
        const sqlM = ctx.match(/`[^`]*`/);
        const sql = sqlM ? sqlM[0] : '';
        let hit = false;
        for (const { model, owner, table } of modelOwner.values()) {
          if (owner === me) continue;
          const t = new RegExp(`"(?:${model}|${table})"|\\b${table}\\b`, 'i');
          if (sql && t.test(sql)) {
            violations.push(`${at}: 생 SQL($queryRaw 류)이 남의 테이블 '${table}'(소유: ${owner})에 접근 — 소유 모듈의 공개 함수로`);
            hit = true;
          }
        }
        if (!hit) warnings.push(`${at}: 생 SQL($queryRaw 류) 사용 — 대상 테이블을 정적으로 판별 못 함. 리뷰에서 소유를 확인하라`);
      }

      // 3-3) 동적 모델 접근 — client[이름].findMany( 꼴은 정적 판별 불가 → 위반(모델명을 리터럴로 쓰라).
      //      오탐 억제: 수신자가 클라이언트풍(prisma·db·tx·client)이거나 메서드가 Prisma 고유명일 때만
      //      (rows[0].count() 같은 일상 코드가 걸리지 않게 — count·create·update·delete 단독은 흔한 이름).
      const DISTINCT_OPS = 'findMany|findUnique|findUniqueOrThrow|findFirst|findFirstOrThrow|createMany|createManyAndReturn|updateMany|deleteMany|upsert|aggregate|groupBy';
      const dynM = line.match(new RegExp(`(\\w+)\\s*\\[[^\\]\\n]+\\]\\s*\\.\\s*(${OPS_ALT})\\s*\\(`));
      if (dynM && (/^(prisma|client|db|tx)$/i.test(dynM[1]) || /(Prisma|Client|Db|DB|Tx)$/.test(dynM[1]) || new RegExp(`^(${DISTINCT_OPS})$`).test(dynM[2]))) {
        violations.push(`${at}: 동적 모델 접근(client[이름].메서드) — 정적 검사 불가. 모델명을 리터럴로 쓰거나 소유 모듈 공개 함수로`);
      }
      //      TS 캐스트 꼴 — `(db as any)[이름].findMany(`. 수신자 식별자가 `)`에 가려 위 정규식이 못 본다
      //      (Next 이식 픽스처 실측 미검출 → 보강). 수신자 판별이 불가하므로 Prisma 고유명일 때만 위반.
      const dynCast = line.match(new RegExp(`\\)\\s*\\[[^\\]\\n]+\\]\\s*\\.\\s*(${DISTINCT_OPS})\\s*\\(`));
      if (dynCast) {
        violations.push(`${at}: 동적 모델 접근(캐스트 꼴 (x as any)[이름].메서드) — 정적 검사 불가. 모델명을 리터럴로 쓰거나 소유 모듈 공개 함수로`);
      }

      // 3-4) 모듈·공용 코드에서 PrismaClient 직접 생성 — 클라이언트는 공용 래퍼 한 곳으로 모은다
      if (/new\s+PrismaClient\s*\(/.test(line) && !STANDALONE_DB_SCRIPTS.includes(posix)) {
        violations.push(`${at}: new PrismaClient() — 클라이언트 생성은 ${SHARED_DB_ALLOWLIST.join(', ')} 한 곳으로 모아라`);
      }
    });
  }
}

// ── 4) 모듈 지도(--map) — 검사가 이미 계산한 그래프를 버리지 않고 한 장으로 출력.
//    (2026-08-15 Graphify 아이디어 차용: "지도는 결정적 추출로 공짜 생성, AI는 조회만" — LLM·외부 의존 0)
//    재생성: node scripts/check-boundaries.cjs --map — 새 모듈·index 변경·스키마 변경 후. 낡으면 재생성이 정답.
if (process.argv.includes('--map')) {
  const mods = fs.existsSync(MODULE_ROOT)
    ? fs.readdirSync(MODULE_ROOT, { withFileTypes: true }).filter((e) => e.isDirectory() && !e.name.startsWith('_')).map((e) => e.name)
    : [];
  const exportsOf = (mod) => {
    for (const ext of ['ts', 'tsx', 'js', 'jsx', 'mjs', 'cjs']) {
      const p = path.join(MODULE_ROOT, mod, `index.${ext}`);
      if (!fs.existsSync(p)) continue;
      const code = stripComments(fs.readFileSync(p, 'utf8'));
      const names = new Set();
      for (const m of code.matchAll(/\bexport\s+(?:async\s+)?(?:function|const|let|class)\s+([A-Za-z_$][\w$]*)/g)) names.add(m[1]);
      for (const m of code.matchAll(/\bexport\s*\{([^}]+)\}/g)) m[1].split(',').forEach((s) => { const n = s.split(/\bas\b/).pop().trim(); if (n) names.add(n); });
      for (const m of code.matchAll(/\bexports\.([A-Za-z_$][\w$]*)\s*=/g)) names.add(m[1]);
      const mm = code.match(/module\.exports\s*=\s*\{([^}]*)\}/);
      if (mm) mm[1].split(',').forEach((s) => { const n = s.split(':')[0].trim(); if (n) names.add(n); });
      return { names: [...names].sort() };
    }
    return null;
  };
  const uses = new Map(); // 역방향(사용처)
  for (const [from, tos] of moduleEdges) for (const t of tos) (uses.get(t) || uses.set(t, new Set()).get(t)).add(from);
  const dbByOwner = new Map();
  for (const { model, owner } of modelOwner.values()) (dbByOwner.get(owner) || dbByOwner.set(owner, []).get(owner)).push(model);
  const SELF = path.basename(__filename); // 스택 변형(-next 등)에서도 재생성 명령이 맞게
  const out = ['# 모듈 지도 — 기계 생성(수동 편집 금지)', `> 재생성: \`npm run boundaries -- --map\`(없으면 \`node scripts/${SELF} --map\`). 생성 시점 기준이라 낡을 수 있다 — 코드와 다르면 재생성이 정답.`, ''];
  for (const mod of mods.sort()) {
    const ex = exportsOf(mod);
    out.push(`## ${mod}`);
    out.push(`- 공개 함수(index): ${ex ? (ex.names.length ? ex.names.map((n) => '`' + n + '`').join(' · ') : '(export 없음)') : '(index 없음 — 공개 인터페이스 미정)'}`);
    const deps = [...(moduleEdges.get(mod) || [])].sort();
    const used = [...(uses.get(mod) || [])].sort();
    out.push(`- 의존 → ${deps.length ? deps.join(', ') : '없음'} / 사용처 ← ${used.length ? used.join(', ') : '없음'}`);
    const models = (dbByOwner.get(mod) || []).sort();
    if (models.length) out.push(`- 소유 DB 모델: ${models.join(', ')}`);
    out.push('');
  }
  if (mods.length) {
    const mapPath = path.join(MODULE_ROOT, '_MODULE_MAP.md');
    fs.writeFileSync(mapPath, out.join('\n'));
    console.log(`🗺  ${toPosix(mapPath)} 생성 (모듈 ${mods.length}개)`);
  } else console.log('🗺  src/modules 에 모듈 없음 — 지도 생략');
}

// ── 결과 ──────────────────────────────────────────────────────────
// ★"검사했다"와 "안 봤다"를 구분해 말한다 — DB 검사 비활성인데 "DB 접근 경계 안"이라고 하면 거짓 보증이다.
if (!modelOwner.size) warnings.push(`DB 경계 검사 비활성 — ${SCHEMA_DIR}/ 에도 prisma/schema.prisma 에도 모델이 없다. Prisma 를 안 쓰면 정상이지만 **쓰는데 못 찾은 것일 수도 있다**(그때는 DB 경계가 꺼진 채 초록이 나온다). DB 경계는 리뷰 몫`);
if (warnings.length) console.warn('⚠️ 경고(막지 않음):\n' + warnings.join('\n'));
if (violations.length) {
  console.error('❌ 모듈 경계 위반:\n' + violations.join('\n'));
  process.exit(1);
}
const dbNote = modelOwner.size ? 'DB 접근 포함' : 'DB 검사 비활성';
console.log(`✅ 모듈 경계 OK — 교차 모듈 import·순환 의존 경계 안 (${dbNote}, CJS·ESM·TS·별칭 포함)`);
