use serde_json::json;
use std::path::Path;
use wb_codebuddy_core::modules::export_import;

use crate::{render, Result};

pub fn run(file: &Path, all: bool, indexes: &[usize], dry_run: bool, json: bool) -> Result<()> {
    let text = std::fs::read_to_string(file)
        .map_err(|error| format!("{}: {error}", file.display()))?;
    let preview = export_import::preview_accounts(&text)?;
    if dry_run || (!all && indexes.is_empty()) {
        if json {
            render::print_json(&preview)?;
        } else {
            render::import_preview(&preview)?;
        }
        if dry_run {
            return Ok(());
        }
        return Err("가져올 계정을 지정하세요 (--all 또는 --index)".to_string());
    }
    if indexes.iter().any(|index| *index == 0) {
        return Err("--index는 1부터 시작합니다".to_string());
    }
    let total = preview
        .get("total")
        .and_then(serde_json::Value::as_u64)
        .unwrap_or(0) as usize;
    let zero_based: Vec<usize> = if all {
        (0..total).collect()
    } else {
        indexes.iter().map(|index| index - 1).collect()
    };
    let result = export_import::import_accounts(&text, &zero_based)?;
    if json {
        render::print_json(&json!({
            "imported": result.imported,
            "skipped": result.skipped,
            "overwritten": result.overwritten,
        }))
    } else {
        println!(
            "가져옴 {}개, 덮어씀 {}개, 건너뜀 {}개",
            result.imported, result.overwritten, result.skipped
        );
        Ok(())
    }
}
