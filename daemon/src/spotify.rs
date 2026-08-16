use crate::state::{SharedState, TrackInfo};
use anyhow::Result;
use std::path::{Path, PathBuf};
use std::time::Duration;
use tokio::sync::mpsc;
use tracing::info;

pub enum SpotifyCommand {
    PlayUri(String),
    Pause,
    Resume,
    Toggle,
    Next,
    Previous,
    SetVolume(u8),
    SetEffect { effect: String, cutoff: Option<f32> },
    SetTargetSource(String),
    Shutdown,
}

pub struct SpotifyController {
    command_tx: mpsc::Sender<SpotifyCommand>,
}

impl SpotifyController {
    pub fn new(command_tx: mpsc::Sender<SpotifyCommand>) -> Self {
        Self { command_tx }
    }

    pub async fn play(&self, uri: String) -> Result<()> {
        self.command_tx.send(SpotifyCommand::PlayUri(uri)).await?;
        Ok(())
    }

    pub async fn pause(&self) -> Result<()> {
        self.command_tx.send(SpotifyCommand::Pause).await?;
        Ok(())
    }

    pub async fn resume(&self) -> Result<()> {
        self.command_tx.send(SpotifyCommand::Resume).await?;
        Ok(())
    }

    pub async fn toggle(&self) -> Result<()> {
        self.command_tx.send(SpotifyCommand::Toggle).await?;
        Ok(())
    }

    pub async fn next(&self) -> Result<()> {
        self.command_tx.send(SpotifyCommand::Next).await?;
        Ok(())
    }

    pub async fn previous(&self) -> Result<()> {
        self.command_tx.send(SpotifyCommand::Previous).await?;
        Ok(())
    }

    pub async fn set_volume(&self, volume: u8) -> Result<()> {
        self.command_tx.send(SpotifyCommand::SetVolume(volume)).await?;
        Ok(())
    }

    pub async fn set_effect(&self, effect: &str, cutoff: Option<f32>) -> Result<()> {
        self.command_tx.send(SpotifyCommand::SetEffect {
            effect: effect.to_string(),
            cutoff,
        }).await?;
        Ok(())
    }

    pub async fn set_target_source(&self, source: &str) -> Result<()> {
        self.command_tx.send(SpotifyCommand::SetTargetSource(source.to_string())).await?;
        Ok(())
    }

    pub async fn shutdown(&self) -> Result<()> {
        self.command_tx.send(SpotifyCommand::Shutdown).await?;
        Ok(())
    }
}

#[cfg(windows)]
mod platform {
    use super::*;
    use windows::Media::Control::{
        GlobalSystemMediaTransportControlsSession,
        GlobalSystemMediaTransportControlsSessionManager,
        GlobalSystemMediaTransportControlsSessionPlaybackStatus,
    };
    use windows::Storage::Streams::DataReader;

    pub struct MediaBackend;

    fn format_friendly_name(raw: &str) -> String {
        let lower = raw.to_lowercase();
        if lower.contains("spotify") {
            "Spotify".to_string()
        } else if lower.contains("youtubemusic") || lower.contains("youtube music") {
            "YouTube Music".to_string()
        } else if lower.contains("chrome") {
            "Google Chrome".to_string()
        } else if lower.contains("msedge") || lower.contains("edge") {
            "Microsoft Edge".to_string()
        } else if lower.contains("brave") {
            "Brave".to_string()
        } else if lower.contains("firefox") {
            "Firefox".to_string()
        } else if lower.contains("vlc") {
            "VLC".to_string()
        } else if lower.contains("apple") || lower.contains("music") {
            "Apple Music".to_string()
        } else {
            let clean = raw.trim_end_matches(".exe");
            if clean.is_empty() { "Media Player".to_string() } else { clean.to_string() }
        }
    }

    impl MediaBackend {
        pub fn get_session_manager() -> Option<GlobalSystemMediaTransportControlsSessionManager> {
            let op = GlobalSystemMediaTransportControlsSessionManager::RequestAsync().ok()?;
            op.get().ok()
        }

        pub fn get_session(target_source: &str) -> Option<GlobalSystemMediaTransportControlsSession> {
            let manager = Self::get_session_manager()?;

            if target_source.eq_ignore_ascii_case("auto") || target_source.is_empty() {
                if let Ok(current) = manager.GetCurrentSession() {
                    return Some(current);
                }
            }

            if let Ok(sessions) = manager.GetSessions() {
                let size = sessions.Size().unwrap_or(0);
                for i in 0..size {
                    if let Ok(s) = sessions.GetAt(i) {
                        if let Ok(app_id) = s.SourceAppUserModelId() {
                            let app_str = app_id.to_string();
                            let friendly = format_friendly_name(&app_str);
                            if friendly.eq_ignore_ascii_case(target_source) || app_str.to_lowercase().contains(&target_source.to_lowercase()) {
                                return Some(s);
                            }
                        }
                    }
                }

                if let Ok(current) = manager.GetCurrentSession() {
                    return Some(current);
                }
            }

            None
        }

        pub async fn sync_state(state: &SharedState, cache_dir: &Path) -> bool {
            let target_source = {
                let s = state.read().await;
                s.target_source.clone()
            };

            let mut detected_sources = vec!["auto".to_string()];
            if let Some(manager) = Self::get_session_manager() {
                if let Ok(sessions) = manager.GetSessions() {
                    let size = sessions.Size().unwrap_or(0);
                    for i in 0..size {
                        if let Ok(s) = sessions.GetAt(i) {
                            if let Ok(app_id) = s.SourceAppUserModelId() {
                                let name = format_friendly_name(&app_id.to_string());
                                if !detected_sources.contains(&name) {
                                    detected_sources.push(name);
                                }
                            }
                        }
                    }
                }
            }

            let session = match Self::get_session(&target_source) {
                Some(s) => s,
                None => {
                    let mut s = state.write().await;
                    s.available_sources = detected_sources;
                    return false;
                }
            };

            let is_playing = session.GetPlaybackInfo()
                .ok()
                .and_then(|info| info.PlaybackStatus().ok())
                .map(|status| status == GlobalSystemMediaTransportControlsSessionPlaybackStatus::Playing)
                .unwrap_or(false);

            let (title, artist, album) = if let Ok(props_async) = session.TryGetMediaPropertiesAsync() {
                if let Ok(props) = props_async.get() {
                    if let Ok(thumb_ref) = props.Thumbnail() {
                        if let Ok(stream_op) = thumb_ref.OpenReadAsync() {
                            if let Ok(stream) = stream_op.get() {
                                if let Ok(size) = stream.Size() {
                                    if size > 0 && size < 5_000_000 {
                                        if let Ok(reader) = DataReader::CreateDataReader(&stream) {
                                            if reader.LoadAsync(size as u32).and_then(|op| op.get()).is_ok() {
                                                let mut buffer = vec![0u8; size as usize];
                                                if reader.ReadBytes(&mut buffer).is_ok() {
                                                    let cover_path = cache_dir.join("cover.png");
                                                    let _ = std::fs::write(&cover_path, &buffer);
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    (
                        props.Title().map(|s| s.to_string()).unwrap_or_default(),
                        props.Artist().map(|s| s.to_string()).unwrap_or_default(),
                        props.AlbumTitle().map(|s| s.to_string()).unwrap_or_default(),
                    )
                } else {
                    (String::new(), String::new(), String::new())
                }
            } else {
                (String::new(), String::new(), String::new())
            };

            let (pos_ms, dur_ms) = if let Ok(timeline) = session.GetTimelineProperties() {
                let base_pos = timeline.Position().map(|d| (d.Duration / 10_000) as u64).unwrap_or(0);
                let dur = timeline.EndTime().map(|d| (d.Duration / 10_000) as u64).unwrap_or(0);
                let real_pos = if is_playing {
                    if let Ok(last_updated) = timeline.LastUpdatedTime() {
                        let unix_now_100ns = std::time::SystemTime::now()
                            .duration_since(std::time::UNIX_EPOCH)
                            .map(|d| (d.as_nanos() / 100) as i64)
                            .unwrap_or(0);
                        let win_now_100ns = unix_now_100ns + 116_444_736_000_000_000;
                        let elapsed_100ns = (win_now_100ns - last_updated.UniversalTime).max(0);
                        let elapsed_ms = (elapsed_100ns / 10_000) as u64;
                        if dur > 0 { (base_pos + elapsed_ms).min(dur) } else { base_pos + elapsed_ms }
                    } else {
                        base_pos
                    }
                } else {
                    base_pos
                };
                (real_pos, dur)
            } else {
                (0, 0)
            };

            let app_name = session.SourceAppUserModelId()
                .map(|id| format_friendly_name(&id.to_string()))
                .unwrap_or_else(|_| "Media Player".to_string());

            if !title.is_empty() {
                let mut s = state.write().await;
                s.connected = true;
                s.is_playing = is_playing;
                s.position_ms = pos_ms;
                s.available_sources = detected_sources;
                let final_artist = if artist.is_empty() { app_name } else { artist };
                s.current_track = TrackInfo {
                    id: format!("{}_{}", title, final_artist),
                    title,
                    artist: final_artist,
                    album,
                    album_art_url: Some("cover.png".to_string()),
                    duration_ms: dur_ms,
                    uri: String::new(),
                };
                return true;
            }

            let mut s = state.write().await;
            s.available_sources = detected_sources;
            false
        }

        pub fn toggle(target_source: &str) -> bool {
            if let Some(session) = Self::get_session(target_source) {
                session.TryTogglePlayPauseAsync().is_ok()
            } else {
                false
            }
        }

        pub fn play(target_source: &str) -> bool {
            if let Some(session) = Self::get_session(target_source) {
                session.TryPlayAsync().is_ok()
            } else {
                false
            }
        }

        pub fn pause(target_source: &str) -> bool {
            if let Some(session) = Self::get_session(target_source) {
                session.TryPauseAsync().is_ok()
            } else {
                false
            }
        }

        pub fn next(target_source: &str) -> bool {
            if let Some(session) = Self::get_session(target_source) {
                session.TrySkipNextAsync().is_ok()
            } else {
                false
            }
        }

        pub fn previous(target_source: &str) -> bool {
            if let Some(session) = Self::get_session(target_source) {
                session.TrySkipPreviousAsync().is_ok()
            } else {
                false
            }
        }

        pub fn play_uri(uri: &str) {
            let _ = std::process::Command::new("cmd")
                .args(["/C", "start", "", uri])
                .spawn();
        }

        pub fn set_volume(volume: u8, target_source: &str) {
            let vol_float = (volume as f32) / 100.0;
            unsafe {
                use windows::core::Interface;
                use windows::Win32::Media::Audio::{
                    eMultimedia, eRender, IAudioSessionControl2, IAudioSessionManager2,
                    IMMDeviceEnumerator, ISimpleAudioVolume, MMDeviceEnumerator,
                };
                use windows::Win32::System::Com::{
                    CoCreateInstance, CoInitializeEx, CLSCTX_ALL, COINIT_MULTITHREADED,
                };
                use windows::Win32::System::Threading::{
                    OpenProcess, QueryFullProcessImageNameA, PROCESS_NAME_FORMAT, PROCESS_QUERY_LIMITED_INFORMATION,
                };

                let _ = CoInitializeEx(None, COINIT_MULTITHREADED);
                if let Ok(enumerator) = CoCreateInstance::<_, IMMDeviceEnumerator>(&MMDeviceEnumerator, None, CLSCTX_ALL) {
                    if let Ok(device) = enumerator.GetDefaultAudioEndpoint(eRender, eMultimedia) {
                        if let Ok(session_manager) = device.Activate::<IAudioSessionManager2>(CLSCTX_ALL, None) {
                            if let Ok(session_enum) = session_manager.GetSessionEnumerator() {
                                if let Ok(count) = session_enum.GetCount() {
                                    let match_keys: Vec<String> = if target_source.eq_ignore_ascii_case("auto") || target_source.is_empty() {
                                        let mut keys = vec!["spotify".to_string(), "youtubemusic".to_string(), "youtube music".to_string()];
                                        if let Some(session) = Self::get_session("auto") {
                                            if let Ok(app_id) = session.SourceAppUserModelId() {
                                                let s = app_id.to_string().to_lowercase();
                                                keys.push(s.clone());
                                                keys.push(format_friendly_name(&s).to_lowercase());
                                            }
                                        }
                                        keys
                                    } else {
                                        let lower = target_source.to_lowercase();
                                        let mut keys = vec![lower.clone()];
                                        if lower.contains("youtube") || lower.contains("music") {
                                            keys.push("youtubemusic".to_string());
                                            keys.push("youtube music".to_string());
                                            keys.push("youtube".to_string());
                                            keys.push("msedge".to_string());
                                            keys.push("chrome".to_string());
                                            keys.push("brave".to_string());
                                        } else if lower.contains("spotify") {
                                            keys.push("spotify".to_string());
                                        } else if lower.contains("chrome") {
                                            keys.push("chrome".to_string());
                                        } else if lower.contains("edge") {
                                            keys.push("msedge".to_string());
                                            keys.push("edge".to_string());
                                        }
                                        keys
                                    };

                                    for i in 0..count {
                                        if let Ok(control) = session_enum.GetSession(i) {
                                            if let Ok(control2) = control.cast::<IAudioSessionControl2>() {
                                                if let Ok(pid) = control2.GetProcessId() {
                                                    if pid > 0 {
                                                        let matches = if let Ok(handle) = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid) {
                                                            let mut buffer = [0u8; 1024];
                                                            let mut size = buffer.len() as u32;
                                                            let p_buf = windows::core::PSTR(buffer.as_mut_ptr());
                                                            if QueryFullProcessImageNameA(handle, PROCESS_NAME_FORMAT(0), p_buf, &mut size).is_ok() {
                                                                let path_str = String::from_utf8_lossy(&buffer[..size as usize]).to_lowercase();
                                                                match_keys.iter().any(|k| path_str.contains(k))
                                                            } else {
                                                                false
                                                            }
                                                        } else {
                                                            false
                                                        };

                                                        if matches {
                                                            if let Ok(vol_ctrl) = control.cast::<ISimpleAudioVolume>() {
                                                                let _ = vol_ctrl.SetMasterVolume(vol_float, std::ptr::null());
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

#[cfg(target_os = "linux")]
mod platform {
    use super::*;
    use mpris::PlayerFinder;

    pub struct MediaBackend;

    impl MediaBackend {
        pub fn get_player(target_source: &str) -> Option<mpris::Player> {
            let finder = PlayerFinder::new().ok()?;
            if !target_source.eq_ignore_ascii_case("auto") && !target_source.is_empty() {
                if let Ok(player) = finder.find_by_name(&target_source.to_lowercase()) {
                    return Some(player);
                }
            }
            if let Ok(player) = finder.find_by_name("spotify") {
                return Some(player);
            }
            finder.find_active().ok()
        }

        pub async fn sync_state(state: &SharedState, _cache_dir: &Path) -> bool {
            let target_source = {
                let s = state.read().await;
                s.target_source.clone()
            };

            let (detected_sources, track_data) = {
                let mut detected = vec!["auto".to_string()];
                if let Ok(finder) = PlayerFinder::new() {
                    if let Ok(players) = finder.find_all() {
                        for p in players {
                            let id = p.identity().to_string();
                            if !detected.contains(&id) {
                                detected.push(id);
                            }
                        }
                    }
                }

                let track = if let Some(player) = Self::get_player(&target_source) {
                    let is_playing = player.get_playback_status()
                        .map(|s| s == mpris::PlaybackStatus::Playing)
                        .unwrap_or(false);

                    if let Ok(metadata) = player.get_metadata() {
                        let title = metadata.title().unwrap_or_default().to_string();
                        let artists = metadata.artists().map(|a| a.join(", ")).unwrap_or_default();
                        let album = metadata.album_name().unwrap_or_default().to_string();
                        let dur_ms = metadata.length().map(|d| d.as_millis() as u64).unwrap_or(0);
                        let pos_ms = player.get_position().map(|d| d.as_millis() as u64).unwrap_or(0);

                        Some((is_playing, pos_ms, dur_ms, title, artists, album))
                    } else {
                        None
                    }
                } else {
                    None
                };

                (detected, track)
            };

            let mut s = state.write().await;
            s.available_sources = detected_sources;

            if let Some((is_playing, pos_ms, dur_ms, title, artists, album)) = track_data {
                if !title.is_empty() {
                    s.connected = true;
                    s.is_playing = is_playing;
                    s.position_ms = pos_ms;
                    s.current_track = TrackInfo {
                        id: format!("{}_{}", title, artists),
                        title,
                        artist: artists,
                        album,
                        album_art_url: None,
                        duration_ms: dur_ms,
                        uri: String::new(),
                    };
                    return true;
                }
            }

            false
        }

        pub fn toggle(target_source: &str) -> bool {
            if let Some(player) = Self::get_player(target_source) {
                player.play_pause().is_ok()
            } else {
                false
            }
        }

        pub fn play(target_source: &str) -> bool {
            if let Some(player) = Self::get_player(target_source) {
                player.play().is_ok()
            } else {
                false
            }
        }

        pub fn pause(target_source: &str) -> bool {
            if let Some(player) = Self::get_player(target_source) {
                player.pause().is_ok()
            } else {
                false
            }
        }

        pub fn next(target_source: &str) -> bool {
            if let Some(player) = Self::get_player(target_source) {
                player.next().is_ok()
            } else {
                false
            }
        }

        pub fn previous(target_source: &str) -> bool {
            if let Some(player) = Self::get_player(target_source) {
                player.previous().is_ok()
            } else {
                false
            }
        }

        pub fn play_uri(uri: &str) {
            let _ = std::process::Command::new("xdg-open")
                .arg(uri)
                .spawn();
        }

        pub fn set_volume(volume: u8, target_source: &str) {
            let vol_float = (volume as f64) / 100.0;
            if let Some(player) = Self::get_player(target_source) {
                let _ = player.set_volume(vol_float);
            }
        }
    }
}

#[cfg(not(any(windows, target_os = "linux")))]
mod platform {
    use super::*;
    pub struct MediaBackend;
    impl MediaBackend {
        pub async fn sync_state(_state: &SharedState, _cache_dir: &Path) -> bool { false }
        pub fn toggle(_target: &str) -> bool { false }
        pub fn play(_target: &str) -> bool { false }
        pub fn pause(_target: &str) -> bool { false }
        pub fn next(_target: &str) -> bool { false }
        pub fn previous(_target: &str) -> bool { false }
        pub fn play_uri(_uri: &str) {}
        pub fn set_volume(_volume: u8, _target: &str) {}
    }
}

pub async fn start_spotify_service(
    device_name: String,
    credentials_path: PathBuf,
    state: SharedState,
) -> Result<(SpotifyController, tokio::task::JoinHandle<()>)> {
    let (cmd_tx, mut cmd_rx) = mpsc::channel::<SpotifyCommand>(32);
    let controller = SpotifyController::new(cmd_tx);

    info!("Starting Balatro Spotify Controller service: {}", device_name);

    let cache_dir = credentials_path.parent().unwrap_or_else(|| Path::new(".")).to_path_buf();
    let state_sync = state.clone();
    let handle = tokio::spawn(async move {
        let mut interval = tokio::time::interval(Duration::from_millis(250));

        loop {
            tokio::select! {
                _ = interval.tick() => {
                    platform::MediaBackend::sync_state(&state_sync, &cache_dir).await;
                }
                Some(cmd) = cmd_rx.recv() => {
                    let target_source = {
                        let s = state_sync.read().await;
                        s.target_source.clone()
                    };

                    match cmd {
                        SpotifyCommand::PlayUri(uri) => {
                            info!("IPC Command: Play URI -> {}", uri);
                            platform::MediaBackend::play_uri(&uri);
                        }
                        SpotifyCommand::Pause => {
                            info!("IPC Command: Pause [{}]", target_source);
                            platform::MediaBackend::pause(&target_source);
                            let mut s = state_sync.write().await;
                            s.is_playing = false;
                        }
                        SpotifyCommand::Resume => {
                            info!("IPC Command: Resume [{}]", target_source);
                            platform::MediaBackend::play(&target_source);
                            let mut s = state_sync.write().await;
                            s.is_playing = true;
                        }
                        SpotifyCommand::Toggle => {
                            info!("IPC Command: Toggle Play/Pause [{}]", target_source);
                            platform::MediaBackend::toggle(&target_source);
                        }
                        SpotifyCommand::Next => {
                            info!("IPC Command: Next Track [{}]", target_source);
                            platform::MediaBackend::next(&target_source);
                        }
                        SpotifyCommand::Previous => {
                            info!("IPC Command: Previous Track [{}]", target_source);
                            platform::MediaBackend::previous(&target_source);
                        }
                        SpotifyCommand::SetVolume(vol) => {
                            info!("IPC Command: Set Volume -> {} [{}]", vol, target_source);
                            platform::MediaBackend::set_volume(vol, &target_source);
                            let mut s = state_sync.write().await;
                            s.volume = vol;
                        }
                        SpotifyCommand::SetEffect { effect, cutoff } => {
                            info!("IPC Command: Set Audio Effect -> {} (cutoff: {:?})", effect, cutoff);
                            let mut s = state_sync.write().await;
                            s.current_effect = effect;
                        }
                        SpotifyCommand::SetTargetSource(source) => {
                            info!("IPC Command: Set Target Source -> {}", source);
                            let mut s = state_sync.write().await;
                            s.target_source = source;
                        }
                        SpotifyCommand::Shutdown => {
                            info!("IPC Command: Shutdown received. Exiting daemon...");
                            break;
                        }
                    }
                }
            }
        }

        info!("Balatro Spotify service terminated cleanly.");
    });

    Ok((controller, handle))
}
