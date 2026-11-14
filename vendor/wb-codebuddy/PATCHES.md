# Vendored patches

This directory is a copy of [wb-codebuddy](https://github.com/giinii06/wb-codebuddy)
at the commit this repo vendored. Upstream targets macOS only. The patches below
add Linux x86_64 so the same binary builds for Windows 11 WSL2. Nothing else
changed.

Re-sync with `git -C <upstream> ls-files` and re-apply these four edits.

## 1. `crates/wb-codebuddy/src/main.rs`

Upstream refuses to compile off macOS:

```rust
#[cfg(not(target_os = "macos"))]
compile_error!("wb-codebuddy supports macOS only");
```

The block is removed, and the `launchd` module is gated so Linux never links
the `launchctl` calls:

```rust
#[cfg(target_os = "macos")]
mod launchd;
```

## 2. `crates/wb-codebuddy/src/commands/mod.rs`

`commands::autostart` imports `crate::launchd`, which no longer exists off
macOS. Upstream's `pub mod autostart;` becomes a cfg pair. On Linux the module
compiles to a stub that returns an error naming the supported alternative.

```rust
#[cfg(target_os = "macos")]
pub mod autostart;
#[cfg(not(target_os = "macos"))]
pub mod autostart {
    use crate::cli::AutostartAction;
    use crate::Result;

    pub fn run(_action: AutostartAction, _json: bool) -> Result<()> {
        Err("autostart는 macOS에서만 지원합니다. Linux에서는 systemd user service를 사용하세요.".to_string())
    }
}
```

The CLI surface is unchanged. `wb-codebuddy autostart enable` still parses on
Linux and exits 1 with that message.

## 3. `crates/wb-codebuddy/src/commands/login.rs`

Upstream opens the OAuth URL with the macOS `open` binary. That becomes a call
to a platform helper:

```rust
if !no_open {
    open_browser(&url);
}
```

`open_browser` is appended to the file. macOS keeps `open`. Linux tries
`xdg-open` then `wslview`, and falls back to `cmd.exe /C start` when
`/proc/version` reports Microsoft, which is the WSL case where neither helper
is installed.

```rust
fn open_browser(url: &str) {
    #[cfg(target_os = "macos")]
    {
        let _ = std::process::Command::new("open").arg(url).spawn();
    }
    #[cfg(windows)]
    {
        let _ = std::process::Command::new("cmd")
            .args(["/C", "start", "", url])
            .spawn();
    }
    #[cfg(all(unix, not(target_os = "macos")))]
    {
        for program in ["xdg-open", "wslview"] {
            if std::process::Command::new(program).arg(url).spawn().is_ok() {
                return;
            }
        }
        let wsl = std::fs::read_to_string("/proc/version")
            .map(|version| version.to_lowercase().contains("microsoft"))
            .unwrap_or(false);
        if wsl {
            let _ = std::process::Command::new("cmd.exe")
                .args(["/C", "start", "", url])
                .spawn();
        }
    }
}
```

A spawn failure is not fatal. The URL is printed before this call, so the user
can open it by hand.

## 4. `README.md`

The first line and the requirements section now name Linux and WSL2. The
`autostart` limitation and the browser fallback order are documented there.

## What still does not work on Linux

`autostart`, because it is launchd. Use a systemd user unit:

```ini
[Unit]
Description=wb-codebuddy token refresh

[Service]
Type=oneshot
ExecStart=%h/.local/bin/wb-codebuddy daemon

[Install]
WantedBy=default.target
```

Pair it with a timer for the 24 hour cadence.

`import-local` reads the desktop app's macOS login state. It returns its
normal error when that state is absent.

Everything else, meaning `login`, `setup`, `switch`, `accounts`, `status`,
`refresh`, `keepalive`, `export`, `import`, `stats`, `note`, `display-field`,
`remove`, and `daemon`, is platform independent and runs on Linux unchanged.
