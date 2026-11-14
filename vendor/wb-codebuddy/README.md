# wb-codebuddy

CodeBuddy CLI 계정 관리 CLI. macOS와 Linux(WSL2)를 지원한다.

여러 CodeBuddy CLI 계정을 OAuth로 등록해 두고, 명령 한 줄로 활성 계정을 바꾸고, 백업하고, 토큰 사용량을 확인한다. 데스크톱 앱 없이 터미널에서만 동작하며, 계정 저장소는 기존 `workbuddy-switch` 앱과 같은 `~/.wb-switch/accounts.json`을 공유한다.

## 어떻게 동작하나

CodeBuddy CLI는 자체 인증 파일을 쓰지 않는다. macOS에서는 `~/.codebuddy/settings.json`의 `apiKeyHelper`가 토큰을 공급하는 구조다.

```
CodeBuddy CLI
  └─ apiKeyHelper: node ~/.codebuddy-rotate/helper.cjs
       ├─ 읽기: ~/.codebuddy-rotate/state.json  (active, activeAccountId)
       └─ 읽기: ~/.wb-switch/accounts.json      (실제 access/refresh 토큰)
```

`wb-codebuddy switch`는 `state.json`의 `activeAccountId`만 바꾼다. CLI가 다음 요청 때 helper를 다시 호출하면 새 계정 토큰이 자동으로 공급된다. `setup`은 `settings.json`에 helper 경로를 심고 helper 스크립트를 설치한다.

## 요구 사항

- macOS(Apple Silicon) 또는 Linux(WSL2 Ubuntu 22.04/24.04, x86_64)
- CodeBuddy CLI 설치 및 최소 1회 실행
- Node.js — helper가 `node <script>`로 실행되므로 PATH에 `node`가 있어야 한다
- Rust 1.75+ (소스에서 빌드할 때만)

Linux에서는 `autostart`가 동작하지 않는다. 토큰 갱신 루프를 자동으로 돌리려면 systemd user service로 `wb-codebuddy daemon`을 등록한다. 로그인 시 브라우저는 `xdg-open`, `wslview` 순으로 열고, 둘 다 없으면 WSL에서 `cmd.exe`로 넘어간다. 그래도 열리지 않으면 출력된 URL을 직접 연다.

## 설치

```sh
git clone git@github.com:giinii06/wb-codebuddy.git
cd wb-codebuddy
cargo install --path crates/wb-codebuddy
```

`~/.cargo/bin/wb-codebuddy`에 설치된다. 릴리스 바이너리를 쓰려면:

```sh
cargo build --release
cp target/release/wb-codebuddy /usr/local/bin/
```

## 처음 설정

```sh
# 1. 계정 추가 (브라우저가 열리고, 로그인하면 자동으로 저장된다)
wb-codebuddy login

# 2. apiKeyHelper 설치
wb-codebuddy setup

# 3. 상태 확인
wb-codebuddy status
```

`login`은 국제판(`ai`)이 기본이다. 국내판 계정은 `--variant cn`을 붙인다.

## 명령

| 명령 | 설명 |
| --- | --- |
| `login [--variant ai\|cn] [--no-open] [--timeout 600]` | OAuth로 계정을 추가한다 |
| `accounts [--variant ai\|cn]` | 저장된 계정을 번호·이메일·활성 여부와 함께 나열한다 |
| `status` | helper 설정 여부, 인증 방식, 현재 계정, 계정 수, 상태 파일 경로 |
| `setup` | `apiKeyHelper`를 설치하거나 갱신한다 |
| `switch <계정>` | 활성 계정을 바꾼다 |
| `remove <계정> [--yes]` | 계정을 삭제한다. 터미널이 아니면 `--yes`가 필요하다 |
| `note <계정> [텍스트] [--clear]` | 계정에 메모를 붙이거나 지운다 |
| `display-field <계정> nickname\|phone\|note` | 계정 목록에 표시할 필드를 고른다 |
| `refresh [<계정> \| --all]` | 토큰을 지금 갱신한다 |
| `keepalive [--days N]` | 데몬의 갱신 대상을 보여주거나 설정한다 |
| `export --out <파일> (--all \| --id <id>...)` | 계정을 JSON으로 내보낸다 |
| `import <파일> [--all \| --index <n>...] [--dry-run]` | JSON에서 계정을 가져온다 |
| `import-local [--variant ai\|cn]` | 이 Mac의 WorkBuddy 로그인 정보를 계정으로 가져온다 |
| `stats [--days 7\|30\|90] [--requests]` | CodeBuddy CLI 토큰 사용량 |
| `autostart enable\|disable\|status` | macOS 로그인 시 자동 실행 |
| `daemon [--interval-hours 24]` | 토큰 갱신 루프 (launchd가 호출) |

모든 명령에 `--json`을 붙이면 기계가 읽기 좋은 JSON으로 출력한다.

### 계정 전환

```sh
wb-codebuddy accounts
#   #    이름                이메일  판    만료              활성  비고
#   1    a@example.com       -       국제  2027-11-14 14:24
#   2    b@example.com       -       국제  2027-11-14 16:19  *

wb-codebuddy switch 2              # 번호
wb-codebuddy switch b@example.com  # 이메일·닉네임 (중복 없을 때만)
wb-codebuddy switch acc_xxxxx      # 계정 id
```

국제판 계정은 `email` 필드 없이 `nickname`에 주소가 들어 있는 경우가 많다. `switch`는 이메일, 닉네임, 표시 이름을 모두 받는다.

전환 전에 실행 중인 CodeBuddy CLI 프로세스를 먼저 종료한다. 그래야 CLI가 새 토큰으로 다시 시작한다. `setup`을 한 번도 하지 않았으면 `switch`는 거부한다.

### 429 자동 전환

한도에 걸려 `429 usage exceeds frequency limit`이 뜨면 다음 계정으로 넘어가 그 턴을 이어서 실행한다. CLI는 프로세스가 살아 있는 동안 helper 토큰을 캐시하므로, 실행 중인 세션 안에서 계정을 바꾸는 것으로는 해결되지 않는다. 그래서 래퍼가 CLI 프로세스를 소유하고, 재시작하는 방식으로 처리한다.

```sh
# ~/.zshrc
alias codebuddy='/path/to/wb-codebuddy/scripts/codebuddy-rotate.py'
```

동작 순서:

1. CLI를 `--session-id <uuid>`로 띄운다.
2. `~/.wb-switch/hook-events.jsonl`에서 같은 세션의 `Stop` 이벤트를 감시한다.
3. `stop_reason`이 `failed`이고 마지막 메시지가 429면 CLI를 종료한다.
4. 프로세스가 끝난 뒤 `state.json`을 다음 계정으로 바꾼다. 살아 있는 프로세스가 있는 채로 바꾸면 데스크톱 앱의 귀속 규칙이 깨진다.
5. `--resume <session-id> "Continue from where you left off…"`로 대화를 이어간다.

계정마다 딱 한 번씩만 시도한다. 이미 429를 맞은 계정은 다시 고르지 않고, 전부 실패하면 더 돌지 않는다. 이때는 CLI를 죽이지 않고 그대로 두어 진짜 429가 그대로 남는다(대화형이면 화면에 에러가 보인 채로, `-p`면 그 상태로 종료). 요약 한 줄과 리셋 시각을 출력한다.

```
codebuddy-rotate: no usable account left after 4 tries, usage resets at 2026-11-15 13:50:25 UTC+8
```

진행 상황은 `~/.wb-switch/logs/codebuddy-rotate.log`에 남는다.

- 429 판정은 문구가 아니라 `Stop` 훅 이벤트로 한다. 모델이 답변에서 429를 언급해도 전환하지 않는다.
- `--resume`으로 세션을 되살리면 마지막 assistant 메시지(이전 계정의 429 문구)가 그대로 재생될 수 있다. 문구 끝 `(requestId/sessionId)`의 requestId가 이번 프로세스 시작보다 이전이면 무시한다.
- `--continue`처럼 세션 id를 모르는 실행은 현재 디렉터리로 이벤트를 고르고, 재시작도 `-c`로 이어간다.
- `--model`을 지정하지 않으면 `deepseek-v4.1-flash`로 고정한다. 과금되는 `deepseek-v4.1-flash-sg`가 선택기에 같은 이름으로 보이기 때문이다.
- 래퍼를 건너뛰려면 `command codebuddy`. `--version`, `config`, `mcp` 같은 하위 명령은 그대로 CLI로 넘긴다.
- `Stop` 훅이 `~/.codebuddy/settings.json`에 걸려 있어야 한다. 데스크톱 앱의 `setup`이 설치하며, 없으면 429를 감지하지 못한다.

### 계정 정리

```sh
wb-codebuddy note 2 "업무용"        # 메모 추가
wb-codebuddy note 2 --clear         # 메모 삭제
wb-codebuddy display-field 2 note   # 목록에 메모를 표시
wb-codebuddy import-local           # 이 Mac의 WorkBuddy 로그인 가져오기
wb-codebuddy remove 2 --yes         # 계정 삭제
```

`remove`는 터미널에서 확인을 한 번 묻는다. 스크립트에서는 `--yes`를 붙인다. 현재 활성 계정을 지우면 CLI가 토큰을 받지 못하므로 먼저 다른 계정으로 전환한다. `remove`는 경고만 출력하고 진행한다.

`note`는 최대 24자다. `display-field`는 `accounts` 목록과 메시지에 쓸 이름을 고른다. `note`를 고르면 메모가 이름 자리에 온다. 기본 순서는 이메일, 닉네임, uid다.

### 토큰 갱신

```sh
wb-codebuddy refresh 2        # 한 계정
wb-codebuddy refresh --all    # 전부
wb-codebuddy keepalive --days 3
```

`refresh`는 refresh 토큰으로 access 토큰을 즉시 갱신한다. 데스크톱 앱이 실행 중이면 경고를 출력한다. 두 프로세스가 같은 refresh 토큰을 동시에 회전시키면 한쪽이 실패하기 때문이다.

`keepalive`는 데몬이 읽는 `keepalive_days`를 바꾼다. 0이면 매 주기마다 모든 계정을 갱신하고, 3이면 만료가 3일 안으로 남은 계정만 갱신한다.

### 백업과 복구

```sh
wb-codebuddy export --out backup.json --all
wb-codebuddy export --out one.json --id acc_xxxxx

wb-codebuddy import backup.json --dry-run   # 미리보기
wb-codebuddy import backup.json --all       # 전부 가져오기
wb-codebuddy import backup.json --index 2   # 2번째 계정만 (1부터 시작)
```

내보낸 파일에는 access/refresh 토큰이 평문으로 들어 있다. `export`는 파일 권한을 `0600`으로 설정하지만, 저장 위치와 보관 기간은 직접 관리해야 한다.

### 토큰 사용량

```sh
wb-codebuddy stats --days 7
wb-codebuddy stats --days 30 --requests
```

`~/.codebuddy/projects` 아래의 세션 JSONL을 스캔해 총 토큰, 캐시 적중률, 모델별·프로젝트별·세션별 상위 사용량을 보여준다. 세션 기록이 복사된 경우 지문으로 중복을 제거한다. `--days`를 생략하면 전체 기간.

### 자동 실행

```sh
wb-codebuddy autostart enable
wb-codebuddy autostart status
wb-codebuddy autostart disable
```

`~/Library/LaunchAgents/com.wbswitch.codebuddy.plist`를 만들고 `launchctl bootstrap gui/<uid>`로 등록한다. `RunAtLoad` + `KeepAlive`라서 로그인할 때 시작하고 죽으면 다시 뜬다. 로그는 `~/.wb-switch/logs/codebuddy-cli.log`.

데몬은 24시간마다 토큰 갱신 주기를 한 번 돌린다. `keepalive --days`로 갱신 대상을 좁힐 수 있다. 데스크톱 앱(`workbuddy-switch`)이 켜져 있으면 `~/.wb-switch/instance.lock`을 `flock`으로 확인하고 그 회차를 건너뛴다. 두 프로세스가 같은 refresh 토큰을 동시에 회전시켜 `invalid_grant`가 나는 것을 막기 위해서다. 건너뛴 사실은 `~/.wb-switch/logs/codebuddy-cli-daemon.log`에 남는다.

## 파일

| 경로 | 역할 |
| --- | --- |
| `~/.wb-switch/accounts.json` | 계정 저장소. 데스크톱 앱과 공유 |
| `~/.codebuddy/settings.json` | `apiKeyHelper` 설정 |
| `~/.codebuddy-rotate/helper.cjs` | 토큰 공급 스크립트 |
| `~/.codebuddy-rotate/state.json` | 활성 계정 인덱스와 id |
| `~/.wb-switch/instance.lock` | 데스크톱 앱 실행 여부 감지 |
| `~/.wb-switch/hook-events.jsonl` | `Stop` 훅 이벤트 (429 자동 전환이 읽는다) |
| `~/.wb-switch/logs/` | 자동 실행·데몬·429 전환 로그 |

`WB_SWITCH_HOME`을 설정하면 `~/.wb-switch`, `~/.codebuddy`, `~/.codebuddy-rotate`가 모두 그 아래로 옮겨진다. 실제 계정을 건드리지 않고 시험할 때 쓴다.

```sh
WB_SWITCH_HOME=/tmp/wb-test wb-codebuddy accounts
```

## 주의

- `switch`는 실행 중인 CodeBuddy CLI를 종료한다. 작업 중이면 먼저 저장한다.
- `remove`는 되돌릴 수 없다. 지우기 전에 `export`로 백업한다.
- `export` 결과물은 자격 증명이다. Git에 커밋하거나 공유하지 않는다.
- 국내판(`cn`)과 국제판(`ai`) 계정은 서로 다른 도메인을 쓴다. `login --variant`와 `accounts --variant`로 구분한다.
- 데스크톱 앱과 동시에 쓰는 것은 안전하지만, 토큰 갱신은 한쪽만 해야 한다. 자동 실행 데몬을 켜 두면 이 조정은 자동으로 된다.

## 개발

```sh
cargo check --workspace
cargo test --workspace
```

```
crates/wb-core        계정·OAuth·helper·통계 로직 (Tauri 의존 없음)
crates/wb-codebuddy   CLI 표면 (clap), launchd, 데몬
```

## 라이선스

MIT
