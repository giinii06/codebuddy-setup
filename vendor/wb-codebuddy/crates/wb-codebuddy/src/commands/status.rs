use serde_json::Value;
use wb_codebuddy_core::modules::codebuddy_cli;

use crate::{render, Result};

pub fn run(json: bool) -> Result<()> {
    let status = codebuddy_cli::status();
    if json {
        return render::print_json(&status);
    }
    println!("CodeBuddy CLI 상태");
    println!(
        "helper 설정  {}",
        if status.get("configured").and_then(Value::as_bool) == Some(true) {
            "됨"
        } else {
            "안 됨"
        }
    );
    println!(
        "인증 방식  {}",
        status.get("authMode").and_then(Value::as_str).unwrap_or("-")
    );
    println!(
        "현재 계정  {}",
        status
            .get("activeAccountName")
            .and_then(Value::as_str)
            .unwrap_or("없음")
    );
    println!(
        "계정 수  {}",
        status.get("accountCount").and_then(Value::as_u64).unwrap_or(0)
    );
    println!(
        "상태 파일  {}",
        status.get("statePath").and_then(Value::as_str).unwrap_or("-")
    );
    if status.get("migrationRequired").and_then(Value::as_bool) == Some(true) {
        println!("helper 업그레이드가 필요합니다. `wb-codebuddy setup`을 실행하세요.");
    }
    Ok(())
}
