use serde_json::{json, Value};
use wb_codebuddy_core::modules::account;

use crate::commands::resolve;
use crate::{render, Result};

pub fn run(query: &str, text: Option<&str>, clear: bool, json: bool) -> Result<()> {
    let patch = note_patch(text, clear)?;
    let accounts = account::load_accounts();
    let target = resolve::resolve(&accounts, query)?;
    let id = account::get_str(&target, "id").ok_or("계정 id가 없습니다")?;
    let name = account::account_display_name(&target);
    let meta = account::update_account_display(&id, &patch)?;
    if json {
        return render::print_json(&meta);
    }
    if clear {
        println!("메모를 지웠습니다: {name}");
    } else {
        println!("메모를 저장했습니다: {name}");
    }
    Ok(())
}

fn note_patch(text: Option<&str>, clear: bool) -> Result<Value> {
    match (text, clear) {
        (Some(text), false) => Ok(json!({"note": text})),
        (None, true) => Ok(json!({"note": null})),
        (Some(_), true) => Err("메모와 --clear는 함께 쓸 수 없습니다".to_string()),
        (None, false) => Err("메모를 지정하세요 (텍스트 또는 --clear)".to_string()),
    }
}

#[cfg(test)]
mod tests {
    use super::note_patch;
    use serde_json::json;

    #[test]
    fn writes_the_given_note() {
        assert_eq!(
            note_patch(Some("업무용"), false).unwrap(),
            json!({"note": "업무용"})
        );
    }

    #[test]
    fn clears_the_note_with_null() {
        assert_eq!(note_patch(None, true).unwrap(), json!({"note": null}));
    }

    #[test]
    fn rejects_both_and_neither() {
        assert!(note_patch(Some("업무용"), true).is_err());
        assert!(note_patch(None, false).is_err());
    }
}
