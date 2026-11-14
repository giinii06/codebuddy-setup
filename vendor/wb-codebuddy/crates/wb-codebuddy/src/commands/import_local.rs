use wb_codebuddy_core::modules::{account, variant::WbVariant};

use crate::{render, Result};

pub fn run(variant: WbVariant, json: bool) -> Result<()> {
    let meta = account::import_local(variant)?;
    if json {
        return render::print_json(&meta);
    }
    let name = account::account_display_name(&meta);
    let id = account::get_str(&meta, "id").unwrap_or_else(|| "-".to_string());
    println!("가져왔습니다: {name} ({id})");
    Ok(())
}
