#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

failures=0
fail() {
  printf 'FAIL  %s\n' "$*" >&2
  failures=$((failures + 1))
}

say() { printf '%s\n' "$*"; }

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

mkdir -p "$tmp/bin" "$tmp/stubs" "$tmp/pkg" "$tmp/state-darwin" "$tmp/state-linux"

cat > "$tmp/stubs/codebuddy" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
state="${STUB_STATE:?}"
touch "$state/marketplaces.txt" "$state/plugins.txt"
cmd="${1:-}"
sub="${2:-}"
if [ "$cmd" = "plugin" ] && [ "$sub" = "marketplace" ]; then
  case "${3:-}" in
    list)
      printf '[{"name": "codebuddy-plugins-official", "type": "zip"}'
      if grep -Fqx 'pstack-claude' "$state/marketplaces.txt"; then
        printf ', {"name": "pstack-claude", "type": "github"}'
      fi
      printf ']\n'
      ;;
    add)
      printf '%s\n' "${4:-}" | sed 's|.*/||' >> "$state/marketplaces.txt"
      ;;
  esac
  exit 0
fi
if [ "$cmd" = "plugin" ] && [ "$sub" = "list" ]; then
  printf 'Installed plugins:\n'
  while IFS= read -r id; do
    printf '\n  > %s\n' "$id"
  done < "$state/plugins.txt"
  exit 0
fi
if [ "$cmd" = "plugin" ] && [ "$sub" = "install" ]; then
  printf '%s\n' "${3:-}" >> "$state/plugins.txt"
  exit 0
fi
exit 0
STUB

cat > "$tmp/stubs/codegraph" <<'STUB'
#!/bin/sh
exit 0
STUB

cat > "$tmp/bin/brew" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${STUB_STATE:?}/brew.log"
if [ "${1:-}" = "install" ] && [ "${2:-}" = "tencent-codebuddy/tap/codebuddy-code" ]; then
  cp "${STUB_SRC:?}/codebuddy" "${STUB_BIN:?}/codebuddy"
  chmod 755 "$STUB_BIN/codebuddy"
fi
exit 0
STUB

cat > "$tmp/bin/npm" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${STUB_STATE:?}/npm.log"
if [ "${1:-}" = "install" ]; then
  cp "${STUB_SRC:?}/codegraph" "${STUB_BIN:?}/codegraph"
  chmod 755 "$STUB_BIN/codegraph"
fi
exit 0
STUB

chmod 755 "$tmp/bin/brew" "$tmp/bin/npm" "$tmp/stubs/codebuddy" "$tmp/stubs/codegraph"

for tool in node python3; do
  src="$(command -v "$tool" 2>/dev/null || true)"
  if [ -n "$src" ]; then
    ln -sf "$src" "$tmp/bin/$tool"
  fi
done

cp "$tmp/stubs/codebuddy" "$tmp/pkg/codebuddy"
chmod 755 "$tmp/pkg/codebuddy"
tar -czf "$tmp/codebuddy-cli.tar.gz" -C "$tmp/pkg" codebuddy
CLI_SHA="$(sha256_file "$tmp/codebuddy-cli.tar.gz")"

cat > "$tmp/assert.mjs" <<'NODE'
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";

const home = process.env.TEST_HOME;
const stateDir = process.env.TEST_STATE;
const snapshotPath = process.env.TEST_SNAPSHOT;
const previousPath = process.env.TEST_PREVIOUS || "";
const platform = process.env.TEST_PLATFORM;
const rcName = process.env.TEST_RC;

const failures = [];
function check(ok, message) {
  if (!ok) failures.push(message);
}
function readJson(file) {
  return JSON.parse(fs.readFileSync(file, "utf8"));
}
function readText(file) {
  return fs.readFileSync(file, "utf8");
}
function modeOf(file) {
  return (fs.statSync(file).mode & 0o777).toString(8);
}
function digest(file) {
  return crypto.createHash("sha256").update(fs.readFileSync(file)).digest("hex");
}
function exists(file) {
  return fs.existsSync(file);
}

const settings = readJson(path.join(home, ".codebuddy/settings.json"));
const mcp = readJson(path.join(home, ".codebuddy/.mcp.json"));
const rcPath = path.join(home, rcName);
const rc = readText(rcPath);

check(settings.env?.CODEBUDDY_BASE_URL === "https://www.codebuddy.ai/v2", "env.CODEBUDDY_BASE_URL");
check(settings.env?.CODEBUDDY_INTERNET_ENVIRONMENT === "public", "env.CODEBUDDY_INTERNET_ENVIRONMENT");
check(settings.model === "deepseek-v4.1-flash", "model");
check(settings.reasoningEffort === "max", "reasoningEffort");
check(settings.permissions?.defaultMode === "fullAccess", "permissions.defaultMode");
check(settings.codebuddy?.agentHome?.orchestration === true, "codebuddy.agentHome.orchestration");
check(!("trustedDirectories" in settings), "trustedDirectories was written");

const pluginIds = [
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
for (const id of pluginIds) {
  check(settings.enabledPlugins?.[id] === true, `enabledPlugins.${id}`);
}

const hookCommands = (name) =>
  (settings.hooks?.[name] ?? []).flatMap((group) => (group.hooks ?? []).map((hook) => hook.command));
const stop = hookCommands("Stop");
const finalStop = hookCommands("FinalStop");
const expectedHook = `sh '${path.join(home, ".wb-switch/hook.sh")}'`;
check(stop.length === 1, `Stop hook count is ${stop.length}, expected 1`);
check(finalStop.length === 1, `FinalStop hook count is ${finalStop.length}, expected 1`);
check(stop[0] === expectedHook, `Stop hook command is ${JSON.stringify(stop[0])}`);
check(finalStop[0] === expectedHook, `FinalStop hook command is ${JSON.stringify(finalStop[0])}`);
check(
  ![...stop, ...finalStop].some((command) => typeof command === "string" && command.includes("discord")),
  "a hook command mentions discord",
);
check(!("apiKeyHelper" in settings), "apiKeyHelper is set without accounts.json");

check(mcp.mcpServers?.context7?.type === "http", "context7 type");
check(mcp.mcpServers?.context7?.url === "https://mcp.context7.com/mcp", "context7 url");
check(mcp.mcpServers?.context7?.print === true, "context7 print");
check(mcp.mcpServers?.context7?.headers?.Authorization === "Bearer test-context7", "context7 Authorization");
check(mcp.mcpServers?.exa?.type === "http", "exa type");
check(mcp.mcpServers?.exa?.url === "https://mcp.exa.ai/mcp", "exa url");
check(mcp.mcpServers?.exa?.headers?.Authorization === "Bearer test-exa", "exa Authorization");
check(mcp.mcpServers?.codegraph?.type === "stdio", "codegraph type");
check(mcp.mcpServers?.codegraph?.command === "codegraph", "codegraph command");
check((mcp.mcpServers?.codegraph?.args ?? []).join(" ") === "serve --mcp", "codegraph args");
check(Array.isArray(mcp.disabledMcpServers), "disabledMcpServers is an array");

const helper = path.join(home, ".codebuddy-rotate/helper.cjs");
const rotate = path.join(home, ".codebuddy-rotate/codebuddy-rotate.py");
const hookScript = path.join(home, ".wb-switch/hook.sh");
const wbBinary = path.join(home, ".local/bin/wb-codebuddy");
check(modeOf(helper) === "700", `helper.cjs mode is ${modeOf(helper)}, expected 700`);
check(modeOf(rotate) === "755", `codebuddy-rotate.py mode is ${modeOf(rotate)}`);
check(modeOf(hookScript) === "755", `hook.sh mode is ${modeOf(hookScript)}`);
check(modeOf(wbBinary) === "755", `wb-codebuddy mode is ${modeOf(wbBinary)}`);
check(readText(hookScript).includes('"$HOME/.wb-switch/hook-events.jsonl"'), "hook.sh writes hook-events.jsonl");
check(readText(rotate).includes("DEFAULT_MODEL"), "codebuddy-rotate.py content");
check(readText(helper).includes("access_token"), "helper.cjs content");

const markerCount = rc.split("# >>> codebuddy-setup >>>").length - 1;
check(markerCount === 1, `${rcName} marker count is ${markerCount}`);
check(rc.split("# <<< codebuddy-setup <<<").length - 1 === 1, `${rcName} closing marker count`);
check(rc.includes('export PATH="$HOME/.local/bin:$PATH"'), `${rcName} PATH line`);
check(rc.includes('alias codebuddy="$HOME/.codebuddy-rotate/codebuddy-rotate.py"'), `${rcName} alias line`);
if (rcName === ".bashrc") {
  check(!exists(path.join(home, ".zshrc")), ".zshrc was created for a bash login shell");
}

const models = readText(path.join(home, ".codebuddy/pstack-models.md"));
check(models.includes("inherit-parent"), "pstack-models.md content");

const installs = readText(path.join(stateDir, "plugins.txt")).split("\n").filter(Boolean);
check(installs.length === 9, `plugin install log has ${installs.length} entries, expected 9`);
check(new Set(installs).size === installs.length, `plugin install log repeats an id: ${installs.join(" ")}`);

const wbOutput = fs.readFileSync(wbBinary, "utf8");
check(wbOutput.includes(`fixture ${platform}`), `wb-codebuddy asset is not the ${platform} build`);

if (platform === "linux-amd64") {
  const cli = path.join(home, ".local/bin/codebuddy");
  check(exists(cli), "codebuddy CLI was not installed to ~/.local/bin");
  if (exists(cli)) {
    check(modeOf(cli) === "755", `codebuddy CLI mode is ${modeOf(cli)}, expected 755`);
    check(readText(cli).includes("marketplaces.txt"), "codebuddy CLI content is not the stub");
  }
  check(!exists(path.join(stateDir, "brew.log")), "brew was called on linux");
  check(
    readText(path.join(stateDir, "npm.log")).includes("install -g @colbymchenry/codegraph"),
    "npm did not install codegraph",
  );
} else {
  const brewLog = readText(path.join(stateDir, "brew.log"));
  check(brewLog.includes("install tencent-codebuddy/tap/codebuddy-code"), "brew did not install the codebuddy formula");
  check(!brewLog.includes("--cask"), "brew used --cask");
}

const snapshot = {
  stop: stop.length,
  finalStop: finalStop.length,
  markers: markerCount,
  enabledPlugins: Object.keys(settings.enabledPlugins ?? {}).length,
  mcpServers: Object.keys(mcp.mcpServers ?? {}).length,
  installs: installs.length,
  settingsDigest: digest(path.join(home, ".codebuddy/settings.json")),
  mcpDigest: digest(path.join(home, ".codebuddy/.mcp.json")),
  rcDigest: digest(rcPath),
};
fs.writeFileSync(snapshotPath, JSON.stringify(snapshot));

if (previousPath) {
  const previous = readJson(previousPath);
  for (const key of Object.keys(snapshot)) {
    check(
      previous[key] === snapshot[key],
      `second run changed ${key}: ${JSON.stringify(previous[key])} -> ${JSON.stringify(snapshot[key])}`,
    );
  }
}

if (failures.length > 0) {
  process.stderr.write(`${failures.join("\n")}\n`);
  process.exit(1);
}
process.stdout.write("assertions ok\n");
NODE

cat > "$tmp/assert-preserve.mjs" <<'NODE'
import fs from "node:fs";
import path from "node:path";

const home = process.env.TEST_HOME;
const failures = [];
function check(ok, message) {
  if (!ok) failures.push(message);
}
function readJson(file) {
  return JSON.parse(fs.readFileSync(file, "utf8"));
}

const settings = readJson(path.join(home, ".codebuddy/settings.json"));
const mcp = readJson(path.join(home, ".codebuddy/.mcp.json"));

check(
  settings.apiKeyHelper === path.join(home, ".codebuddy-rotate/helper.cjs"),
  `apiKeyHelper is ${JSON.stringify(settings.apiKeyHelper)} with accounts present`,
);
check(settings.unknownTopLevel?.keep === true, "unknown top level key was dropped");
check(JSON.stringify(settings.trustedDirectories) === '["/keep/me"]', "trustedDirectories was changed");
check(settings.enabledPlugins?.["existing@somewhere"] === true, "existing plugin entry was dropped");
check(settings.enabledPlugins?.["pstack@pstack-claude"] === true, "pstack was not enabled");

const stopGroups = settings.hooks?.Stop ?? [];
const commands = stopGroups.flatMap((group) => (group.hooks ?? []).map((hook) => hook.command));
check(commands.includes("bun run discord-notify"), "the existing discord hook was removed");
check(commands.filter((command) => command === `sh '${path.join(home, ".wb-switch/hook.sh")}'`).length === 1, "our Stop hook is missing or duplicated");
check(stopGroups.length === 2, `Stop has ${stopGroups.length} groups, expected 2`);

check(mcp.mcpServers?.keepme?.command === "keep", "an existing MCP server was dropped");
check(mcp.otherKey === 1, "an unknown MCP key was dropped");
check(JSON.stringify(mcp.disabledMcpServers) === '["off"]', "disabledMcpServers entries were removed");
check(mcp.mcpServers?.context7?.url === "https://mcp.context7.com/mcp", "context7 url was not updated");
check(
  mcp.mcpServers?.context7?.headers?.Authorization === "Bearer keep-me",
  "an existing Authorization header was overwritten without a new key",
);

if (failures.length > 0) {
  process.stderr.write(`${failures.join("\n")}\n`);
  process.exit(1);
}
process.stdout.write("assertions ok\n");
NODE

run_install() {
  local platform="$1"
  local home="$2"
  local state="$3"
  local login_shell="$4"
  local mode="$5"
  (
    export HOME="$home"
    export SHELL="$login_shell"
    export PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    export CODEBUDDY_SETUP_PLATFORM="$platform"
    export CODEBUDDY_SETUP_RAW="file://$REPO_ROOT"
    export CODEBUDDY_SETUP_RELEASE_BASE="file://$REPO_ROOT/test/fixtures"
    export CODEBUDDY_SETUP_NO_LOGIN=1
    export CONTEXT7_API_KEY=test-context7
    export EXA_API_KEY=test-exa
    export CODEBUDDY_CLI_ARCHIVE="$tmp/codebuddy-cli.tar.gz"
    export CODEBUDDY_CLI_SHA256="$CLI_SHA"
    export STUB_STATE="$state"
    export STUB_BIN="$tmp/bin"
    export STUB_SRC="$tmp/stubs"
    if [ "$mode" = "pipe" ]; then
      bash < "$REPO_ROOT/install.sh"
    else
      bash "$REPO_ROOT/install.sh"
    fi
  )
}

assert_state() {
  local home="$1"
  local state="$2"
  local platform="$3"
  local rc="$4"
  local snapshot="$5"
  local previous="$6"
  local round="$7"
  if ! TEST_HOME="$home" \
    TEST_STATE="$state" \
    TEST_PLATFORM="$platform" \
    TEST_RC="$rc" \
    TEST_SNAPSHOT="$snapshot" \
    TEST_PREVIOUS="$previous" \
    node "$tmp/assert.mjs"; then
    fail "install result does not match expectations (${platform}, round ${round})"
  fi
}

say "=== fixture self-check ==="
if grep -rEq 'ctx7sk-[0-9a-f]{8}-' "$REPO_ROOT" --exclude-dir=.git --exclude-dir=target; then
  fail "repository contains a context7 key"
fi
real_mcp="$HOME/.codebuddy/.mcp.json"
if [ -f "$real_mcp" ]; then
  while IFS= read -r token; do
    [ -n "$token" ] || continue
    if grep -rFq "$token" "$REPO_ROOT" --exclude-dir=.git --exclude-dir=target; then
      fail "repository contains a live MCP token"
    fi
  done < <(node -e '
    const fs = require("node:fs");
    const config = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    for (const server of Object.values(config.mcpServers ?? {})) {
      const auth = server?.headers?.Authorization;
      if (typeof auth === "string") {
        const token = auth.replace(/^Bearer\s+/i, "").trim();
        if (token.length >= 16) console.log(token);
      }
    }
  ' "$real_mcp")
fi
if ! cmp -s <(bash "$REPO_ROOT/test/fixtures/wb-codebuddy-darwin-arm64") <(printf 'wb-codebuddy fixture darwin-arm64\n'); then
  fail "darwin fixture does not identify itself"
fi

say "=== linux-amd64: first run (piped) ==="
linux_home="$tmp/home-linux"
if ! run_install linux-amd64 "$linux_home" "$tmp/state-linux" /bin/bash pipe > "$tmp/linux.log" 2>&1; then
  cat "$tmp/linux.log"
  fail "install.sh failed for linux-amd64"
fi
assert_state "$linux_home" "$tmp/state-linux" linux-amd64 .bashrc "$tmp/snap-linux.json" "" 1

say "=== darwin-arm64: first run (piped) ==="
darwin_home="$tmp/home-darwin"
if ! run_install darwin-arm64 "$darwin_home" "$tmp/state-darwin" /bin/zsh pipe > "$tmp/darwin1.log" 2>&1; then
  cat "$tmp/darwin1.log"
  fail "install.sh failed for darwin-arm64 on the first run"
fi
assert_state "$darwin_home" "$tmp/state-darwin" darwin-arm64 .zshrc "$tmp/snap1.json" "" 1

say "=== darwin-arm64: second run (file) ==="
if ! run_install darwin-arm64 "$darwin_home" "$tmp/state-darwin" /bin/zsh file > "$tmp/darwin2.log" 2>&1; then
  cat "$tmp/darwin2.log"
  fail "install.sh failed for darwin-arm64 on the second run"
fi
assert_state "$darwin_home" "$tmp/state-darwin" darwin-arm64 .zshrc "$tmp/snap2.json" "$tmp/snap1.json" 2

if [ ! -x "$tmp/bin/codebuddy" ]; then
  fail "the darwin run did not resolve codebuddy from the brew stub"
fi

if ! cmp -s "$REPO_ROOT/config/pstack-models.md" "$darwin_home/.codebuddy/pstack-models.md"; then
  fail "pstack-models.md differs from the repository copy"
fi
if ! grep -Fq '이미 있음  pstack@pstack-claude' "$tmp/darwin2.log"; then
  fail "the second run reinstalled pstack instead of skipping it"
fi
if ! grep -Fq '이미 있음  codebuddy' "$tmp/darwin2.log"; then
  fail "the second run did not report an already present codebuddy CLI"
fi
if ! grep -Fq '체크섬 확인  wb-codebuddy-darwin-arm64' "$tmp/darwin1.log"; then
  fail "the first run did not verify the wb-codebuddy checksum"
fi
if ! grep -Fq '체크섬 확인  codebuddy-cli.tar.gz' "$tmp/linux.log"; then
  fail "the linux run did not verify the codebuddy CLI checksum"
fi
if ! grep -Fq '로컬 CodeBuddy CLI 압축 파일' "$tmp/linux.log"; then
  fail "the linux run did not use the stubbed CodeBuddy CLI archive"
fi

say "=== darwin-arm64: merge into an existing config ==="
preserve_home="$tmp/home-preserve"
mkdir -p "$preserve_home/.codebuddy" "$preserve_home/.wb-switch" "$tmp/state-preserve"
cat > "$preserve_home/.codebuddy/settings.json" <<'JSON'
{
  "apiKeyHelper": "/old/helper.cjs",
  "unknownTopLevel": { "keep": true },
  "hooks": {
    "Stop": [
      { "hooks": [{ "command": "bun run discord-notify", "type": "command" }], "matcher": "" }
    ]
  },
  "enabledPlugins": { "existing@somewhere": true },
  "trustedDirectories": ["/keep/me"]
}
JSON
cat > "$preserve_home/.codebuddy/.mcp.json" <<'JSON'
{
  "mcpServers": {
    "keepme": { "type": "stdio", "command": "keep" },
    "context7": { "type": "http", "url": "https://old.example/mcp", "headers": { "Authorization": "Bearer keep-me" } }
  },
  "otherKey": 1,
  "disabledMcpServers": ["off"]
}
JSON
printf '[{"id": "acc_1", "access_token": "x"}]\n' > "$preserve_home/.wb-switch/accounts.json"

if ! (
  export HOME="$preserve_home"
  export SHELL=/bin/zsh
  export PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  export CODEBUDDY_SETUP_PLATFORM=darwin-arm64
  export CODEBUDDY_SETUP_RAW="file://$REPO_ROOT"
  export CODEBUDDY_SETUP_RELEASE_BASE="file://$REPO_ROOT/test/fixtures"
  export CODEBUDDY_SETUP_NO_LOGIN=1
  export STUB_STATE="$tmp/state-preserve"
  export STUB_BIN="$tmp/bin"
  export STUB_SRC="$tmp/stubs"
  unset CONTEXT7_API_KEY EXA_API_KEY
  bash "$REPO_ROOT/install.sh"
) > "$tmp/preserve.log" 2>&1; then
  cat "$tmp/preserve.log"
  fail "install.sh failed when merging into an existing config"
fi
if ! TEST_HOME="$preserve_home" node "$tmp/assert-preserve.mjs"; then
  fail "existing configuration was not preserved"
fi

if [ "$failures" -gt 0 ]; then
  printf '\nFAIL  %s checks failed\n' "$failures" >&2
  exit 1
fi

printf '\nPASS  install.sh passed every check on darwin-arm64 and linux-amd64\n'
