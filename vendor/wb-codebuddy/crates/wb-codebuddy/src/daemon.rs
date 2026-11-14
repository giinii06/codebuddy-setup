use std::io::Write;
use std::os::unix::io::AsRawFd;
use std::time::Duration;

use serde_json::{json, Value};
use wb_codebuddy_core::modules::{config, refresh};

use crate::Result;

pub async fn run(interval_hours: u64) -> Result<()> {
    let interval = Duration::from_secs(interval_hours.max(1) * 3600);
    loop {
        if desktop_app_running() {
            log(&json!({"skipped": "desktop-app-running"}));
        } else {
            let result = refresh::run_keepalive_cycle().await;
            log(&result);
        }
        tokio::time::sleep(interval).await;
    }
}

pub(crate) fn desktop_app_running() -> bool {
    let path = config::store_dir().join("instance.lock");
    let Ok(file) = std::fs::OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .open(&path)
    else {
        return false;
    };
    let fd = file.as_raw_fd();
    let locked = unsafe { libc::flock(fd, libc::LOCK_EX | libc::LOCK_NB) } == 0;
    if locked {
        unsafe {
            libc::flock(fd, libc::LOCK_UN);
        }
        false
    } else {
        matches!(
            std::io::Error::last_os_error().raw_os_error(),
            Some(code) if code == libc::EWOULDBLOCK || code == libc::EAGAIN
        )
    }
}

fn log(value: &Value) {
    let path = config::store_dir()
        .join("logs")
        .join("codebuddy-cli-daemon.log");
    if let Some(parent) = path.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    let line = format!("{} {}\n", config::utc_iso(), value);
    if let Ok(mut file) = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)
    {
        let _ = file.write_all(line.as_bytes());
    }
}
