use serde_json::json;
use std::path::Path;
use wb_codebuddy_core::modules::{account, export_import};

use crate::{render, Result};

pub fn run(out: &Path, all: bool, ids: &[String], json: bool) -> Result<()> {
    let accounts = account::load_accounts();
    let selected: Vec<String> = if all {
        accounts
            .iter()
            .filter_map(|account| account::get_str(account, "id"))
            .collect()
    } else if ids.is_empty() {
        return Err("내보낼 계정을 지정하세요 (--all 또는 --id)".to_string());
    } else {
        ids.to_vec()
    };
    let path = if out.is_absolute() {
        out.to_path_buf()
    } else {
        std::env::current_dir()
            .map_err(|error| error.to_string())?
            .join(out)
    };
    let path_text = path.to_string_lossy().to_string();
    let written = export_import::export_accounts_to_path(&selected, &path_text)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&written, std::fs::Permissions::from_mode(0o600))
            .map_err(|error| error.to_string())?;
    }
    let exported = accounts
        .iter()
        .filter(|account| {
            account::get_str(account, "id").is_some_and(|id| selected.contains(&id))
        })
        .count();
    if json {
        return render::print_json(&json!({"path": written, "count": exported}));
    }
    println!("{exported}개 계정을 내보냈습니다.\n{written}");
    println!("이 파일에는 토큰이 들어 있습니다. 안전하게 보관하세요.");
    Ok(())
}
