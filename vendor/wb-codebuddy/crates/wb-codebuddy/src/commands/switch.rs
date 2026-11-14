use serde_json::Value;
use wb_codebuddy_core::modules::{account, codebuddy_cli};

use crate::commands::resolve;
use crate::{render, Result};

pub fn run(query: &str, json: bool) -> Result<()> {
    let accounts = account::load_accounts();
    let target = resolve::resolve(&accounts, query)?;
    let id = account::get_str(&target, "id").ok_or("계정 id가 없습니다")?;
    let status = codebuddy_cli::status();
    if status.get("configured").and_then(Value::as_bool) != Some(true) {
        return Err(
            "apiKeyHelper가 설정되지 않았습니다. 먼저 `wb-codebuddy setup`을 실행하세요".to_string(),
        );
    }
    let result = codebuddy_cli::switch_active_account(&id)?;
    if json {
        return render::print_json(&result);
    }
    println!(
        "{}",
        result
            .get("message")
            .and_then(Value::as_str)
            .unwrap_or("계정을 전환했습니다")
    );
    if result.get("cliClosed").and_then(Value::as_bool) == Some(true) {
        println!(
            "실행 중이던 CodeBuddy CLI {}개를 종료했습니다.",
            result
                .get("closedProcessCount")
                .and_then(Value::as_u64)
                .unwrap_or(0)
        );
    }
    Ok(())
}
