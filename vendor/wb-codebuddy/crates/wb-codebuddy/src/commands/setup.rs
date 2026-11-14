use serde_json::Value;
use wb_codebuddy_core::modules::{account, codebuddy_cli};

use crate::{render, Result};

pub fn run(json: bool) -> Result<()> {
    if account::load_accounts().is_empty() {
        return Err("먼저 `wb-codebuddy login`으로 계정을 추가하세요".to_string());
    }
    let result = codebuddy_cli::install_helper()?;
    if json {
        render::print_json(&result)
    } else {
        println!(
            "{}",
            result
                .get("message")
                .and_then(Value::as_str)
                .unwrap_or("apiKeyHelper를 설치했습니다")
        );
        Ok(())
    }
}
