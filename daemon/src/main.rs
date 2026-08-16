mod server;
mod spotify;
mod state;

use clap::Parser;
use server::AppState;
use std::net::SocketAddr;
use std::path::PathBuf;
use std::sync::Arc;
use tracing::{error, info};
use tracing_subscriber::EnvFilter;

#[derive(Parser, Debug)]
#[command(author, version, about = "Balatro Spotify Media Controller Daemon", long_about = None)]
struct Args {
    /// Port for the local IPC REST API
    #[arg(short, long, default_value_t = 53188)]
    port: u16,

    /// Spotify device name
    #[arg(short, long, default_value = "Balatro Deck Player")]
    device_name: String,

    /// Directory for caching Spotify session credentials
    #[arg(short, long)]
    credentials_dir: Option<PathBuf>,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let filter = EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| EnvFilter::new("info"));

    tracing_subscriber::fmt()
        .with_env_filter(filter)
        .init();

    let args = Args::parse();

    info!("Initializing Balatro Spotify Daemon v{}", env!("CARGO_PKG_VERSION"));
    info!("Device Name: {}", args.device_name);
    info!("IPC Port: {}", args.port);

    let creds_dir = args.credentials_dir.unwrap_or_else(|| {
        std::env::current_dir()
            .unwrap_or_else(|_| PathBuf::from("."))
            .join(".spotify_cache")
    });

    if !creds_dir.exists() {
        let _ = std::fs::create_dir_all(&creds_dir);
    }
    let credentials_path = creds_dir.join("credentials.json");

    let shared_state = state::create_shared_state(args.device_name.clone());

    let (spotify_controller, _spotify_task) = spotify::start_spotify_service(
        args.device_name,
        credentials_path,
        shared_state.clone(),
    ).await?;

    let spotify_controller = Arc::new(spotify_controller);

    let app_state = AppState {
        spotify: spotify_controller.clone(),
        playback_state: shared_state,
    };

    let addr = SocketAddr::from(([127, 0, 0, 1], args.port));

    // Capturar Ctrl+C para terminación limpia
    let spotify_shutdown = spotify_controller.clone();
    tokio::spawn(async move {
        let _ = tokio::signal::ctrl_c().await;
        info!("Ctrl+C received, shutting down gracefully...");
        let _ = spotify_shutdown.shutdown().await;
        std::process::exit(0);
    });

    if let Err(e) = server::start_server(addr, app_state).await {
        error!("Server encountered an error: {}", e);
    }

    Ok(())
}
