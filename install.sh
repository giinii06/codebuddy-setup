#!/usr/bin/env bash
set -euo pipefail

REPO="${CODEBUDDY_SETUP_REPO:-giinii06/codebuddy-setup}"
BRANCH="${CODEBUDDY_SETUP_BRANCH:-main}"
RAW="${CODEBUDDY_SETUP_RAW:-https://raw.githubusercontent.com/$REPO/$BRANCH}"
RELEASE="${CODEBUDDY_SETUP_RELEASE_BASE:-https://github.com/$REPO/releases/latest/download}"

CODEBUDDY_VERSION="${CODEBUDDY_VERSION:-2.184.0}"
CODEBUDDY_LINUX_SHA256="${CODEBUDDY_LINUX_SHA256:-1d780dc0f459d30ac0cc51153d04f29ab8063ec24d5ce39b31f82bb719f45937}"
CODEBUDDY_CLI_ARCHIVE="${CODEBUDDY_CLI_ARCHIVE:-}"
CODEBUDDY_CLI_SHA256="${CODEBUDDY_CLI_SHA256:-}"
NODE_VERSION="${NODE_VERSION:-24.22.3}"
BUN_VERSION="${BUN_VERSION:-1.4.4}"
NODE_DIST="${CODEBUDDY_SETUP_NODE_DIST:-https://nodejs.org/dist}"
BUN_DIST="${CODEBUDDY_SETUP_BUN_DIST:-https://github.com/oven-sh/bun/releases/download}"

HOME_DIR="$HOME"
LOCAL_BIN="$HOME_DIR/.local/bin"
NODE_DIR="$HOME_DIR/.local/node"
BUN_DIR="$HOME_DIR/.bun"
CB_DIR="$HOME_DIR/.codebuddy"
SETTINGS="$CB_DIR/settings.json"
MCP_CONFIG="$CB_DIR/.mcp.json"
PSTACK_MODELS="$CB_DIR/pstack-models.md"
ROTATE_DIR="$HOME_DIR/.codebuddy-rotate"
SWITCH_DIR="$HOME_DIR/.wb-switch"
ACCOUNTS="$SWITCH_DIR/accounts.json"
WB_BIN="$LOCAL_BIN/wb-codebuddy"
HOOK_SCRIPT="$SWITCH_DIR/hook.sh"
SHELL_MARKER="# >>> codebuddy-setup >>>"
SHELL_MARKER_END="# <<< codebuddy-setup <<<"

PLUGIN_IDS=(
  "pstack@pstack-claude"
  "agent-browser@codebuddy-plugins-official"
  "docx@codebuddy-plugins-official"
  "find-skills@codebuddy-plugins-official"
  "pdf@codebuddy-plugins-official"
  "playwright-cli@codebuddy-plugins-official"
  "pptx@codebuddy-plugins-official"
  "skills-sec-audit@codebuddy-plugins-official"
  "xlsx@codebuddy-plugins-official"
)

say() { printf '%s\n' "$*"; }
warn() { printf '경고  %s\n' "$*" >&2; }
die() { printf '오류  %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

fetch() {
  local url="$1"
  local out="$2"
  curl -fsSL "$url" -o "$out" || die "다운로드에 실패했습니다. $url"
}

sha256_of() {
  if have sha256sum; then
    sha256sum "$1" | awk '{print $1}'
  elif have shasum; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif have openssl; then
    openssl dgst -sha256 "$1" | awk '{print $NF}'
  else
    return 1
  fi
}

require_sha256_tool() {
  if ! have sha256sum && ! have shasum && ! have openssl; then
    die "SHA256 도구가 없습니다. sha256sum 또는 shasum을 설치하세요."
  fi
}

verify_sha256() {
  local file="$1"
  local expected="$2"
  local label="$3"
  local actual
  actual="$(sha256_of "$file")" || die "$label 체크섬을 계산하지 못했습니다."
  if [ "$actual" != "$expected" ]; then
    die "$label 체크섬이 다릅니다. 기대값 $expected, 실제값 $actual"
  fi
  say "체크섬 확인  $label"
}

resolve_platform() {
  local raw_os raw_arch
  if [ -n "${CODEBUDDY_SETUP_PLATFORM:-}" ]; then
    PLATFORM="$CODEBUDDY_SETUP_PLATFORM"
  else
    raw_os="$(uname -s)"
    raw_arch="$(uname -m)"
    case "$raw_os/$raw_arch" in
      Darwin/arm64) PLATFORM="darwin-arm64" ;;
      Darwin/x86_64)
        die "macOS Intel은 지원하지 않습니다. Apple Silicon(arm64)에서 실행하세요."
        ;;
      Linux/x86_64 | Linux/amd64) PLATFORM="linux-amd64" ;;
      Linux/aarch64 | Linux/arm64)
        die "Linux arm64는 지원하지 않습니다. x86_64에서 실행하세요."
        ;;
      MINGW* | MSYS* | CYGWIN*)
        die "Windows 네이티브는 지원하지 않습니다. WSL2 Ubuntu 셸 안에서 실행하세요."
        ;;
      *)
        die "지원하지 않는 플랫폼입니다. $raw_os/$raw_arch"
        ;;
    esac
  fi
  case "$PLATFORM" in
    darwin-arm64 | linux-amd64) ;;
    *)
      die "알 수 없는 CODEBUDDY_SETUP_PLATFORM 값입니다. $PLATFORM"
      ;;
  esac
  ASSET="wb-codebuddy-$PLATFORM"
  say "플랫폼  $PLATFORM"
}

resolve_shell_rc() {
  if [ "$PLATFORM" = "darwin-arm64" ]; then
    SHELL_RC="$HOME_DIR/.zshrc"
    return 0
  fi
  case "${SHELL:-}" in
    *zsh) SHELL_RC="$HOME_DIR/.zshrc" ;;
    *) SHELL_RC="$HOME_DIR/.bashrc" ;;
  esac
}

node_major() {
  local version
  version="$(node --version 2>/dev/null || true)"
  version="${version#v}"
  case "$version" in
    '' | *[!0-9.]*) printf '0' ;;
    *) printf '%s' "${version%%.*}" ;;
  esac
}

install_node() {
  local major name archive sums expected extract source
  major="$(node_major)"
  if [ "$major" -ge 20 ]; then
    say "이미 있음  node $(node --version)"
    return 0
  fi

  case "$PLATFORM" in
    darwin-arm64) name="node-v$NODE_VERSION-darwin-arm64.tar.gz" ;;
    linux-amd64) name="node-v$NODE_VERSION-linux-x64.tar.xz" ;;
  esac
  say "설치  Node $NODE_VERSION ($PLATFORM)"

  archive="$TMP_DIR/$name"
  sums="$TMP_DIR/node-SHASUMS256.txt"
  fetch "$NODE_DIST/v$NODE_VERSION/$name" "$archive"
  fetch "$NODE_DIST/v$NODE_VERSION/SHASUMS256.txt" "$sums"
  expected="$(awk -v name="$name" '$2 == name {print $1}' "$sums")"
  [ -n "$expected" ] || die "Node 체크섬 목록에서 $name 항목을 찾지 못했습니다."
  verify_sha256 "$archive" "$expected" "$name"

  extract="$TMP_DIR/node-extract"
  mkdir -p "$extract"
  case "$name" in
    *.tar.xz)
      tar -xJf "$archive" -C "$extract" || die "Node 압축을 풀지 못했습니다. xz-utils가 필요합니다."
      ;;
    *)
      tar -xzf "$archive" -C "$extract" || die "Node 압축을 풀지 못했습니다."
      ;;
  esac
  source="$extract/${name%.tar.*}"
  [ -d "$source" ] || die "Node 압축 구조가 예상과 다릅니다."

  rm -rf "$NODE_DIR"
  mkdir -p "$(dirname "$NODE_DIR")"
  mv "$source" "$NODE_DIR"
  mkdir -p "$LOCAL_BIN"
  ln -sf "$NODE_DIR/bin/node" "$LOCAL_BIN/node"
  ln -sf "$NODE_DIR/bin/npm" "$LOCAL_BIN/npm"
  ln -sf "$NODE_DIR/bin/npx" "$LOCAL_BIN/npx"
  hash -r
  have node || die "Node를 설치했지만 PATH에서 찾지 못했습니다."
  say "설치 완료  node $(node --version)"
}

install_python() {
  if have python3; then
    say "이미 있음  python3 $(python3 --version 2>&1)"
    return 0
  fi
  if [ "$PLATFORM" = "darwin-arm64" ]; then
    say "설치  python (brew)"
    brew install python || die "python 설치에 실패했습니다."
    hash -r
    have python3 || die "python3를 설치했지만 PATH에서 찾지 못했습니다."
    return 0
  fi
  die "python3가 없습니다. sudo apt install -y python3 를 실행한 뒤 다시 시도하세요."
}

install_bun() {
  local name archive sums expected extract source
  if [ -x "$BUN_DIR/bin/bun" ]; then
    say "이미 있음  bun $("$BUN_DIR/bin/bun" --version 2>/dev/null || true)"
    return 0
  fi
  if have bun; then
    say "이미 있음  bun $(bun --version)"
    return 0
  fi

  case "$PLATFORM" in
    darwin-arm64) name="bun-darwin-aarch64.zip" ;;
    linux-amd64) name="bun-linux-x64.zip" ;;
  esac
  say "설치  Bun $BUN_VERSION ($PLATFORM)"

  archive="$TMP_DIR/$name"
  sums="$TMP_DIR/bun-SHASUMS256.txt"
  fetch "$BUN_DIST/bun-v$BUN_VERSION/$name" "$archive"
  fetch "$BUN_DIST/bun-v$BUN_VERSION/SHASUMS256.txt" "$sums"
  expected="$(awk -v name="$name" '$2 == name {print $1}' "$sums")"
  [ -n "$expected" ] || die "Bun 체크섬 목록에서 $name 항목을 찾지 못했습니다."
  verify_sha256 "$archive" "$expected" "$name"

  extract="$TMP_DIR/bun-extract"
  mkdir -p "$extract"
  if have unzip; then
    unzip -q "$archive" -d "$extract" || die "Bun 압축을 풀지 못했습니다."
  elif have python3; then
    python3 -m zipfile -e "$archive" "$extract" || die "Bun 압축을 풀지 못했습니다."
  else
    die "Bun 압축을 풀려면 unzip 또는 python3가 필요합니다."
  fi
  source="$extract/${name%.zip}"
  [ -f "$source/bun" ] || die "Bun 압축 구조가 예상과 다릅니다."

  mkdir -p "$BUN_DIR/bin"
  install -m 755 "$source/bun" "$BUN_DIR/bin/bun"
  ln -sf "$BUN_DIR/bin/bun" "$BUN_DIR/bin/bunx"
  hash -r
  have bun || die "Bun을 설치했지만 PATH에서 찾지 못했습니다."
  say "설치 완료  bun $("$BUN_DIR/bin/bun" --version)"
}

install_dependencies() {
  local missing=""
  for tool in curl tar; do
    have "$tool" || missing="$missing $tool"
  done
  [ -z "$missing" ] || die "필수 도구가 없습니다:$missing"
  require_sha256_tool

  if [ "$PLATFORM" = "darwin-arm64" ]; then
    have brew || die "Homebrew가 필요합니다. https://brew.sh 에서 설치한 뒤 다시 실행하세요."
  fi

  install_node
  install_python
  install_bun
}

install_codebuddy_cli() {
  if [ "$PLATFORM" = "darwin-arm64" ]; then
    if have codebuddy; then
      say "이미 있음  codebuddy"
      return 0
    fi
    say "설치  codebuddy (brew formula)"
    brew install tencent-codebuddy/tap/codebuddy-code || die "CodeBuddy CLI 설치에 실패했습니다."
    hash -r
    have codebuddy || die "codebuddy를 설치했지만 PATH에서 찾지 못했습니다."
    return 0
  fi

  if [ -x "$LOCAL_BIN/codebuddy" ]; then
    say "이미 있음  $LOCAL_BIN/codebuddy"
    return 0
  fi

  local archive extract
  archive="$TMP_DIR/codebuddy-cli.tar.gz"
  if [ -n "$CODEBUDDY_CLI_ARCHIVE" ]; then
    say "사용  로컬 CodeBuddy CLI 압축 파일"
    cp "$CODEBUDDY_CLI_ARCHIVE" "$archive" || die "로컬 압축 파일을 읽지 못했습니다. $CODEBUDDY_CLI_ARCHIVE"
    if [ -n "$CODEBUDDY_CLI_SHA256" ]; then
      verify_sha256 "$archive" "$CODEBUDDY_CLI_SHA256" "codebuddy-cli.tar.gz"
    fi
  else
    say "설치  CodeBuddy CLI $CODEBUDDY_VERSION (linux-x64)"
    fetch "https://acc-1258344699.cos.ap-guangzhou.myqcloud.com/@tencent-ai/codebuddy-code/releases/download/$CODEBUDDY_VERSION/codebuddy-code_Linux_x86_64.tar.gz" "$archive"
    verify_sha256 "$archive" "$CODEBUDDY_LINUX_SHA256" "codebuddy-cli.tar.gz"
  fi

  extract="$TMP_DIR/codebuddy-cli"
  mkdir -p "$extract"
  tar -xzf "$archive" -C "$extract" || die "CodeBuddy CLI 압축을 풀지 못했습니다."
  [ -f "$extract/codebuddy" ] || die "압축 파일 안에 codebuddy가 없습니다."
  mkdir -p "$LOCAL_BIN"
  install -m 755 "$extract/codebuddy" "$LOCAL_BIN/codebuddy"
  say "설치 완료  $LOCAL_BIN/codebuddy"
}

install_codegraph() {
  if have codegraph; then
    say "이미 있음  codegraph"
    return 0
  fi
  say "설치  codegraph"
  NPM_CONFIG_PREFIX="$HOME_DIR/.local" npm install -g @colbymchenry/codegraph \
    || die "codegraph 설치에 실패했습니다."
  hash -r
  have codegraph || die "codegraph를 설치했지만 PATH에서 찾지 못했습니다."
  say "설치 완료  $(command -v codegraph)"
}

codebuddy_bin() {
  if [ "$PLATFORM" = "darwin-arm64" ]; then
    command -v codebuddy || true
  else
    printf '%s' "$LOCAL_BIN/codebuddy"
  fi
}

install_plugins() {
  local cb marketplaces installed id
  cb="$(codebuddy_bin)"
  if [ -z "$cb" ] || [ ! -x "$cb" ]; then
    warn "codebuddy 실행 파일을 찾지 못했습니다. 플러그인 설치를 건너뜁니다."
    return 0
  fi
  marketplaces="$("$cb" plugin marketplace list 2>/dev/null || true)"
  case "$marketplaces" in
    *pstack-claude*)
      say "이미 있음  마켓 pstack-claude"
      ;;
    *)
      say "마켓 추가  michael-denyer/pstack-claude"
      "$cb" plugin marketplace add michael-denyer/pstack-claude \
        || warn "마켓 추가에 실패했습니다. pstack 설치는 건너뜁니다."
      ;;
  esac

  installed="$("$cb" plugin list 2>/dev/null || true)"
  for id in "${PLUGIN_IDS[@]}"; do
    case "$installed" in
      *"$id"*)
        say "이미 있음  $id"
        continue
        ;;
    esac
    say "플러그인 설치  $id"
    "$cb" plugin install "$id" || warn "플러그인 설치에 실패했습니다. $id"
  done
}

install_wb_codebuddy() {
  local expected
  mkdir -p "$LOCAL_BIN" "$ROTATE_DIR" "$SWITCH_DIR/logs"
  fetch "$RELEASE/$ASSET" "$TMP_DIR/$ASSET"
  fetch "$RELEASE/$ASSET.sha256" "$TMP_DIR/$ASSET.sha256"
  expected="$(awk '{print $1}' "$TMP_DIR/$ASSET.sha256")"
  [ -n "$expected" ] || die "체크섬 파일이 비어 있습니다. $ASSET.sha256"
  verify_sha256 "$TMP_DIR/$ASSET" "$expected" "$ASSET"
  install -m 755 "$TMP_DIR/$ASSET" "$WB_BIN"
  say "설치 완료  $WB_BIN"

  fetch "$RAW/vendor/wb-codebuddy/scripts/codebuddy-cli-helper.cjs" "$TMP_DIR/helper.cjs"
  install -m 700 "$TMP_DIR/helper.cjs" "$ROTATE_DIR/helper.cjs"
  say "설치 완료  $ROTATE_DIR/helper.cjs"

  fetch "$RAW/vendor/wb-codebuddy/scripts/codebuddy-rotate.py" "$TMP_DIR/codebuddy-rotate.py"
  install -m 755 "$TMP_DIR/codebuddy-rotate.py" "$ROTATE_DIR/codebuddy-rotate.py"
  say "설치 완료  $ROTATE_DIR/codebuddy-rotate.py"

  fetch "$RAW/scripts/hook.sh" "$TMP_DIR/hook.sh"
  install -m 755 "$TMP_DIR/hook.sh" "$HOOK_SCRIPT"
  say "설치 완료  $HOOK_SCRIPT"
}

install_pstack_models() {
  if [ -f "$PSTACK_MODELS" ]; then
    say "기존 파일 유지  $PSTACK_MODELS"
    return 0
  fi
  fetch "$RAW/config/pstack-models.md" "$TMP_DIR/pstack-models.md"
  install -m 644 "$TMP_DIR/pstack-models.md" "$PSTACK_MODELS"
  say "설치 완료  $PSTACK_MODELS"
}

merge_mcp() {
  mkdir -p "$CB_DIR"
  CODEBUDDY_SETUP_MCP="$MCP_CONFIG" node "$TMP_DIR/merge-mcp.mjs" \
    || die "MCP 설정 병합에 실패했습니다."
}

merge_settings() {
  mkdir -p "$CB_DIR"
  CODEBUDDY_SETUP_SETTINGS="$SETTINGS" \
    CODEBUDDY_SETUP_HOME="$HOME_DIR" \
    CODEBUDDY_SETUP_ACCOUNTS="$ACCOUNTS" \
    CODEBUDDY_SETUP_MODEL="${CODEBUDDY_MODEL:-deepseek-v4.1-flash}" \
    CODEBUDDY_SETUP_EFFORT="${CODEBUDDY_REASONING_EFFORT:-max}" \
    CODEBUDDY_SETUP_PERMISSION_MODE="${CODEBUDDY_PERMISSION_MODE:-fullAccess}" \
    node "$TMP_DIR/merge-settings.mjs" || die "settings.json 병합에 실패했습니다."
}

install_shell_block() {
  resolve_shell_rc
  mkdir -p "$(dirname "$SHELL_RC")"
  [ -f "$SHELL_RC" ] || : > "$SHELL_RC"

  local next="$TMP_DIR/shellrc"
  if grep -Fq "$SHELL_MARKER" "$SHELL_RC"; then
    awk -v start="$SHELL_MARKER" -v end="$SHELL_MARKER_END" '
      $0 == start {
        print start
        print "export BUN_INSTALL=\"$HOME/.bun\""
        print "export PATH=\"$HOME/.local/bin:$HOME/.bun/bin:$PATH\""
        print "alias codebuddy=\"$HOME/.codebuddy-rotate/codebuddy-rotate.py\""
        skip = 1
        next
      }
      $0 == end { skip = 0 }
      !skip { print }
    ' "$SHELL_RC" > "$next"
  else
    cp "$SHELL_RC" "$next"
    if [ -s "$next" ] && [ -n "$(tail -c 1 "$next")" ]; then
      printf '\n' >> "$next"
    fi
    if [ -s "$next" ]; then
      printf '\n' >> "$next"
    fi
    {
      printf '%s\n' "$SHELL_MARKER"
      printf 'export BUN_INSTALL="$HOME/.bun"\n'
      printf 'export PATH="$HOME/.local/bin:$HOME/.bun/bin:$PATH"\n'
      printf 'alias codebuddy="$HOME/.codebuddy-rotate/codebuddy-rotate.py"\n'
      printf '%s\n' "$SHELL_MARKER_END"
    } >> "$next"
  fi

  if cmp -s "$next" "$SHELL_RC"; then
    say "이미 있음  $SHELL_RC 블록"
    return 0
  fi
  cp -p "$SHELL_RC" "$SHELL_RC.codebuddy-setup.tmp"
  cat "$next" > "$SHELL_RC.codebuddy-setup.tmp"
  mv "$SHELL_RC.codebuddy-setup.tmp" "$SHELL_RC"
  say "셸 설정 갱신  $SHELL_RC"
}

interactive_login() {
  if [ "${CODEBUDDY_SETUP_NO_LOGIN:-0}" = "1" ]; then
    say "로그인 단계를 건너뜁니다."
    return 0
  fi
  if [ ! -r /dev/tty ]; then
    say "터미널이 없어 로그인을 건너뜁니다. 나중에 실행하세요."
    printf '  %s login\n  %s setup\n' "$WB_BIN" "$WB_BIN"
    return 0
  fi
  printf 'wb-codebuddy로 지금 로그인할까요? [Y/n] ' > /dev/tty
  local answer=""
  read -r answer < /dev/tty || answer=""
  case "${answer:-y}" in
    [nN]*)
      say "로그인을 건너뜁니다. 나중에 실행하세요. $WB_BIN login"
      return 0
      ;;
  esac
  if [ "$PLATFORM" != "darwin-arm64" ]; then
    say "브라우저가 열리지 않으면 화면에 찍힌 URL을 직접 여세요."
  fi
  if ! "$WB_BIN" login < /dev/tty; then
    warn "로그인에 실패했습니다. 나중에 직접 실행하세요. $WB_BIN login"
    return 0
  fi
  if ! "$WB_BIN" setup < /dev/tty; then
    warn "wb-codebuddy setup에 실패했습니다. 직접 실행하세요. $WB_BIN setup"
    return 0
  fi
  say "로그인 완료."
}

write_merge_scripts() {
  cat > "$TMP_DIR/merge-mcp.mjs" <<'NODE'
import fs from "node:fs";
import path from "node:path";

const target = process.env.CODEBUDDY_SETUP_MCP;

function isObject(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function readObject(file) {
  let text;
  try {
    text = fs.readFileSync(file, "utf8").replace(/^\uFEFF/, "");
  } catch (error) {
    if (error.code === "ENOENT") return {};
    throw error;
  }
  if (!text.trim()) return {};
  const parsed = JSON.parse(text);
  if (!isObject(parsed)) throw new Error(`${file} is not a JSON object`);
  return parsed;
}

function writeObject(file, value) {
  const dir = path.dirname(file);
  const temp = path.join(dir, `.${path.basename(file)}.${process.pid}.tmp`);
  fs.writeFileSync(temp, `${JSON.stringify(value, null, 2)}\n`, { mode: 0o600 });
  fs.renameSync(temp, file);
}

function objectAt(container, key, label) {
  const value = container[key];
  if (value === undefined) return {};
  if (!isObject(value)) throw new Error(`${label} is not a JSON object`);
  return { ...value };
}

function ensureHttp(servers, name, url, keyName) {
  const existing = isObject(servers[name]) ? servers[name] : {};
  const headers = isObject(existing.headers) ? { ...existing.headers } : {};
  const supplied = (process.env[keyName] || "").trim();
  if (supplied) headers.Authorization = `Bearer ${supplied}`;
  const next = { ...existing, type: "http", url, print: true };
  if (Object.keys(headers).length > 0) next.headers = headers;
  else delete next.headers;
  servers[name] = next;
}

function ensureStdio(servers, name, command, args) {
  const existing = isObject(servers[name]) ? servers[name] : {};
  servers[name] = { ...existing, type: "stdio", command, args, print: true };
}

try {
  const config = readObject(target);
  const servers = objectAt(config, "mcpServers", "mcpServers");
  ensureHttp(servers, "context7", "https://mcp.context7.com/mcp", "CONTEXT7_API_KEY");
  ensureHttp(servers, "exa", "https://mcp.exa.ai/mcp", "EXA_API_KEY");
  ensureStdio(servers, "codegraph", "codegraph", ["serve", "--mcp"]);
  config.mcpServers = servers;
  if (!Array.isArray(config.disabledMcpServers)) config.disabledMcpServers = [];
  writeObject(target, config);
  process.stdout.write(`MCP 설정 갱신  ${target}\n`);
} catch (error) {
  process.stderr.write(`error: ${error.message}\n`);
  process.exit(1);
}
NODE

  cat > "$TMP_DIR/merge-settings.mjs" <<'NODE'
import fs from "node:fs";
import path from "node:path";

const settingsPath = process.env.CODEBUDDY_SETUP_SETTINGS;
const home = process.env.CODEBUDDY_SETUP_HOME;
const accountsPath = process.env.CODEBUDDY_SETUP_ACCOUNTS;

const PLUGINS = [
  "pstack@pstack-claude",
  "agent-browser@codebuddy-plugins-official",
  "docx@codebuddy-plugins-official",
  "find-skills@codebuddy-plugins-official",
  "pdf@codebuddy-plugins-official",
  "playwright-cli@codebuddy-plugins-official",
  "pptx@codebuddy-plugins-official",
  "skills-sec-audit@codebuddy-plugins-official",
  "xlsx@codebuddy-plugins-official",
];

function isObject(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function readObject(file) {
  let text;
  try {
    text = fs.readFileSync(file, "utf8").replace(/^\uFEFF/, "");
  } catch (error) {
    if (error.code === "ENOENT") return {};
    throw error;
  }
  if (!text.trim()) return {};
  const parsed = JSON.parse(text);
  if (!isObject(parsed)) throw new Error(`${file} is not a JSON object`);
  return parsed;
}

function writeObject(file, value) {
  const dir = path.dirname(file);
  const temp = path.join(dir, `.${path.basename(file)}.${process.pid}.tmp`);
  fs.writeFileSync(temp, `${JSON.stringify(value, null, 2)}\n`, { mode: 0o600 });
  fs.renameSync(temp, file);
}

function objectAt(container, key, label) {
  const value = container[key];
  if (value === undefined) return {};
  if (!isObject(value)) throw new Error(`${label} is not a JSON object`);
  return { ...value };
}

function quoteForShell(value) {
  return `'${value.replace(/'/g, `'\\''`)}'`;
}

function ensureHook(hooks, name, command) {
  const groups = Array.isArray(hooks[name]) ? hooks[name].slice() : [];
  const present = groups.some(
    (group) =>
      isObject(group) &&
      Array.isArray(group.hooks) &&
      group.hooks.some((hook) => isObject(hook) && hook.command === command),
  );
  if (!present) groups.push({ hooks: [{ command, type: "command" }], matcher: "" });
  hooks[name] = groups;
}

function hasAccounts(file) {
  try {
    const parsed = JSON.parse(fs.readFileSync(file, "utf8").replace(/^\uFEFF/, ""));
    return Array.isArray(parsed) && parsed.length > 0;
  } catch {
    return false;
  }
}

try {
  const settings = readObject(settingsPath);
  const hookCommand = `sh ${quoteForShell(path.join(home, ".wb-switch", "hook.sh"))}`;

  const env = objectAt(settings, "env", "env");
  env.CODEBUDDY_BASE_URL = "https://www.codebuddy.ai/v2";
  env.CODEBUDDY_INTERNET_ENVIRONMENT = "public";
  settings.env = env;

  const codebuddy = objectAt(settings, "codebuddy", "codebuddy");
  const agentHome = objectAt(codebuddy, "agentHome", "codebuddy.agentHome");
  agentHome.orchestration = true;
  codebuddy.agentHome = agentHome;
  settings.codebuddy = codebuddy;

  settings.model = process.env.CODEBUDDY_SETUP_MODEL;
  settings.reasoningEffort = process.env.CODEBUDDY_SETUP_EFFORT;

  const permissions = objectAt(settings, "permissions", "permissions");
  permissions.defaultMode = process.env.CODEBUDDY_SETUP_PERMISSION_MODE;
  settings.permissions = permissions;

  const enabledPlugins = objectAt(settings, "enabledPlugins", "enabledPlugins");
  for (const id of PLUGINS) enabledPlugins[id] = true;
  settings.enabledPlugins = enabledPlugins;

  const hooks = objectAt(settings, "hooks", "hooks");
  ensureHook(hooks, "Stop", hookCommand);
  ensureHook(hooks, "FinalStop", hookCommand);
  settings.hooks = hooks;

  if (hasAccounts(accountsPath)) {
    settings.apiKeyHelper = path.join(home, ".codebuddy-rotate", "helper.cjs");
  }

  writeObject(settingsPath, settings);
  process.stdout.write(`설정 갱신  ${settingsPath}\n`);
} catch (error) {
  process.stderr.write(`error: ${error.message}\n`);
  process.exit(1);
}
NODE
}

summary() {
  resolve_shell_rc
  say ""
  say "설치를 마쳤습니다."
  say ""
  say "설치한 것"
  say "  Node $(node --version 2>/dev/null || printf '?'), Bun $(bun --version 2>/dev/null || printf '?') (PATH 등록)"
  say "  CodeBuddy CLI, codegraph, pstack, 공식 플러그인 8개"
  say "  wb-codebuddy 바이너리와 helper, 429 전환 래퍼, Stop 훅"
  say "  MCP 서버 context7, exa, codegraph"
  say "  settings.json과 .mcp.json 병합"
  say ""
  say "경로"
  say "  $NODE_DIR/bin/node"
  say "  $BUN_DIR/bin/bun"
  say "  $WB_BIN"
  say "  $ROTATE_DIR/helper.cjs"
  say "  $ROTATE_DIR/codebuddy-rotate.py"
  say "  $HOOK_SCRIPT"
  say "  $SETTINGS"
  say "  $MCP_CONFIG"
  say "  $PSTACK_MODELS"
  say ""
  say "다음 단계"
  say "  $WB_BIN login"
  say "  $WB_BIN setup"
  if [ "$PLATFORM" = "darwin-arm64" ]; then
    say "  exec zsh"
  else
    case "$SHELL_RC" in
      *.zshrc) say "  exec zsh" ;;
      *) say "  source ~/.bashrc" ;;
    esac
  fi
  say "  codebuddy"
  if [ -z "${CONTEXT7_API_KEY:-}" ] && [ -z "${EXA_API_KEY:-}" ]; then
    say ""
    say "API 키는 쓰지 않았습니다. 필요하면 CONTEXT7_API_KEY와 EXA_API_KEY를 export한 뒤 다시 실행하세요."
  fi
  say ""
}

main() {
  resolve_platform
  resolve_shell_rc

  TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "$TMP_DIR"' EXIT
  write_merge_scripts

  mkdir -p "$LOCAL_BIN" "$CB_DIR" "$BUN_DIR/bin"
  PATH="$LOCAL_BIN:$BUN_DIR/bin:$PATH"
  export PATH

  say "CodeBuddy 환경을 설치합니다. ($REPO)"
  install_dependencies
  install_codebuddy_cli
  install_codegraph
  install_plugins
  install_wb_codebuddy
  merge_mcp
  merge_settings
  install_pstack_models
  install_shell_block
  interactive_login
  summary
}

main "$@"
