# codebuddy-setup

이 맥의 CodeBuddy CLI 환경을 macOS와 Windows 11 WSL2에서 한 줄로 재현합니다.

CodeBuddy CLI, pstack, 공식 플러그인, MCP 서버, wb-codebuddy를 설치하고 설정 파일을 병합합니다. 설치 스크립트는 여러 번 실행해도 같은 상태로 수렴합니다.

## 지원 플랫폼

| 플랫폼 | 상태 |
| --- | --- |
| macOS Apple Silicon (arm64) | 지원 |
| Windows 11 WSL2 Ubuntu 22.04/24.04 (x86_64) | 지원 |
| macOS Intel | 지원하지 않음 |
| Windows 네이티브 (PowerShell, cmd) | 지원하지 않음 |
| Linux arm64 | 지원하지 않음 |

지원하지 않는 환경에서 실행하면 설치 스크립트가 이유를 출력하고 멈춥니다.

## 검증 범위

macOS Apple Silicon은 이 저장소를 만든 맥에서 끝까지 실행해 확인했습니다. 설치는 물론 설정 병합, 재실행, 설치된 wb-codebuddy 바이너리 실행까지 포함합니다.

Node와 Bun 자동 설치는 macOS에서 실제 배포판을 내려받아 체크섬, 버전, 새 셸의 PATH 해석까지 확인했습니다. Linux는 같은 코드 경로를 테스트 하네스의 가짜 아카이브로 검사하고, 실제 linux-x64 Node tarball과 Bun zip의 이름과 내부 구조도 대조했습니다.

Linux 경로는 실제 WSL 머신에서 아직 실행하지 않았습니다. `test/install-test.sh`가 Linux를 스텁으로 검사합니다. CodeBuddy CLI 자리에 같은 인터페이스를 흉내 내는 스텁 tarball을 넣고, `brew`와 `npm`도 스텁으로 바꿉니다. 그래서 설치 순서, 파일 배치, 권한, 설정 병합, 재실행 수렴은 검증되지만 실제 CodeBuddy CLI의 동작은 검증되지 않습니다.

공식 CodeBuddy Linux 바이너리는 172MB짜리 Bun 1.4.4 standalone 실행 파일입니다. AVX가 없는 QEMU에서는 세그폴트가 나므로 이 맥의 Docker로 실행 검증을 할 수 없습니다. WSL에서 직접 확인해야 합니다.

wb-codebuddy의 Linux 바이너리는 Rust로 빌드되어 QEMU에서도 실행됩니다. 버전 출력과 `autostart`가 macOS 전용 오류를 내는 것까지 확인했습니다.

## 설치하는 것

- CodeBuddy CLI. macOS는 Homebrew formula, Linux는 공식 tarball 2.184.0.
- Node 24 LTS와 Bun. 이미 있으면 건너뛰고, 없으면 공식 배포판을 SHA256으로 확인한 뒤 `~/.local/node`와 `~/.bun`에 설치합니다.
- pstack과 공식 플러그인 8개. pstack은 `pstack-claude` 마켓에서, 나머지는 `codebuddy-plugins-official`에서 받습니다.
- MCP 서버 context7, exa, codegraph.
- wb-codebuddy. 릴리스 바이너리, `apiKeyHelper` 스크립트, 429 자동 전환 래퍼, `Stop`/`FinalStop` 훅.
- `settings.json`과 `.mcp.json` 병합. 기존의 다른 키와 알 수 없는 항목은 보존하고, 이 저장소가 관리하는 값만 갱신합니다.
- `~/.codebuddy/pstack-models.md`. 이미 있으면 건드리지 않습니다.
- 셸 설정에 `PATH`와 `codebuddy` 별칭. 마커 블록으로 한 번만 추가합니다.

## 요구 사항

macOS는 Homebrew가 필요합니다. 없으면 설치 스크립트가 먼저 안내하고 멈춥니다. python3가 없으면 brew로 설치합니다.

WSL2 Ubuntu는 `curl`, `tar`, SHA256 도구가 필요합니다. 우분투에는 모두 들어 있습니다.

두 플랫폼 모두 Node 24 LTS와 Bun을 자동으로 설치합니다. 이미 있으면 건너뜁니다. Node가 없거나 메이저 버전이 20 미만이면 공식 tarball을 `~/.local/node`에 풀고 `~/.local/bin`에 링크합니다. Bun은 공식 zip을 `~/.bun`에 풀고 `~/.bun/bin`을 PATH에 넣습니다. python3는 우분투에 기본으로 있으므로 설치 스크립트가 직접 설치하지 않습니다. 없으면 `apt` 명령을 알려 주고 멈춥니다.

sudo는 쓰지 않습니다. 모든 파일은 홈 디렉터리 아래에 들어갑니다.

## 설치

macOS와 WSL2 모두 같은 한 줄입니다.

```sh
curl -fsSL https://raw.githubusercontent.com/giinii06/codebuddy-setup/main/install.sh | bash
```

WSL에서는 PowerShell이 아니라 WSL 셸 안에서 실행하세요.

### Codex에 맡기기

Codex CLI는 저장소 루트의 `AGENTS.md`를 자동으로 읽습니다. 저장소를 받고 Codex를 실행한 뒤 한마디만 하면 됩니다.

```sh
git clone https://github.com/giinii06/codebuddy-setup.git
cd codebuddy-setup
codex exec --trust -s danger-full-access "알아서 해줘"
```

`-s danger-full-access`는 Codex의 샌드박스를 끕니다. 설치 스크립트가 `$HOME`에 쓰고 네트워크를 쓰기 때문에 필요합니다. `--trust`는 이 저장소를 신뢰 대상으로 기록하고 MCP 명령을 샌드박스 밖에서 실행하게 합니다. 실행 전에 `install.sh` 내용을 확인하세요.

`codex exec`는 승인을 묻지 않으므로, 대화형으로 하려면 `codex -s danger-full-access -a never "알아서 해줘"`를 씁니다.

Codex는 WSL 환경을 확인하고 `CODEBUDDY_SETUP_NO_LOGIN=1 bash install.sh`로 설치합니다. 이어서 설치를 검증하고, 사용자가 직접 해야 하는 브라우저 로그인 명령을 알려 줍니다.

### API 키를 함께 넣으려면

키는 저장소에 들어 있지 않습니다. 필요하면 환경 변수로 넘깁니다.

```sh
export CONTEXT7_API_KEY=...
export EXA_API_KEY=...
curl -fsSL https://raw.githubusercontent.com/giinii06/codebuddy-setup/main/install.sh | bash
```

키를 넘기지 않으면 `Authorization` 헤더를 쓰지 않습니다. 기존 설정에 헤더가 있으면 그대로 보존합니다.

## 설치 후

```sh
wb-codebuddy login
wb-codebuddy setup
exec zsh
codebuddy
```

WSL에서 셸이 bash이면 `exec zsh` 대신 `source ~/.bashrc`를 실행합니다. 설치 스크립트가 로그인까지 물어봤다면 셸만 다시 읽으면 됩니다.

`wb-codebuddy login`은 브라우저를 엽니다. WSL에서 브라우저가 열리지 않으면 화면에 찍힌 URL을 직접 여세요. `wslu`를 설치하면 `wslview`로 자동으로 열립니다.

## 빠지는 것

이 저장소는 공개되어 있습니다. 그래서 다음은 설치하지 않습니다.

- discord 알림 훅. 원본 맥의 `~/.codebuddy/discord-notify`와 그 `Stop` 훅은 봇 토큰에 묶여 있어 제외합니다.
- CodeBuddy 자격 증명. `~/.codebuddy/.credentials.json`은 복사하지 않습니다.
- API 키. context7과 exa 키는 환경 변수로만 받습니다.
- 계정 토큰. `~/.wb-switch/accounts.json`은 만들지 않습니다. `wb-codebuddy login`이 직접 만듭니다.
- `trustedDirectories`. 원본 맥의 경로가 박혀 있어 의미가 없습니다.

## 설정 파일

| 경로 | 역할 |
| --- | --- |
| `~/.codebuddy/settings.json` | 모델, 권한 모드, 플러그인, 훅, `apiKeyHelper` |
| `~/.codebuddy/.mcp.json` | MCP 서버 정의 |
| `~/.codebuddy/pstack-models.md` | pstack 역할별 모델 |
| `~/.codebuddy-rotate/helper.cjs` | CLI에 토큰을 공급하는 스크립트. 권한 700 |
| `~/.codebuddy-rotate/codebuddy-rotate.py` | 429 자동 전환 래퍼 |
| `~/.wb-switch/hook.sh` | `Stop` 훅. 이벤트를 `~/.wb-switch/hook-events.jsonl`에 남깁니다 |
| `~/.local/bin/wb-codebuddy` | 계정 관리 바이너리 |
| `~/.local/bin/codebuddy` | Linux에서 받은 CodeBuddy CLI |
| `~/.local/node/bin/node` | Node 24 LTS. `~/.local/bin/node`가 가리킵니다 |
| `~/.bun/bin/bun` | Bun. `bunx`도 같은 디렉터리에 있습니다 |

## 보안

`permissions.defaultMode`는 원본 맥과 같게 `fullAccess`입니다. 설치 스크립트가 확인 없이 파일을 고치고 명령을 실행할 수 있다는 뜻입니다. 다르게 두려면 설치 전에 `CODEBUDDY_PERMISSION_MODE`를 설정하세요.

```sh
export CODEBUDDY_PERMISSION_MODE=default
```

wb-codebuddy 바이너리는 이 저장소의 `vendor/wb-codebuddy` 소스에서 빌드합니다. 릴리스 자산은 GitHub Actions가 만들고, 로컬 확인용으로 `scripts/build-release.sh`를 쓸 수 있습니다. 릴리스 자산은 `.sha256`과 함께 배포하고 설치 스크립트가 검증합니다. Node와 Bun도 공식 배포처의 `SHASUMS256.txt`와 대조한 뒤 설치합니다.

`apiKeyHelper`는 `~/.wb-switch/accounts.json`이 비어 있지 않은 배열일 때만 설정합니다. 계정이 없는데 먼저 걸면 helper가 종료 코드 1로 끝나 CLI가 시작하지 못합니다.

`autostart`는 launchd라서 macOS 전용입니다. Linux에서는 systemd user service로 `wb-codebuddy daemon`을 등록하세요. 자세한 내용은 `vendor/wb-codebuddy/PATCHES.md`에 있습니다.

## 문제 해결

`codebuddy` 명령이 회전 래퍼를 건너뛰게 하려면 `command codebuddy`를 씁니다. `--version`, `config`, `mcp` 같은 하위 명령은 래퍼가 그대로 CLI로 넘깁니다.

인증 상태는 `wb-codebuddy status`로 봅니다. 활성 계정, 인증 방식, 계정 수가 나옵니다.

설치된 MCP 서버는 `codebuddy mcp list`, 플러그인은 `codebuddy plugin list`로 확인합니다.

설치 후 CLI가 시작하지 않으면 `~/.wb-switch/accounts.json`을 확인하세요. 없거나 빈 배열이면 `wb-codebuddy login`을 먼저 실행합니다.

WSL에서 브라우저가 열리지 않으면 출력된 URL을 직접 엽니다. `sudo apt install -y wslu`를 설치하면 다음부터 `wslview`가 처리합니다.

`node`나 `bun`이 보이지 않으면 셸 설정을 다시 읽었는지 확인합니다. `~/.local/bin`과 `~/.bun/bin`은 설치 스크립트가 넣은 블록이 PATH에 추가합니다.

## 빌드

릴리스 자산을 만드는 곳은 `.github/workflows/release.yml` 하나입니다. `v*` 태그를 밀면 이 워크플로가 두 바이너리와 `.sha256` 두 개, 모두 네 파일을 릴리스에 올립니다. 설치 스크립트는 이 릴리스에서 내려받습니다.

- `wb-codebuddy-darwin-arm64`는 `macos-15`(arm64)에서 빌드합니다.
- `wb-codebuddy-linux-amd64`는 `ubuntu-22.04`에서 빌드합니다. glibc 2.35에 맞춰지므로 WSL Ubuntu 22.04와 24.04에서 모두 동작합니다. `ubuntu-latest`를 쓰면 요구 glibc가 올라가 22.04에서 깨집니다.

`scripts/build-release.sh`는 로컬 확인용입니다. 인자 없이 실행하면 macOS 바이너리만 만듭니다.

```sh
./scripts/build-release.sh
./scripts/build-release.sh darwin-arm64
```

Linux를 로컬에서 만들려면 `./scripts/build-release.sh linux-amd64`를 실행합니다. `rust:1-bookworm` 이미지를 `--platform linux/amd64`로 돌리므로 Apple Silicon에서는 느리고 메모리를 많이 씁니다. 실패해도 릴리스에는 영향이 없습니다. 그 경로는 선택 사항입니다.

설치 스크립트는 두 플랫폼을 모두 검사합니다.

```sh
bash test/install-test.sh
```

## 라이선스

MIT. 자세한 내용은 `LICENSE`를 보세요.

`vendor/wb-codebuddy`의 소스는 MIT이며 저작권자는 2026 wb-switch입니다. 원본은 macOS 전용이고, 이 저장소는 Linux에서 빌드되도록 패치한 사본을 담고 있습니다. 패치 내역은 `vendor/wb-codebuddy/PATCHES.md`에, 라이선스 전문은 `NOTICE`에 있습니다.
