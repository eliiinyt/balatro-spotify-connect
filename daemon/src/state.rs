use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::sync::RwLock;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TrackInfo {
    pub id: String,
    pub title: String,
    pub artist: String,
    pub album: String,
    pub album_art_url: Option<String>,
    pub duration_ms: u64,
    pub uri: String,
}

impl Default for TrackInfo {
    fn default() -> Self {
        Self {
            id: String::new(),
            title: "No track playing".to_string(),
            artist: "Balatro Deck Player".to_string(),
            album: String::new(),
            album_art_url: None,
            duration_ms: 0,
            uri: String::new(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlaybackState {
    pub connected: bool,
    pub username: Option<String>,
    pub device_name: String,
    pub is_playing: bool,
    pub current_track: TrackInfo,
    pub position_ms: u64,
    pub volume: u8,
    pub current_effect: String,
    pub target_source: String,
    pub available_sources: Vec<String>,
}

impl PlaybackState {
    pub fn new(device_name: String) -> Self {
        Self {
            connected: false,
            username: None,
            device_name,
            is_playing: false,
            current_track: TrackInfo::default(),
            position_ms: 0,
            volume: 80,
            current_effect: "none".to_string(),
            target_source: "auto".to_string(),
            available_sources: vec!["auto".to_string()],
        }
    }
}

pub type SharedState = Arc<RwLock<PlaybackState>>;

pub fn create_shared_state(device_name: String) -> SharedState {
    Arc::new(RwLock::new(PlaybackState::new(device_name)))
}
