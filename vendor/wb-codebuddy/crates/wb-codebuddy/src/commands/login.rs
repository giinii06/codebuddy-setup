use serde_json::Value;
use wb_codebuddy_core::modules::{account, oauth, variant::WbVariant};

use crate::Result;

pub async fn run(variant: WbVariant, no_open: bool, timeout: u64) -> Result<()> {
    let started = oauth::oauth_start(variant).await?;
    let login_id = started
        .get("loginId")
        .and_then(Value::as_str)
        .ok_or("loginId가 없습니다")?
        .to_string();
    let url = started
        .get("verificationUri")
        .and_then(Value::as_str)
        .ok_or("로그인 URL이 없습니다")?
        .to_string();
    println!("브라우저에서 로그인하세요.\n{url}");
    if !no_open {
        open_browser(&url);
    }
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(timeout);
    loop {
        if std::time::Instant::now() >= deadline {
            return Err("로그인 시간이 초과되었습니다".to_string());
        }
        let poll = oauth::oauth_poll(&login_id).await;
        if poll.get("done").and_then(Value::as_bool) == Some(true) {
            if let Some(error) = poll.get("error").and_then(Value::as_str) {
                return Err(error.to_string());
            }
            let result = poll.get("result").cloned().unwrap_or(Value::Null);
            println!("로그인 완료  {}", account::account_display_name(&result));
            return Ok(());
        }
        tokio::time::sleep(std::time::Duration::from_secs(2)).await;
    }
}

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
