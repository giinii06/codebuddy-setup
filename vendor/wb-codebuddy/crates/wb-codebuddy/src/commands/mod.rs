pub mod accounts;
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
pub mod display_field;
pub mod export;
pub mod import;
pub mod import_local;
pub mod keepalive;
pub mod login;
pub mod note;
pub mod refresh;
pub mod remove;
pub mod resolve;
pub mod setup;
pub mod stats;
pub mod status;
pub mod switch;
