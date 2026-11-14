use serde_json::Value;
use unicode_width::UnicodeWidthStr;

use crate::Result;

pub fn print_json(value: &Value) -> Result<()> {
    let text = serde_json::to_string_pretty(value).map_err(|error| error.to_string())?;
    println!("{text}");
    Ok(())
}

fn pad(text: &str, width: usize) -> String {
    let used = UnicodeWidthStr::width(text);
    let mut out = String::with_capacity(text.len() + width.saturating_sub(used));
    out.push_str(text);
    out.push_str(&" ".repeat(width.saturating_sub(used)));
    out
}

fn text(value: &Value, key: &str) -> String {
    match value.get(key) {
        Some(Value::String(text)) if !text.trim().is_empty() => text.clone(),
        Some(Value::Number(number)) => number.to_string(),
        _ => "-".to_string(),
    }
}

fn number(value: &Value) -> u64 {
    value.as_u64().unwrap_or(0)
}

pub fn comma(value: u64) -> String {
    let digits = value.to_string();
    let mut out = String::new();
    for (index, ch) in digits.chars().enumerate() {
        if index > 0 && (digits.len() - index) % 3 == 0 {
            out.push(',');
        }
        out.push(ch);
    }
    out
}

fn format_ms(value: &Value) -> String {
    value
        .as_i64()
        .and_then(chrono::DateTime::<chrono::Utc>::from_timestamp_millis)
        .map(|time| {
            time.with_timezone(&chrono::Local)
                .format("%Y-%m-%d %H:%M")
                .to_string()
        })
        .unwrap_or_else(|| "-".to_string())
}

pub fn accounts(rows: &[Value]) -> Result<()> {
    if rows.is_empty() {
        println!("저장된 계정이 없습니다.");
        return Ok(());
    }
    println!(
        "{}  {}  {}  {}  {}  {}  {}",
        pad("#", 3),
        pad("이름", 18),
        pad("이메일", 28),
        pad("판", 6),
        pad("만료", 16),
        pad("활성", 4),
        "비고"
    );
    for row in rows {
        let mut name = text(row, "nickname");
        if let Some(display) = row.get("displayName").and_then(Value::as_str) {
            if !display.trim().is_empty() {
                name = display.to_string();
            }
        }
        let email = text(row, "email");
        let variant = match row.get("variant").and_then(Value::as_str) {
            Some("ai") => "국제",
            Some("cn") => "국내",
            _ => "-",
        };
        let expires = format_ms(row.get("expiresAt").unwrap_or(&Value::Null));
        let active = if row.get("active").and_then(Value::as_bool) == Some(true) {
            "*"
        } else {
            ""
        };
        let mut notes = Vec::new();
        if row.get("needsRelogin").and_then(Value::as_bool) == Some(true) {
            notes.push("재로그인");
        }
        if row.get("isEnterprise").and_then(Value::as_bool) == Some(true) {
            notes.push("기업");
        }
        println!(
            "{}  {}  {}  {}  {}  {}  {}",
            pad(&text(row, "index"), 3),
            pad(&name, 18),
            pad(&email, 28),
            pad(variant, 6),
            pad(&expires, 16),
            pad(active, 4),
            notes.join(", ")
        );
    }
    Ok(())
}

pub fn stats(value: &Value, requests: bool) -> Result<()> {
    let source = value.get("source").unwrap_or(&Value::Null);
    let summary = source.get("summary").unwrap_or(&Value::Null);
    let range = match value.get("rangeDays").and_then(Value::as_i64) {
        Some(days) => format!("최근 {days}일"),
        None => "전체".to_string(),
    };
    println!("CodeBuddy CLI 토큰 사용량 ({range})");
    println!(
        "총 토큰  {}",
        comma(number(summary.get("total").unwrap_or(&Value::Null)))
    );
    println!(
        "입력 {}  출력 {}  캐시 읽기 {}  캐시 쓰기 {}",
        comma(number(summary.get("input").unwrap_or(&Value::Null))),
        comma(number(summary.get("output").unwrap_or(&Value::Null))),
        comma(number(summary.get("cacheRead").unwrap_or(&Value::Null))),
        comma(number(summary.get("cacheWrite").unwrap_or(&Value::Null)))
    );
    println!(
        "요청 {}  캐시 적중률 {}",
        comma(number(summary.get("records").unwrap_or(&Value::Null))),
        match summary.get("cacheHitRate").and_then(Value::as_f64) {
            Some(rate) => format!("{:.1}%", rate * 100.0),
            None => "-".to_string(),
        }
    );
    let parse_errors = number(source.get("parseErrors").unwrap_or(&Value::Null));
    if parse_errors > 0 {
        println!("읽지 못한 파일 {}", comma(parse_errors));
    }

    print_group(source, "models", "모델", 5);
    print_group(source, "projects", "프로젝트", 5);
    print_group(source, "sessions", "세션", 5);

    if requests {
        println!();
        println!("최근 요청");
        if let Some(rows) = source.get("requests").and_then(Value::as_array) {
            for row in rows.iter().take(20) {
                println!(
                    "{}  {}  {}  {}",
                    format_ms(row.get("timestamp").unwrap_or(&Value::Null)),
                    pad(row.get("model").and_then(Value::as_str).unwrap_or("-"), 24),
                    pad(row.get("project").and_then(Value::as_str).unwrap_or("-"), 24),
                    comma(number(row.get("total").unwrap_or(&Value::Null)))
                );
            }
        }
    }
    Ok(())
}

fn print_group(source: &Value, key: &str, label: &str, limit: usize) {
    let Some(rows) = source.get(key).and_then(Value::as_array) else {
        return;
    };
    if rows.is_empty() {
        return;
    }
    println!();
    println!("{label}");
    for row in rows.iter().take(limit) {
        let name = row
            .get("title")
            .and_then(Value::as_str)
            .filter(|text| !text.trim().is_empty())
            .or_else(|| row.get("key").and_then(Value::as_str))
            .unwrap_or("-");
        println!(
            "  {}  {}",
            pad(name, 40),
            comma(number(row.get("total").unwrap_or(&Value::Null)))
        );
    }
}

pub fn refresh(rows: &[Value]) -> Result<()> {
    if rows.is_empty() {
        println!("갱신할 계정이 없습니다.");
        return Ok(());
    }
    for row in rows {
        let name = text(row, "name");
        let status = match row.get("status").and_then(Value::as_str) {
            Some("ok") => "ok".to_string(),
            _ => format!("재로그인 필요: {}", text(row, "reason")),
        };
        println!("{}  {}", pad(&name, 28), status);
    }
    Ok(())
}

pub fn import_preview(preview: &Value) -> Result<()> {
    let total = preview.get("total").and_then(Value::as_u64).unwrap_or(0);
    println!("파일의 계정 {total}개");
    if let Some(rows) = preview.get("accounts").and_then(Value::as_array) {
        for row in rows {
            let index = row.get("index").and_then(Value::as_u64).unwrap_or(0) + 1;
            let name = row.get("nickname").and_then(Value::as_str).unwrap_or("-");
            let email = row.get("email").and_then(Value::as_str).unwrap_or("-");
            let has_token = row.get("hasToken").and_then(Value::as_bool) == Some(true);
            let encrypted = row.get("encrypted").and_then(Value::as_bool) == Some(true);
            let note = if !has_token {
                "토큰 없음"
            } else if encrypted {
                "암호화"
            } else {
                ""
            };
            println!(
                "{:>3}  {}  {}  {}",
                index,
                pad(name, 18),
                pad(email, 28),
                note
            );
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::comma;

    #[test]
    fn comma_groups_thousands() {
        assert_eq!(comma(0), "0");
        assert_eq!(comma(999), "999");
        assert_eq!(comma(1_000), "1,000");
        assert_eq!(comma(1_234_567), "1,234,567");
    }
}
