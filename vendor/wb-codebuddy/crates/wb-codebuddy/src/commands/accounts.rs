use serde_json::{json, Value};
use wb_codebuddy_core::modules::{account, codebuddy_cli, variant::WbVariant};

use crate::{render, Result};

pub fn run(variant: Option<WbVariant>, json: bool) -> Result<()> {
    let accounts = account::load_accounts();
    let status = codebuddy_cli::status();
    let active_id = status.get("activeAccountId").and_then(Value::as_str);
    let mut rows = Vec::new();
    for (index, account_value) in accounts.iter().enumerate() {
        let account_variant = WbVariant::from_account(account_value);
        if variant.is_some_and(|wanted| wanted != account_variant) {
            continue;
        }
        let mut row = account::account_meta(account_value);
        row["index"] = json!(index + 1);
        row["displayName"] = json!(account::account_display_name(account_value));
        row["active"] = json!(row.get("id").and_then(Value::as_str) == active_id);
        row["variantLabel"] = json!(match account_variant {
            WbVariant::Ai => "국제",
            WbVariant::Cn => "국내",
        });
        rows.push(row);
    }
    if json {
        render::print_json(&Value::Array(rows))
    } else {
        render::accounts(&rows)
    }
}
