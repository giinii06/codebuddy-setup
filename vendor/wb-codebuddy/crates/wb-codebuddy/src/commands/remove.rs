use serde_json::{json, Value};
use std::io::{BufRead, IsTerminal, Write};
use wb_codebuddy_core::modules::{account, codebuddy_cli};

use crate::commands::resolve;
use crate::{render, Result};

pub fn run(query: &str, yes: bool, json: bool) -> Result<()> {
    let accounts = account::load_accounts();
    let target = resolve::resolve(&accounts, query)?;
    let id = account::get_str(&target, "id").ok_or("계정 id가 없습니다")?;
    let name = account::account_display_name(&target);
    if is_active(&id) {
        // JSON 모드에서 stdout에 사람용 문장을 섞으면 출력이 깨진다.
        let warning = format!("경고: {name} 계정은 현재 활성 계정입니다. 삭제하면 CodeBuddy CLI가 토큰을 받지 못합니다.");
        if json {
            eprintln!("{warning}");
        } else {
            println!("{warning}");
        }
    }
    if !confirm(&name, yes)? {
        println!("취소했습니다.");
        return Ok(());
    }
    account::delete_account(&id)?;
    if json {
        return render::print_json(&json!({"removed": true, "id": id, "name": name}));
    }
    println!("삭제했습니다: {name}");
    Ok(())
}

fn is_active(id: &str) -> bool {
    codebuddy_cli::status()
        .get("activeAccountId")
        .and_then(Value::as_str)
        .is_some_and(|active| active == id)
}

/// true면 진행, false면 취소. 터미널이 아니면 물어볼 수 없으므로 오류로 끝낸다.
fn confirm(name: &str, yes: bool) -> Result<bool> {
    if yes {
        return Ok(true);
    }
    if !std::io::stdin().is_terminal() {
        return Err("확인할 수 없습니다. 삭제하려면 --yes를 붙이세요".to_string());
    }
    print!("{name} 계정을 삭제할까요? [y/N] ");
    std::io::stdout()
        .flush()
        .map_err(|error| error.to_string())?;
    let mut answer = String::new();
    std::io::stdin()
        .lock()
        .read_line(&mut answer)
        .map_err(|error| error.to_string())?;
    Ok(is_affirmative(&answer))
}

fn is_affirmative(answer: &str) -> bool {
    matches!(answer.trim().to_ascii_lowercase().as_str(), "y" | "yes")
}

#[cfg(test)]
mod tests {
    use super::is_affirmative;

    #[test]
    fn accepts_y_and_yes_in_any_case() {
        for answer in ["y", "Y", "yes", "YES", "  Yes\n"] {
            assert!(is_affirmative(answer), "{answer:?}는 승인으로 읽어야 한다");
        }
    }

    #[test]
    fn treats_everything_else_as_no() {
        for answer in ["", "\n", "n", "no", "yeah", "1"] {
            assert!(!is_affirmative(answer), "{answer:?}는 취소로 읽어야 한다");
        }
    }
}
