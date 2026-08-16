use crate::spotify::SpotifyController;
use crate::state::SharedState;
use axum::{
    extract::State,
    http::StatusCode,
    response::IntoResponse,
    routing::{get, post},
    Json, Router,
};
use serde::{Deserialize, Serialize};
use std::net::SocketAddr;
use std::sync::Arc;
use tower_http::cors::{Any, CorsLayer};
use tracing::info;

#[derive(Clone)]
pub struct AppState {
    pub spotify: Arc<SpotifyController>,
    pub playback_state: SharedState,
}

#[derive(Deserialize)]
pub struct PlayPayload {
    pub uri: Option<String>,
}

#[derive(Deserialize)]
pub struct VolumePayload {
    pub volume: u8,
}

#[derive(Deserialize)]
pub struct EffectPayload {
    pub effect: String,
    pub cutoff: Option<f32>,
}

#[derive(Deserialize)]
pub struct SourcePayload {
    pub source: String,
}

#[derive(Serialize)]
pub struct ApiResponse {
    pub success: bool,
    pub message: String,
}

pub fn create_router(app_state: AppState) -> Router {
    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods(Any)
        .allow_headers(Any);

    Router::new()
        .route("/health", get(health_handler))
        .route("/status", get(status_handler))
        .route("/play", post(play_handler))
        .route("/pause", post(pause_handler))
        .route("/resume", post(resume_handler))
        .route("/toggle", post(toggle_handler))
        .route("/next", post(next_handler))
        .route("/prev", post(prev_handler))
        .route("/volume", post(volume_handler))
        .route("/effect", post(effect_handler))
        .route("/source", post(source_handler))
        .route("/shutdown", post(shutdown_handler))
        .layer(cors)
        .with_state(app_state)
}

pub async fn start_server(addr: SocketAddr, app_state: AppState) -> anyhow::Result<()> {
    let app = create_router(app_state);
    info!("Starting Balatro Spotify IPC REST server on http://{}", addr);

    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;
    Ok(())
}

async fn health_handler() -> impl IntoResponse {
    (StatusCode::OK, Json(ApiResponse { success: true, message: "Balatro Spotify Daemon is healthy".to_string() }))
}

async fn status_handler(State(state): State<AppState>) -> impl IntoResponse {
    let playback = state.playback_state.read().await;
    (StatusCode::OK, Json((*playback).clone()))
}

async fn play_handler(
    State(state): State<AppState>,
    Json(payload): Json<PlayPayload>,
) -> impl IntoResponse {
    if let Some(uri) = payload.uri {
        match state.spotify.play(uri).await {
            Ok(_) => (StatusCode::OK, Json(ApiResponse { success: true, message: "Playback started".to_string() })),
            Err(e) => (StatusCode::INTERNAL_SERVER_ERROR, Json(ApiResponse { success: false, message: e.to_string() })),
        }
    } else {
        match state.spotify.resume().await {
            Ok(_) => (StatusCode::OK, Json(ApiResponse { success: true, message: "Resumed playback".to_string() })),
            Err(e) => (StatusCode::INTERNAL_SERVER_ERROR, Json(ApiResponse { success: false, message: e.to_string() })),
        }
    }
}

async fn pause_handler(State(state): State<AppState>) -> impl IntoResponse {
    match state.spotify.pause().await {
        Ok(_) => (StatusCode::OK, Json(ApiResponse { success: true, message: "Playback paused".to_string() })),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR, Json(ApiResponse { success: false, message: e.to_string() })),
    }
}

async fn resume_handler(State(state): State<AppState>) -> impl IntoResponse {
    match state.spotify.resume().await {
        Ok(_) => (StatusCode::OK, Json(ApiResponse { success: true, message: "Playback resumed".to_string() })),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR, Json(ApiResponse { success: false, message: e.to_string() })),
    }
}

async fn toggle_handler(State(state): State<AppState>) -> impl IntoResponse {
    match state.spotify.toggle().await {
        Ok(_) => (StatusCode::OK, Json(ApiResponse { success: true, message: "Toggled playback".to_string() })),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR, Json(ApiResponse { success: false, message: e.to_string() })),
    }
}

async fn next_handler(State(state): State<AppState>) -> impl IntoResponse {
    match state.spotify.next().await {
        Ok(_) => (StatusCode::OK, Json(ApiResponse { success: true, message: "Skipped to next track".to_string() })),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR, Json(ApiResponse { success: false, message: e.to_string() })),
    }
}

async fn prev_handler(State(state): State<AppState>) -> impl IntoResponse {
    match state.spotify.previous().await {
        Ok(_) => (StatusCode::OK, Json(ApiResponse { success: true, message: "Skipped to previous track".to_string() })),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR, Json(ApiResponse { success: false, message: e.to_string() })),
    }
}

async fn volume_handler(
    State(state): State<AppState>,
    Json(payload): Json<VolumePayload>,
) -> impl IntoResponse {
    let vol = payload.volume.min(100);
    match state.spotify.set_volume(vol).await {
        Ok(_) => (StatusCode::OK, Json(ApiResponse { success: true, message: format!("Volume set to {}", vol) })),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR, Json(ApiResponse { success: false, message: e.to_string() })),
    }
}

async fn effect_handler(
    State(state): State<AppState>,
    Json(payload): Json<EffectPayload>,
) -> impl IntoResponse {
    info!("Audio effect requested: {} (cutoff: {:?})", payload.effect, payload.cutoff);
    {
        let mut playback = state.playback_state.write().await;
        playback.current_effect = payload.effect.clone();
    }
    match state.spotify.set_effect(&payload.effect, payload.cutoff).await {
        Ok(_) => (StatusCode::OK, Json(ApiResponse { success: true, message: format!("Effect {} applied", payload.effect) })),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR, Json(ApiResponse { success: false, message: e.to_string() })),
    }
}

async fn source_handler(
    State(state): State<AppState>,
    Json(payload): Json<SourcePayload>,
) -> impl IntoResponse {
    info!("Target source requested: {}", payload.source);
    {
        let mut playback = state.playback_state.write().await;
        playback.target_source = payload.source.clone();
    }
    match state.spotify.set_target_source(&payload.source).await {
        Ok(_) => (StatusCode::OK, Json(ApiResponse { success: true, message: format!("Source set to {}", payload.source) })),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR, Json(ApiResponse { success: false, message: e.to_string() })),
    }
}

async fn shutdown_handler(State(state): State<AppState>) -> impl IntoResponse {
    let spotify = state.spotify.clone();
    tokio::spawn(async move {
        tokio::time::sleep(std::time::Duration::from_millis(100)).await;
        let _ = spotify.shutdown().await;
        std::process::exit(0);
    });

    (StatusCode::OK, Json(ApiResponse { success: true, message: "Shutting down Balatro Spotify daemon".to_string() }))
}
