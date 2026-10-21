# 가짜 CLI(#! 스크립트)를 Windows 의 node·파이썬이 띄울 수 있게 한다 — `. scripts/lib/fake-cli.sh` 후 가짜를 만들 때마다 `fake_cli_win <폴더> <이름>`.
# 왜: Windows 의 node(libuv)·파이썬은 «이름.exe» 만 찾는다 — 확장자 없는 #! 가짜는 건너뛰고 PATH 뒤의 진짜 glab·ssh 를 부른다
#     (mr-pipeline-refresh 시험은 진짜 GitLab 에 파이프라인 생성 POST 까지 보냈다 — #707).
# 어떻게: node.exe 를 «이름.exe» 로 링크하고 NODE_OPTIONS --require 심을 걸어, 그 exe 가 옆의 같은 이름 sh 가짜를 같은 인자로 돌린다.
#   인자는 NUL 로 이은 파일로 넘긴다 — 명령줄로 넘기면 MSYS 가 다시 읽으며 `scope[]=` 를 글롭으로 펼치고 `"\n"` 따옴표를 망가뜨린다.
# Linux·macOS 에선 아무것도 안 한다(기존 가짜 그대로). 한계: 가짜에 넘기는 첫 인자가 «-» 로 시작하면 node 가 자기 옵션으로 먹고,
#   경로 모양이면(`sub/dir`·`C:/x`) 역슬래시·상대경로로 바뀐다 — 지금 쓰는 첫 인자는 `api`·호스트명·`terminal` 이라 해당 없음(#707 리뷰).
case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*) FAKECLI_WIN=1;; *) FAKECLI_WIN=;; esac
fake_cli_win() { # $1=폴더 $2=이름
  [ -n "$FAKECLI_WIN" ] || return 0
  # 안전망: 심이 어긋나 진짜 glab 이 불려도 가짜 토큰이라 401 로 막힌다(쓰기 요청이 바깥에 닿지 않게)
  [ "$2" = glab ] && export GITLAB_TOKEN=fake-cli-707 GITLAB_HOST=fake-host.invalid
  node -e 'const fs=require("fs");try{fs.linkSync(process.execPath,process.argv[1])}catch(e){fs.copyFileSync(process.execPath,process.argv[1])}' "$1/$2.exe" || return 1
  [ -n "${FAKECLI_SHIM:-}" ] && return 0
  FAKECLI_SHIM="$1/.fake-cli-shim.cjs"
  cat > "$1/.fake-cli-run.sh" <<'EOF'
mapfile -d '' -t A < "$1"; rm -f "$1"; s=$2; exec sh "$s" "${A[@]}"
EOF
  cat > "$FAKECLI_SHIM" <<'EOF'
const p = require('path'), fs = require('fs');
const script = process.execPath.replace(/\.exe$/i, '');
if (script !== process.execPath && fs.existsSync(script)) { // 링크된 가짜 exe 일 때만 — 진짜 node.exe 는 그냥 지나간다
  const a = process.argv.slice(1);
  if (a.length) a[0] = p.relative(process.cwd(), a[0]); // node 가 첫 인자를 «스크립트 경로»로 보고 절대경로로 바꿔 둔 것을 되돌린다
  const argf = `${script}.args.${process.pid}`;
  fs.writeFileSync(argf, a.map((x) => x + '\0').join(''));
  const fwd = (f) => f.replace(/\\/g, '/');
  const r = require('child_process').spawnSync('bash', [fwd(p.join(__dirname, '.fake-cli-run.sh')), fwd(argf), fwd(script)], { stdio: 'inherit' });
  process.exit(r.status === null ? 1 : r.status);
}
EOF
  export NODE_OPTIONS="--require \"$(cygpath -m "$FAKECLI_SHIM")\"${NODE_OPTIONS:+ $NODE_OPTIONS}"
}
