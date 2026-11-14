use std::path::{Path, PathBuf};
use std::process::Command;

use wb_codebuddy_core::modules::config;

use crate::Result;

const LABEL: &str = "com.wbswitch.codebuddy";

pub fn plist_path() -> PathBuf {
    config::home_dir()
        .join("Library")
        .join("LaunchAgents")
        .join(format!("{LABEL}.plist"))
}

pub fn log_path() -> PathBuf {
    config::store_dir()
        .join("logs")
        .join("codebuddy-cli.log")
}

pub fn enable() -> Result<PathBuf> {
    let exe = std::env::current_exe().map_err(|error| error.to_string())?;
    let plist = plist_path();
    if let Some(parent) = plist.parent() {
        std::fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    }
    if let Some(parent) = log_path().parent() {
        std::fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    }
    std::fs::write(&plist, render_plist(&exe, &log_path()))
        .map_err(|error| error.to_string())?;
    let _ = bootout();
    let target = format!("gui/{}", unsafe { libc::getuid() });
    let status = Command::new("launchctl")
        .args(["bootstrap", &target])
        .arg(&plist)
        .status()
        .map_err(|error| error.to_string())?;
    if !status.success() {
        return Err("launchctl bootstrap에 실패했습니다".to_string());
    }
    Ok(plist)
}

pub fn disable() -> Result<()> {
    bootout()?;
    let plist = plist_path();
    if plist.exists() {
        std::fs::remove_file(&plist).map_err(|error| error.to_string())?;
    }
    Ok(())
}

pub fn is_loaded() -> bool {
    let target = format!("gui/{}/{}", unsafe { libc::getuid() }, LABEL);
    Command::new("launchctl")
        .args(["print", &target])
        .output()
        .map(|output| output.status.success())
        .unwrap_or(false)
}

fn bootout() -> Result<()> {
    let target = format!("gui/{}/{}", unsafe { libc::getuid() }, LABEL);
    let _ = Command::new("launchctl")
        .args(["bootout", &target])
        .output();
    Ok(())
}

pub fn render_plist(exe: &Path, log: &Path) -> String {
    format!(
        r#"<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>{LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>{exe}</string>
    <string>daemon</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>ProcessType</key>
  <string>Background</string>
  <key>StandardOutPath</key>
  <string>{log}</string>
  <key>StandardErrorPath</key>
  <string>{log}</string>
</dict>
</plist>
"#,
        exe = xml_escape(&exe.to_string_lossy()),
        log = xml_escape(&log.to_string_lossy()),
    )
}

fn xml_escape(value: &str) -> String {
    value
        .replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
}

#[cfg(test)]
mod tests {
    use super::render_plist;
    use std::path::Path;

    #[test]
    fn plist_contains_program_and_log_paths() {
        let text = render_plist(
            Path::new("/Users/me/bin/wb-codebuddy"),
            Path::new("/Users/me/.wb-switch/logs/codebuddy-cli.log"),
        );
        assert!(text.contains("<string>/Users/me/bin/wb-codebuddy</string>"));
        assert!(text.contains("<string>daemon</string>"));
        assert!(text.contains("com.wbswitch.codebuddy"));
        assert!(text.contains("/Users/me/.wb-switch/logs/codebuddy-cli.log"));
    }

    #[test]
    fn plist_escapes_xml_characters() {
        let text = render_plist(Path::new("/tmp/a&b"), Path::new("/tmp/log"));
        assert!(text.contains("/tmp/a&amp;b"));
    }
}
