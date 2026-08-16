G.SPOTIFY = G.SPOTIFY or {
    version = "1.0.0",
    state = {
        online = false,
        connected = false,
        username = nil,
        device_name = "Balatro Deck Player",
        is_playing = false,
        volume = 80,
        position_ms = 0,
        target_source = "auto",
        available_sources = { "auto" },
        current_track = {
            id = "",
            title = "No track playing",
            artist = "Balatro Deck Player",
            album = "",
            album_art_url = nil,
            duration_ms = 0,
            uri = ""
        },
        playlists = {}
    }
}

local mod_path = SMODS and SMODS.current_mod and SMODS.current_mod.path or ""

local function safe_load_file(rel_path)
    if SMODS and SMODS.load_file then
        local fn = SMODS.load_file(rel_path)
        if type(fn) == "function" then return fn() end

        local fn2 = SMODS.load_file("/" .. rel_path)
        if type(fn2) == "function" then return fn2() end
    end

    if NFS and NFS.read then
        local clean_mod_path = mod_path:gsub("[/\\]$", "")
        local full_path = clean_mod_path .. "/" .. rel_path:gsub("^[/\\]", "")
        local content = NFS.read(full_path)
        if content then
            local fn = load(content)
            if fn then return fn() end
        end
    end

    if love.filesystem.getInfo and love.filesystem.getInfo(rel_path) then
        local content = love.filesystem.read(rel_path)
        if content then
            local fn = load(content)
            if fn then return fn() end
        end
    end

    error("[Spotify Connect] Failed to load module: " .. tostring(rel_path))
end

local Config = safe_load_file("src/config.lua")
local DaemonManager = safe_load_file("src/daemon_manager.lua")
local IPCClient = safe_load_file("src/ipc_client.lua")
local HUDPlayer = safe_load_file("src/ui/hud_player.lua")
local ModalBrowser = safe_load_file("src/ui/modal_browser.lua")
local GameHooks = safe_load_file("src/game_hooks.lua")

G.SPOTIFY.mod_path = mod_path
G.SPOTIFY.config = Config
G.SPOTIFY.daemon = DaemonManager
G.SPOTIFY.ipc = IPCClient
G.SPOTIFY.hud = HUDPlayer
G.SPOTIFY.modal = ModalBrowser
G.SPOTIFY.hooks = GameHooks

Config.init(mod_path)
DaemonManager.init(mod_path, Config)
IPCClient.init(mod_path, Config.current.daemon_port)
HUDPlayer.init()
ModalBrowser.init()
GameHooks.init()

if Config.current.target_source and Config.current.target_source ~= "" then
    IPCClient.set_target_source(Config.current.target_source)
end

if Config.current.auto_start_daemon then
    DaemonManager.start()
end

function G.SPOTIFY.should_mute_vanilla()
    if not (Config.current.enabled and Config.current.mute_vanilla_music) then
        return false
    end
    return G.SPOTIFY.state.is_playing
end

function G.SPOTIFY.update(dt)
    if not (Config and Config.current and Config.current.enabled) then return end

    local now = love.timer and love.timer.getTime() or socket.gettime()
    if G.SPOTIFY._last_update_time and (now - G.SPOTIFY._last_update_time) < 0.001 then
        return
    end
    G.SPOTIFY._last_update_time = now

    IPCClient.update()

    if G.SPOTIFY.state and G.SPOTIFY.state.is_playing then
        local anchor_pos = G.SPOTIFY.state.anchor_pos or (G.SPOTIFY.state.position_ms or 0)
        local anchor_time = G.SPOTIFY.state.anchor_time or now
        local elapsed_ms = (now - anchor_time) * 1000
        local dur = (G.SPOTIFY.state.current_track and G.SPOTIFY.state.current_track.duration_ms) or 0
        local cur_pos = anchor_pos + elapsed_ms
        if dur > 0 then
            G.SPOTIFY.state.position_ms = math.min(dur, math.max(0, cur_pos))
        else
            G.SPOTIFY.state.position_ms = math.max(0, cur_pos)
        end
    end

    GameHooks.update(dt)

    HUDPlayer.create_or_update(false)
end

local original_keypressed = love.keypressed
love.keypressed = function(key)
    if key == "f8" then
        if G.SPOTIFY and G.SPOTIFY.modal then
            G.SPOTIFY.modal.open()
        end
    end
    if original_keypressed then
        return original_keypressed(key)
    end
end

if SMODS.current_mod then
    SMODS.current_mod.config_tab = function()
        return {
            n = G.UIT.ROOT,
            config = { align = "cm", padding = 0.1, colour = G.C.CLEAR },
            nodes = {
                {
                    n = G.UIT.R,
                    config = { align = "cm", padding = 0.1 },
                    nodes = {
                        { n = G.UIT.T, config = { text = "Balatro Spotify Connect", scale = 0.5, colour = HEX("1DB954"), shadow = true } }
                    }
                },
                {
                    n = G.UIT.R,
                    config = { align = "cm", padding = 0.05 },
                    nodes = {
                        { n = G.UIT.T, config = { text = "Dispositivo Connect: " .. (Config.current.device_name or "Balatro Deck Player"), scale = 0.3, colour = G.C.UI.TEXT_LIGHT } }
                    }
                },
                {
                    n = G.UIT.R,
                    config = { align = "cm", padding = 0.05 },
                    nodes = {
                        create_toggle({
                            label = "Activar Mod",
                            ref_table = Config.current,
                            ref_value = "enabled",
                            callback = Config.save
                        })
                    }
                },
                {
                    n = G.UIT.R,
                    config = { align = "cm", padding = 0.05 },
                    nodes = {
                        create_toggle({
                            label = "Silenciar música nativa de Balatro",
                            ref_table = Config.current,
                            ref_value = "mute_vanilla_music",
                            callback = Config.save
                        })
                    }
                },
                {
                    n = G.UIT.R,
                    config = { align = "cm", padding = 0.05 },
                    nodes = {
                        create_toggle({
                            label = "Mostrar Mini-Player en HUD",
                            ref_table = Config.current,
                            ref_value = "hud_enabled",
                            callback = function()
                                Config.save()
                                HUDPlayer.create_or_update(true)
                            end
                        })
                    }
                },
                {
                    n = G.UIT.R,
                    config = { align = "cm", padding = 0.1 },
                    nodes = {
                        UIBox_button({
                            label = { "Abrir Reproductor y Ajustes (F8)" },
                            button = "spotify_hud_open_menu",
                            colour = HEX("1DB954"),
                            minw = 3.5,
                            minh = 0.5,
                            scale = 0.35
                        })
                    }
                }
            }
        }
    end
end

local original_love_quit = love.quit
love.quit = function()
    pcall(function()
        if G.SPOTIFY and G.SPOTIFY.ipc then
            G.SPOTIFY.ipc.stop()
        end
    end)
    pcall(function()
        if DaemonManager then
            DaemonManager.stop()
        end
    end)
    if original_love_quit then
        return original_love_quit()
    end
end
