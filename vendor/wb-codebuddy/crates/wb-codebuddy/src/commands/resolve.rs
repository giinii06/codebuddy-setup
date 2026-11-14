use serde_json::Value;
use wb_codebuddy_core::modules::account;

use crate::Result;

/// 계정 id → 1부터 시작하는 번호 → 이메일·닉네임·표시 이름 순으로 찾는다.
pub fn resolve(accounts: &[Value], query: &str) -> Result<Value> {
    if let Some(found) = accounts
        .iter()
        .find(|account| account::get_str(account, "id").as_deref() == Some(query))
    {
        return Ok(found.clone());
    }
    if let Ok(index) = query.parse::<usize>() {
        if index >= 1 && index <= accounts.len() {
            return Ok(accounts[index - 1].clone());
        }
    }
    let matches: Vec<&Value> = accounts
        .iter()
        .filter(|account| {
            identities(account)
                .iter()
                .any(|value| value.eq_ignore_ascii_case(query))
        })
        .collect();
    match matches.as_slice() {
        [only] => Ok((*only).clone()),
        [] => Err(format!("계정을 찾을 수 없습니다: {query}")),
        _ => Err("여러 계정과 일치합니다. 계정 id를 사용하세요".to_string()),
    }
}

/// 사용자가 입력할 만한 계정 이름: 이메일, 닉네임, 표시 이름.
fn identities(account: &Value) -> Vec<String> {
    let mut values: Vec<String> = ["email", "nickname"]
        .iter()
        .filter_map(|key| account::get_str(account, key))
        .collect();
    let display = account::account_display_name(account);
    if display != "unknown" {
        values.push(display);
    }
    values
}

#[cfg(test)]
mod tests {
    use super::resolve;
    use serde_json::json;

    fn accounts() -> Vec<serde_json::Value> {
        vec![
            json!({"id": "a1", "email": "one@example.com"}),
            json!({"id": "a2", "email": "two@example.com"}),
            json!({"id": "a3", "nickname": "three@example.com"}),
        ]
    }

    #[test]
    fn resolves_id_email_and_one_based_index() {
        assert_eq!(resolve(&accounts(), "a2").unwrap()["id"], "a2");
        assert_eq!(resolve(&accounts(), "ONE@example.com").unwrap()["id"], "a1");
        assert_eq!(resolve(&accounts(), "2").unwrap()["id"], "a2");
        assert_eq!(resolve(&accounts(), "1").unwrap()["id"], "a1");
    }

    #[test]
    fn resolves_accounts_that_only_have_a_nickname() {
        assert_eq!(
            resolve(&accounts(), "three@example.com").unwrap()["id"],
            "a3"
        );
    }

    #[test]
    fn rejects_unknown_and_out_of_range() {
        assert!(resolve(&accounts(), "nobody@example.com").is_err());
        assert!(resolve(&accounts(), "0").is_err());
        assert!(resolve(&accounts(), "4").is_err());
    }
}
