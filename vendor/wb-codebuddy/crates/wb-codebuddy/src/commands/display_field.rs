use serde_json::json;
use wb_codebuddy_core::modules::account;

use crate::cli::DisplayFieldArg;
use crate::commands::resolve;
use crate::{render, Result};

pub fn run(query: &str, field: DisplayFieldArg, json: bool) -> Result<()> {
    let accounts = account::load_accounts();
    let target = resolve::resolve(&accounts, query)?;
    let id = account::get_str(&target, "id").ok_or("계정 id가 없습니다")?;
    let name = account::account_display_name(&target);
    let meta = account::update_account_display(&id, &json!({"displayField": field.as_str()}))?;
    if json {
        return render::print_json(&meta);
    }
    println!("표시 필드를 {}(으)로 바꿨습니다: {name}", field.as_str());
    Ok(())
}
