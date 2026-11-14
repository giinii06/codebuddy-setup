use serde_json::{json, Value};
use wb_codebuddy_core::modules::config;

use crate::{render, Result};

pub fn run(days: Option<u32>, json: bool) -> Result<()> {
    let mut cfg = config::load_checkin_config();
    if let Some(days) = days {
        cfg = with_keepalive_days(cfg, days);
        config::save_checkin_config(&cfg).map_err(|error| error.to_string())?;
    }
    let current = keepalive_days(&cfg);
    if json {
        return render::print_json(&json!({"keepaliveDays": current}));
    }
    if days.is_some() {
        println!("keepalive_days를 {current}(으)로 설정했습니다.");
    } else {
        println!("keepalive_days  {current}");
    }
    Ok(())
}

fn keepalive_days(cfg: &Value) -> i64 {
    cfg.get("keepalive_days")
        .and_then(Value::as_i64)
        .unwrap_or(0)
}

fn with_keepalive_days(mut cfg: Value, days: u32) -> Value {
    cfg["keepalive_days"] = json!(days);
    cfg
}

#[cfg(test)]
mod tests {
    use super::{keepalive_days, with_keepalive_days};
    use serde_json::json;

    #[test]
    fn reads_the_current_value_and_defaults_to_zero() {
        assert_eq!(keepalive_days(&json!({"keepalive_days": 3})), 3);
        assert_eq!(keepalive_days(&json!({})), 0);
    }

    #[test]
    fn changes_only_keepalive_days() {
        let cfg = with_keepalive_days(
            json!({"enabled": true, "keepalive_days": 0, "lazy_refresh_hours": 12}),
            7,
        );
        assert_eq!(cfg["keepalive_days"], 7);
        assert_eq!(cfg["enabled"], true);
        assert_eq!(cfg["lazy_refresh_hours"], 12);
    }
}
