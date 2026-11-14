use serde_json::{json, Value};
use wb_codebuddy_core::modules::{account, refresh::refresh_account_token};

use crate::commands::resolve;
use crate::{daemon, render, Result};

pub async fn run(query: Option<&str>, all: bool, json: bool) -> Result<()> {
    let accounts = account::load_accounts();
    let targets: Vec<Value> = match (query, all) {
        (Some(query), false) => vec![resolve::resolve(&accounts, query)?],
        (None, true) => accounts,
        (Some(_), true) => return Err("계정과 --all은 함께 쓸 수 없습니다".to_string()),
        (None, false) => return Err("갱신할 계정을 지정하세요 (계정 또는 --all)".to_string()),
    };
    if daemon::desktop_app_running() {
        eprintln!(
            "경고: 데스크톱 앱이 실행 중입니다. 같은 refresh 토큰을 동시에 회전시키면 갱신이 실패할 수 있습니다."
        );
    }
    let mut rows = Vec::with_capacity(targets.len());
    for target in targets {
        let refreshed = refresh_account_token(target).await;
        rows.push(Outcome::from_account(&refreshed).to_json());
    }
    if json {
        return render::print_json(&json!({ "results": rows }));
    }
    render::refresh(&rows)
}

/// 한 계정의 갱신 결과. `needs_relogin` 불리언과 사유 문자열을 따로 들고 다니면
/// 둘이 어긋날 수 있어서 상태 하나로 묶는다.
enum Status {
    Ok,
    NeedsRelogin(String),
}

impl Status {
    fn from_account(account: &Value) -> Self {
        if account.get("needs_relogin").and_then(Value::as_bool) != Some(true) {
            return Self::Ok;
        }
        let reason = account::get_str(account, "needs_relogin_reason")
            .unwrap_or_else(|| "이유를 알 수 없습니다".to_string());
        Self::NeedsRelogin(reason)
    }

    fn label(&self) -> &'static str {
        match self {
            Self::Ok => "ok",
            Self::NeedsRelogin(_) => "needs_relogin",
        }
    }

    fn reason(&self) -> Option<&str> {
        match self {
            Self::Ok => None,
            Self::NeedsRelogin(reason) => Some(reason),
        }
    }
}

struct Outcome {
    id: String,
    name: String,
    status: Status,
}

impl Outcome {
    fn from_account(account: &Value) -> Self {
        Self {
            id: account::get_str(account, "id").unwrap_or_default(),
            name: account::account_display_name(account),
            status: Status::from_account(account),
        }
    }

    fn to_json(&self) -> Value {
        json!({
            "id": self.id,
            "name": self.name,
            "status": self.status.label(),
            "reason": self.status.reason(),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::Outcome;
    use serde_json::json;

    #[test]
    fn reports_refreshed_account_as_ok_without_a_reason() {
        let row = Outcome::from_account(&json!({
            "id": "a1",
            "email": "one@example.com",
            "access_token": "AT-2",
        }))
        .to_json();
        assert_eq!(row["id"], "a1");
        assert_eq!(row["name"], "one@example.com");
        assert_eq!(row["status"], "ok");
        assert_eq!(row["reason"], serde_json::Value::Null);
    }

    #[test]
    fn reports_marked_account_as_needs_relogin_with_its_reason() {
        let row = Outcome::from_account(&json!({
            "id": "a2",
            "email": "two@example.com",
            "needs_relogin": true,
            "needs_relogin_reason": "refresh token이 없어 갱신할 수 없습니다. 다시 로그인해 주세요",
        }))
        .to_json();
        assert_eq!(row["status"], "needs_relogin");
        assert!(row["reason"].as_str().unwrap().contains("refresh token"));
    }
}
