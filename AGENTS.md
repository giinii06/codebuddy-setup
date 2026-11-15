# CodeBuddy 설치 런북

이 저장소를 받은 Codex가 WSL Ubuntu에서 설치를 끝내기 위한 지침입니다. 사용자가 "알아서 해줘"라고 하면 이 문서를 끝까지 실행합니다.

## 대상 확인

다음을 실행해 환경을 확인합니다.

```sh
uname -s
uname -m
grep -i microsoft /proc/version
```

`uname -s`가 `Linux`이고 `uname -m`이 `x86_64`이면 진행합니다. `/proc/version`에 `microsoft`가 있으면 WSL입니다. `/proc/version`에서 아무것도 출력되지 않으면 WSL이 아닙니다. Windows PowerShell이나 cmd에서 실행 중이면 멈추고 WSL Ubuntu 셸에서 다시 실행하라고 알립니다. macOS Apple Silicon도 지원하지만 이 런북은 WSL을 기준으로 합니다.

## 설치

저장소 루트에서 실행합니다. 네트워크가 필요하고 몇 분 걸립니다.

```sh
CODEBUDDY_SETUP_NO_LOGIN=1 bash install.sh
```

`CODEBUDDY_SETUP_NO_LOGIN=1`은 대화형 로그인을 건너뜁니다. 에이전트가 프롬프트에서 멈추지 않게 합니다. 설치 스크립트는 `sudo`를 쓰지 않고 모든 파일을 `$HOME` 아래에 둡니다. 이미 설치된 항목은 건너뛰므로 다시 실행해도 안전합니다.

저장소를 아직 받지 않았다면 다음을 실행합니다.

```sh
git clone https://github.com/giinii06/codebuddy-setup.git
cd codebuddy-setup
CODEBUDDY_SETUP_NO_LOGIN=1 bash install.sh
```

설치가 실패하면 출력에서 `오류`로 시작하는 줄을 읽습니다. 원인을 고친 뒤 같은 명령을 다시 실행합니다. `경고`로 시작하는 줄이 있으면 설치는 끝났지만 일부 항목이 빠졌다는 뜻입니다. `경고` 줄도 함께 보고합니다.

Codex 샌드박스가 `$HOME` 쓰기나 네트워크를 막으면 설치가 실패합니다. 그때는 사용자에게 샌드박스 밖 실행을 승인해 달라고 요청합니다.

## 설치 확인

다음 블록이 모두 통과해야 합니다.

```sh
export PATH="$HOME/.local/bin:$HOME/.bun/bin:$PATH"
test -x "$HOME/.local/bin/wb-codebuddy"
test -f "$HOME/.codebuddy/settings.json"
test -f "$HOME/.codebuddy/.mcp.json"
test -f "$HOME/.wb-switch/hook.sh"
grep -qs 'codebuddy-setup' "$HOME/.bashrc" "$HOME/.zshrc"
command -v codebuddy
node --version
bun --version
wb-codebuddy --version
```

하나라도 실패하면 설치를 끝났다고 보고하지 않습니다. 실패한 항목과 설치 로그의 마지막 `오류` 줄을 함께 보고합니다.

## 사용자가 할 일

로그인은 브라우저를 열기 때문에 사용자가 직접 해야 합니다. 다음 명령을 그대로 알려 줍니다.

```sh
wb-codebuddy login
wb-codebuddy setup
source ~/.bashrc
codebuddy
```

zsh를 쓰면 `source ~/.bashrc` 대신 `exec zsh`를 실행합니다. 브라우저가 열리지 않으면 화면에 찍힌 URL을 직접 열라고 안내합니다.

## 하지 말 것

- `sudo`로 설치하지 않습니다.
- `~/.codebuddy/.credentials.json`이나 `~/.wb-switch/accounts.json`을 만들거나 복사하지 않습니다.
- discord 알림 훅을 설치하지 않습니다. 기존 설정에 있으면 지우지 않습니다.
- API 키를 저장소나 설정 파일에 넣지 않습니다. 필요하면 `CONTEXT7_API_KEY`와 `EXA_API_KEY` 환경 변수로 넘깁니다.
- `~/.codebuddy/pstack-models.md`가 이미 있으면 덮어쓰지 않습니다. 설치 스크립트가 보존합니다.

## 문제 해결

`codebuddy: command not found`가 나오면 `source ~/.bashrc`를 실행한 뒤 다시 시도합니다.

`python3`가 없다는 오류가 나오면 `sudo apt install -y python3`를 사용자에게 안내합니다. 설치 스크립트는 sudo를 쓰지 않습니다.

네트워크 오류가 나오면 `curl -I https://raw.githubusercontent.com`과 `curl -I https://github.com`으로 연결을 확인합니다. 다운로드가 실패하면 `오류` 줄에 막힌 URL이 들어 있습니다.
