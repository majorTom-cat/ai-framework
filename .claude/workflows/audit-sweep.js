export const meta = {
  name: 'audit-sweep',
  description: '문서·코드 전수 감사 — 묶음마다 감사 에이전트 + 인용 검증 에이전트, 인용이 실재하지 않는 발견은 탈락',
  whenToUse: '/overhaul 2단계에서. args: [{ name: "정본 규칙", canon: "이 영역의 정본이 무엇인지 한 줄", files: ["CLAUDE.md", ...] }, ...]',
  phases: [
    { title: 'Audit', detail: '묶음마다 fresh-context 감사 에이전트 1개 — 배정 문서를 전부 열어 5종 수거' },
    { title: 'Verify', detail: '묶음마다 인용 검증 에이전트 1개 — 파일:줄 인용이 실재하는지, 좌표가 맞는지' },
  ],
}

const bundles = Array.isArray(args) ? args : (args && args.bundles) || []
if (!bundles.length) throw new Error('args 로 묶음 목록 [{name, canon, files}] 을 넘겨라 — /overhaul 1단계 «지도»의 결과다')

const AUDIT = {
  type: 'object',
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          kind: { type: 'string', enum: ['중복', '모순', '낡음', '자리잘못', '비대', '위험지점'] },
          file: { type: 'string' },
          line: { type: 'integer' },
          quote: { type: 'string', description: '그 줄의 원문 인용 (그대로) — 없으면 발견을 적지 마라' },
          diagnosis: { type: 'string', description: '무엇이 문제인지 한 문장' },
          proposal: { type: 'string', description: '이동 / 병합 / 삭제 / 대체됨 표지판 / 축약(포인터화) 중 하나 + 한 줄' },
        },
        required: ['kind', 'file', 'line', 'quote', 'diagnosis', 'proposal'],
      },
    },
    checked: { type: 'array', items: { type: 'string' }, description: '실제로 끝까지 읽은 파일 경로 전부' },
  },
  required: ['findings', 'checked'],
}
const VERIFY = {
  type: 'object',
  properties: {
    results: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          index: { type: 'integer' },
          quote_found: { type: 'boolean', description: '그 파일에 그 인용이 실재한다 (줄 번호는 ±3 허용)' },
          actual_line: { type: 'integer' },
          note: { type: 'string' },
        },
        required: ['index', 'quote_found', 'note'],
      },
    },
  },
  required: ['results'],
}

phase('Audit')
log(`audit-sweep: 묶음 ${bundles.length}개 · 파일 ${bundles.reduce((n, b) => n + (b.files || []).length, 0)}개`)

const results = await pipeline(
  bundles,
  b => agent(
    `fresh-context 감사 에이전트. 묶음 «${b.name}». 이 영역의 정본: ${b.canon || '(미지정 — 먼저 정본이 무엇인지 한 줄로 정하고 시작하라)'}\n` +
    `배정 문서(전부 실제로 열어라 — 요약·목차 스킵 금지):\n${(b.files || []).map(f => '- ' + f).join('\n')}\n\n` +
    `수거할 것: ①중복(같은 규칙이 두 곳) ②모순(정본과 다른 서술) ③낡음(폐기된 규칙·죽은 경로·명령·날짜) ④자리잘못(배치 규칙 위반) ⑤비대(분리·축약 후보) ⑥위험지점(코드면: 권한 검사 누락·입력 검증 없는 경계·트랜잭션 없는 다중 쓰기·말없이 잘리는 상한).\n` +
    `규칙: 각 발견에 파일:줄 + 그 줄의 원문 인용 필수 — 인용이 없으면 적지 마라. «문제 없음»이어도 checked 에 읽은 파일 전부를 적어라(0건 ≠ 안 봄). 파일을 고치지 마라.`,
    { label: `audit:${b.name}`, phase: 'Audit', schema: AUDIT }),
  (r, b) => {
    if (!r) return null
    if (!r.findings.length) return { bundle: b.name, findings: [], dropped: [], checked: r.checked }
    return agent(
      `인용 검증자. 아래 발견 목록의 각 항목에 대해 file 을 직접 열어 quote 가 실제로 그 파일에 있는지(줄 번호 ±3 허용) 확인하라. 없거나 다른 문장이면 quote_found=false. 판단하지 말고 실재 여부만 보고하라.\n\n` +
      r.findings.map((f, i) => `[${i}] ${f.file}:${f.line} «${f.quote}»`).join('\n'),
      { label: `verify:${b.name}`, phase: 'Verify', schema: VERIFY, effort: 'high' })
      .then(v => {
        const ok = new Map((v ? v.results : []).map(x => [x.index, x]))
        const findings = [], dropped = []
        r.findings.forEach((f, i) => {
          const x = ok.get(i)
          if (x && x.quote_found) findings.push({ ...f, line: x.actual_line || f.line })
          else dropped.push({ ...f, why: x ? x.note : '검증자 응답 없음' })
        })
        return { bundle: b.name, findings, dropped, checked: r.checked }
      })
  },
)

const out = results.filter(Boolean).map(r => {
  const assigned = (bundles.find(b => b.name === r.bundle) || {}).files || []
  const unchecked = assigned.filter(f => !r.checked.includes(f))
  return { ...r, unchecked }
})
const totals = out.reduce((t, r) => ({ findings: t.findings + r.findings.length, dropped: t.dropped + r.dropped.length, unchecked: t.unchecked + r.unchecked.length }), { findings: 0, dropped: 0, unchecked: 0 })
log(`확정 ${totals.findings}건 · 인용 불일치 탈락 ${totals.dropped}건 · 안 읽힌 파일 ${totals.unchecked}개 (0이 아니면 그 묶음을 다시 돌려라)`)

// 반환값: 묶음별 확정 발견(파일:줄+인용) · 탈락 목록 · 안 읽힌 파일. 3단계 «종합»의 입력이다 — 파괴적 제안은 본 세션이 파일을 직접 열어 재확인한 뒤에만 표에 올린다.
return { bundles: out, totals }
