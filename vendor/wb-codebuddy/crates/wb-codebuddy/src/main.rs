mod cli;
mod commands;
mod daemon;
#[cfg(target_os = "macos")]
mod launchd;
mod render;

use clap::Parser;

pub type Result<T> = std::result::Result<T, String>;

#[tokio::main(flavor = "current_thread")]
async fn main() {
    wb_codebuddy_core::modules::i18n::set_locale(wb_codebuddy_core::modules::i18n::Locale::Ko);
    let cli = cli::Cli::parse();
    if let Err(error) = cli.run().await {
        eprintln!("오류: {error}");
        std::process::exit(1);
    }
}
