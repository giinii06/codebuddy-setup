use clap::{Parser, Subcommand, ValueEnum};
use std::path::PathBuf;
use wb_codebuddy_core::modules::variant::WbVariant;

use crate::commands;
use crate::daemon;
use crate::Result;

#[derive(Parser)]
#[command(name = "wb-codebuddy", version, about = "CodeBuddy CLI 계정 관리 도구")]
pub struct Cli {
    /// 결과를 JSON으로 출력한다.
    #[arg(long, global = true)]
    pub json: bool,
    #[command(subcommand)]
    pub command: Command,
}

#[derive(Subcommand)]
pub enum Command {
    /// OAuth로 계정을 추가한다.
    Login {
        /// 로그인할 판. 기본값은 국제판이다.
        #[arg(long, value_enum, default_value_t = VariantArg::Ai)]
        variant: VariantArg,
        /// 브라우저를 열지 않는다.
        #[arg(long)]
        no_open: bool,
        /// 로그인 대기 시간(초).
        #[arg(long, default_value_t = 600)]
        timeout: u64,
    },
    /// 저장된 계정을 나열한다.
    Accounts {
        /// 이 판의 계정만 보여준다.
        #[arg(long, value_enum)]
        variant: Option<VariantArg>,
    },
    /// CodeBuddy CLI 인증 상태를 보여준다.
    Status,
    /// apiKeyHelper를 설치하거나 갱신한다.
    Setup,
    /// CodeBuddy CLI의 활성 계정을 바꾼다.
    Switch {
        /// 계정 id, 이메일, 또는 `accounts` 목록의 번호.
        account: String,
    },
    /// 계정을 JSON 파일로 내보낸다.
    Export {
        #[arg(long)]
        out: PathBuf,
        /// 모든 계정을 내보낸다.
        #[arg(long)]
        all: bool,
        /// 내보낼 계정 id. 여러 번 지정할 수 있다.
        #[arg(long = "id")]
        ids: Vec<String>,
    },
    /// JSON 파일에서 계정을 가져온다.
    Import {
        file: PathBuf,
        /// 파일의 모든 계정을 가져온다.
        #[arg(long)]
        all: bool,
        /// 1부터 시작하는 파일 내 순번. 여러 번 지정할 수 있다.
        #[arg(long = "index")]
        indexes: Vec<usize>,
        /// 미리보기만 하고 저장하지 않는다.
        #[arg(long)]
        dry_run: bool,
    },
    /// CodeBuddy CLI 토큰 사용량을 보여준다.
    Stats {
        /// 최근 7, 30, 90일. 생략하면 전체 기간.
        #[arg(long)]
        days: Option<i64>,
        /// 최근 요청 내역도 보여준다.
        #[arg(long)]
        requests: bool,
    },
    /// macOS 로그인 시 자동 실행을 설정한다.
    Autostart {
        #[command(subcommand)]
        action: AutostartAction,
    },
    /// 토큰 갱신 루프를 실행한다. launchd가 호출한다.
    Daemon {
        /// 갱신 주기(시간).
        #[arg(long, default_value_t = 24)]
        interval_hours: u64,
    },
    /// 계정을 삭제한다.
    Remove {
        /// 계정 id, 이메일, 닉네임, 표시 이름, 또는 `accounts` 목록의 번호.
        account: String,
        /// 확인 없이 삭제한다.
        #[arg(long)]
        yes: bool,
    },
    /// 이 Mac의 WorkBuddy 로그인 정보를 계정으로 가져온다.
    ImportLocal {
        /// 가져올 판. 기본값은 국제판이다.
        #[arg(long, value_enum, default_value_t = VariantArg::Ai)]
        variant: VariantArg,
    },
    /// 계정의 토큰을 지금 갱신한다.
    Refresh {
        /// 계정 id, 이메일, 닉네임, 표시 이름, 또는 `accounts` 목록의 번호.
        account: Option<String>,
        /// 모든 계정을 차례로 갱신한다.
        #[arg(long, conflicts_with = "account")]
        all: bool,
    },
    /// 계정에 메모를 붙이거나 지운다.
    Note {
        /// 계정 id, 이메일, 닉네임, 표시 이름, 또는 `accounts` 목록의 번호.
        account: String,
        /// 메모 내용. 최대 24자.
        text: Option<String>,
        /// 메모를 지운다.
        #[arg(long, conflicts_with = "text")]
        clear: bool,
    },
    /// 계정 목록에 표시할 필드를 고른다.
    DisplayField {
        /// 계정 id, 이메일, 닉네임, 표시 이름, 또는 `accounts` 목록의 번호.
        account: String,
        /// 표시할 필드.
        #[arg(value_enum)]
        field: DisplayFieldArg,
    },
    /// 토큰 갱신 주기(keepalive_days)를 보여주거나 설정한다.
    Keepalive {
        /// 계정을 유지할 일수. 0이면 매 주기마다 모든 계정을 갱신한다.
        #[arg(long)]
        days: Option<u32>,
    },
}

#[derive(Subcommand)]
pub enum AutostartAction {
    Enable,
    Disable,
    Status,
}

#[derive(Clone, Copy, ValueEnum)]
pub enum DisplayFieldArg {
    Nickname,
    Phone,
    Note,
}

impl DisplayFieldArg {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Nickname => "nickname",
            Self::Phone => "phone",
            Self::Note => "note",
        }
    }
}

#[derive(Clone, Copy, ValueEnum)]
pub enum VariantArg {
    Ai,
    Cn,
}

impl From<VariantArg> for WbVariant {
    fn from(value: VariantArg) -> Self {
        match value {
            VariantArg::Ai => Self::Ai,
            VariantArg::Cn => Self::Cn,
        }
    }
}

impl Cli {
    pub async fn run(self) -> Result<()> {
        let Cli { json, command } = self;
        match command {
            Command::Login {
                variant,
                no_open,
                timeout,
            } => commands::login::run(variant.into(), no_open, timeout).await,
            Command::Accounts { variant } => {
                commands::accounts::run(variant.map(Into::into), json)
            }
            Command::Status => commands::status::run(json),
            Command::Setup => commands::setup::run(json),
            Command::Switch { account } => commands::switch::run(&account, json),
            Command::Export { out, all, ids } => commands::export::run(&out, all, &ids, json),
            Command::Import {
                file,
                all,
                indexes,
                dry_run,
            } => commands::import::run(&file, all, &indexes, dry_run, json),
            Command::Stats { days, requests } => commands::stats::run(days, requests, json),
            Command::Autostart { action } => commands::autostart::run(action, json),
            Command::Daemon { interval_hours } => daemon::run(interval_hours).await,
            Command::Remove { account, yes } => commands::remove::run(&account, yes, json),
            Command::ImportLocal { variant } => commands::import_local::run(variant.into(), json),
            Command::Refresh { account, all } => {
                commands::refresh::run(account.as_deref(), all, json).await
            }
            Command::Note {
                account,
                text,
                clear,
            } => commands::note::run(&account, text.as_deref(), clear, json),
            Command::DisplayField { account, field } => {
                commands::display_field::run(&account, field, json)
            }
            Command::Keepalive { days } => commands::keepalive::run(days, json),
        }
    }
}
