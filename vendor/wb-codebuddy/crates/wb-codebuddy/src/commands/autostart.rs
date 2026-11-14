use serde_json::json;

use crate::cli::AutostartAction;
use crate::{launchd, render, Result};

pub fn run(action: AutostartAction, json: bool) -> Result<()> {
    match action {
        AutostartAction::Enable => {
            let path = launchd::enable()?;
            if json {
                render::print_json(&json!({"installed": true, "plist": path}))
            } else {
                println!("자동 실행을 켰습니다.\n{}", path.display());
                Ok(())
            }
        }
        AutostartAction::Disable => {
            launchd::disable()?;
            if json {
                render::print_json(&json!({"installed": false}))
            } else {
                println!("자동 실행을 껐습니다.");
                Ok(())
            }
        }
        AutostartAction::Status => {
            let installed = launchd::plist_path().exists();
            let loaded = launchd::is_loaded();
            if json {
                render::print_json(&json!({
                    "installed": installed,
                    "loaded": loaded,
                    "plist": launchd::plist_path(),
                    "log": launchd::log_path(),
                }))
            } else {
                println!("plist  {}", if installed { "있음" } else { "없음" });
                println!("launchd  {}", if loaded { "실행 중" } else { "중지" });
                println!("로그  {}", launchd::log_path().display());
                Ok(())
            }
        }
    }
}
