export const meta = {
  name: 'merge-review',
  description: '머지 전 diff 리뷰 — 렌즈 4개 병렬 + 발견마다 반박 3표, 살아남은 것만 보고',
  whenToUse: '/done 4단계에서. args: { base: "origin/main", card: "#123", acceptance: "수용 기준 원문", externalSurface: true|false, level: "medium"|"high"|"xhigh" }',
  phases: [
    { title: 'Find', detail: '정확성 · 과잉설계 · 수용기준 대조 (+보안: 외부 입력 표면이 있을 때만) 렌즈를 fresh context 로 병렬' },
    { title: 'Verify', detail: '발견마다 반박 전용 검토자 3명 — 둘 이상이 «틀렸다»면 탈락' },
  ],
}

// ── 입력 ────────────────────────────────────────────────────────────────
const a = args || {}
const base = a.base || 'origin/main'
const card = a.card || '(카드 미지정)'
const acceptance = a.acceptance || ''
// 리뷰 수준 = 카드가 정한다(짐작 금지 — 호출하는 /done 4단계가 diff 로 골라 넘긴다).
// 기본 high. 반박표는 «인용이 실재하나»를 보는 일이라 한 단 낮춰도 판정이 흔들리지 않는다(토큰 절반).
const LEVELS = ['medium', 'high', 'xhigh']
const level = LEVELS.includes(a.level) ? a.level : 'high'
const refuteLevel = LEVELS[Math.max(0, LEVELS.indexOf(level) - 1)]
const DIFF = `대상 = \`git diff ${base}...HEAD\` 와 미커밋 변경 \`git diff\`. 먼저 그 명령으로 diff 를 직접 읽고, 필요하면 파일을 열어 주변 코드를 확인하라. 기억으로 답하지 마라.`

// ── 스키마 ──────────────────────────────────────────────────────────────
const FINDINGS = {
  type: 'object',
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          file: { type: 'string' },
          line: { type: 'integer' },
          severity: { type: 'string', enum: ['important', 'nit'] },
          summary: { type: 'string', description: '한 문장 결함 설명 (한국어)' },
          evidence: { type: 'string', description: '그 줄의 원문 인용 — 없으면 발견을 적지 마라' },
          fix: { type: 'string', description: '위치·뭘 지우나·뭘로 대체 — 1줄' },
        },
        required: ['file', 'line', 'severity', 'summary', 'evidence', 'fix'],
      },
    },
    checked: { type: 'array', items: { type: 'string' }, description: '실제로 읽은 파일 경로' },
  },
  required: ['findings', 'checked'],
}
const VERDICT = {
  type: 'object',
  properties: {
    refuted: { type: 'boolean', description: 'true = 이 발견은 틀렸거나 근거가 없다' },
    reason: { type: 'string' },
  },
  required: ['refuted', 'reason'],
}

// ── 렌즈 ────────────────────────────────────────────────────────────────
const RULES = '규칙: ①파일:줄 + 그 줄의 원문 인용이 없는 발견은 적지 마라 ②스타일·취향은 무시 ③확실하지 않으면 nit ④important 는 «머지 전에 고쳐야 할 결함»만.'
const LENSES = [
  { key: 'correctness', prompt: `${DIFF}\n렌즈: 정확성 — 논리 오류·경계값·예외 경로·경합·널 처리·잘못된 조건·테스트가 약해진 흔적(실패 테스트 삭제·skip). ${RULES}` },
  { key: 'overdesign', prompt: `${DIFF}\n렌즈: 과잉설계 — 하나뿐인 구현의 추상화·stdlib 재발명·불필요한 신규 의존성·죽은 코드. 발견은 «위치·뭘 지우나·뭘로 대체» 1줄. ${RULES}` },
  { key: 'acceptance', prompt: `${DIFF}\n렌즈: 수용 기준 대조 — 카드 ${card} 의 수용 기준:\n${acceptance || '(args.acceptance 가 비어 있다 — `glab issue view` 로 카드 본문의 수용 기준·검수 방법을 읽어라)'}\n항목마다 diff 에서 그것을 만족시키는 코드와 테스트를 찾아라. **빠진 항목**을 important 로 보고하라(file·line 은 그 항목이 들어갔어야 할 자리, evidence 는 카드 원문 인용). 넣은 것의 결함은 다른 렌즈 몫이다. ${RULES}` },
]
if (a.externalSurface) {
  LENSES.push({ key: 'security', prompt: `${DIFF}\n렌즈: 보안 — 새 외부 입력 표면(엔드포인트·업로드·인증·비밀값)의 입력 검증·권한 검사·비밀값 노출·인젝션·경로 탈출. ${RULES}` })
}

// ── Find ────────────────────────────────────────────────────────────────
phase('Find')
log(`merge-review: ${card} · base ${base} · 수준 ${level}(반박 ${refuteLevel}) · 렌즈 ${LENSES.map(l => l.key).join(', ')}`)
const found = await parallel(LENSES.map(l => () =>
  agent(`fresh-context 코드 리뷰어. 이 diff 를 쓴 사람이 아니다 — 자기 결과를 옹호할 이유가 없다.\n${l.prompt}`, { label: `find:${l.key}`, phase: 'Find', schema: FINDINGS, effort: level })
    .then(r => r ? { lens: l.key, ...r } : null)))

const finders = found.filter(Boolean)
const checked = [...new Set(finders.flatMap(f => f.checked))]
const seen = new Set()
const candidates = []
for (const f of finders) {
  for (const x of f.findings) {
    const key = `${x.file}:${x.line}:${x.summary.slice(0, 30)}`
    if (seen.has(key)) continue
    seen.add(key)
    candidates.push({ ...x, lens: f.lens })
  }
}
log(`발견 후보 ${candidates.length}건 (렌즈 ${finders.length}/${LENSES.length} 완료)`)

// ── Verify ──────────────────────────────────────────────────────────────
phase('Verify')
const ANGLES = [
  '인용 실재 — 파일을 열어 그 줄에 그 원문이 정말 있는지, 좌표가 맞는지',
  '이미 처리됨 — 지적한 문제를 다른 줄·호출부·테스트·미들웨어가 이미 막고 있는지',
  '재현 가능 — 그 입력·경로에서 정말 그 결함이 나는지 (가능하면 테스트·명령으로 확인)',
]
const verified = await parallel(candidates.map(c => () =>
  parallel(ANGLES.map((angle, i) => () =>
    agent(`반박 전용 검토자. 아래 리뷰 발견을 «틀렸다»고 증명하려 해 봐라. 관점: ${angle}.\n확실하지 않으면 refuted=true 로 답하라 — 의심스러운 발견은 사람에게 보내지 않는다.\n\n발견: ${JSON.stringify(c)}\n\n${DIFF}`,
      { label: `refute:${c.file.split('/').pop()}:${c.line}#${i + 1}`, phase: 'Verify', schema: VERDICT, effort: refuteLevel })))
    .then(votes => {
      const v = votes.filter(Boolean)
      const survived = v.filter(x => !x.refuted).length >= 2
      return { ...c, survived, votes: v.map(x => (x.refuted ? '✗ ' : '○ ') + x.reason) }
    })))

const confirmed = verified.filter(Boolean).filter(x => x.survived)
const rejected = verified.filter(Boolean).filter(x => !x.survived)
log(`확정 ${confirmed.length}건 · 반박 탈락 ${rejected.length}건`)

// 반환값 = /done 이 그대로 쓰는 것: 카드 증적 댓글(전체) + 채팅 보고(확정만)
return {
  card, base,
  lenses: LENSES.map(l => l.key),
  finders_completed: finders.length,
  checked_files: checked,
  confirmed: confirmed.map(({ votes, survived, ...rest }) => rest),
  rejected: rejected.map(x => ({ file: x.file, line: x.line, summary: x.summary, why: x.votes })),
}
