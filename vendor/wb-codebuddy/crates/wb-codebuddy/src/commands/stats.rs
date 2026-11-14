use wb_codebuddy_core::modules::token_stats;

use crate::{render, Result};

pub fn run(days: Option<i64>, requests: bool, json: bool) -> Result<()> {
    if let Some(days) = days {
        if !matches!(days, 7 | 30 | 90) {
            return Err("--days는 7, 30, 90 중 하나여야 합니다".to_string());
        }
    }
    let value = token_stats::get_codebuddy_cli_statistics(days);
    if json {
        render::print_json(&value)
    } else {
        render::stats(&value, requests)
    }
}
