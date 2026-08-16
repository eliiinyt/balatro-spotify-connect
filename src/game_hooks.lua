local GameHooks = {}

GameHooks.last_volume = nil
GameHooks.last_effect = "none"
GameHooks.duck_factor = 1.0
GameHooks.target_duck_factor = 1.0
GameHooks.last_sent_volume = nil
GameHooks.was_scoring = false

function GameHooks.init()
    GameHooks.last_volume = G.SETTINGS and G.SETTINGS.SOUND and G.SETTINGS.SOUND.music_volume or 80
    GameHooks.last_effect = "none"
    GameHooks.duck_factor = 1.0
    GameHooks.target_duck_factor = 1.0
    GameHooks.last_sent_volume = nil
    GameHooks.was_scoring = false
end

local function is_booster_open()
    if G.booster_pack and not G.booster_pack.REMOVED then
        return true
    end
    if G.STATE and G.STATES then
        if G.STATE == G.STATES.TAROT_PACK or
           G.STATE == G.STATES.PLANET_PACK or
           G.STATE == G.STATES.SPECTRAL_PACK or
           G.STATE == G.STATES.STANDARD_PACK or
           G.STATE == G.STATES.BUFFOON_PACK or
           G.STATE == G.STATES.SMODS_BOOSTER_OPENED then
            return true
        end
    end
    return false
end

local function is_game_paused()
    if G.SETTINGS and G.SETTINGS.paused then
        return true
    end
    if G.OVERLAY_MENU then
        return true
    end
    return false
end

function GameHooks.update(dt)
    if not (G.SPOTIFY and G.SPOTIFY.config and G.SPOTIFY.config.current.enabled) then
        return
    end

    if G.SPOTIFY.config.current.hud_enabled and not G.HUD_SPOTIFY and G.SPOTIFY.hud then
        G.SPOTIFY.hud.create_or_update(true)
    end

    local cfg = G.SPOTIFY.config.current
    local base_vol = G.SETTINGS and G.SETTINGS.SOUND and G.SETTINGS.SOUND.music_volume or 80

    local now = love.timer and love.timer.getTime() or (socket and socket.gettime() or 0)
    local real_dt = (GameHooks.last_update_time and now > GameHooks.last_update_time) and math.min(0.1, now - GameHooks.last_update_time) or 0.016
    GameHooks.last_update_time = now

    if cfg.reactive_effects then
        local in_booster = is_booster_open()
        local in_pause = is_game_paused()
        local should_duck = in_booster or in_pause
        local current_effect = should_duck and "underwater" or "none"

        if current_effect ~= GameHooks.last_effect then
            GameHooks.last_effect = current_effect
            if G.SPOTIFY.ipc then
                G.SPOTIFY.ipc.set_audio_effect(current_effect, {
                    cutoff = should_duck and 450 or 20000
                })
            end
        end

        GameHooks.target_duck_factor = should_duck and 0.35 or 1.0

        if G.STATE == G.STATES.HAND_PLAYED then
            if not GameHooks.was_scoring then
                GameHooks.was_scoring = true
                if G.HUD_SPOTIFY and G.HUD_SPOTIFY.juice_up then
                    G.HUD_SPOTIFY:juice_up(0.18, 0.04)
                end
            end
        else
            GameHooks.was_scoring = false
        end
    else
        GameHooks.target_duck_factor = 1.0
        if GameHooks.last_effect ~= "none" then
            GameHooks.last_effect = "none"
            if G.SPOTIFY.ipc then
                G.SPOTIFY.ipc.set_audio_effect("none")
            end
        end
    end

    local speed = 5.0 * real_dt
    if GameHooks.duck_factor < GameHooks.target_duck_factor then
        GameHooks.duck_factor = math.min(GameHooks.target_duck_factor, GameHooks.duck_factor + speed)
    elseif GameHooks.duck_factor > GameHooks.target_duck_factor then
        GameHooks.duck_factor = math.max(GameHooks.target_duck_factor, GameHooks.duck_factor - speed)
    end

    if cfg.sync_volume then
        local target_final_vol = math.floor(base_vol * GameHooks.duck_factor)
        if target_final_vol ~= GameHooks.last_sent_volume then
            GameHooks.last_sent_volume = target_final_vol
            if G.SPOTIFY.ipc then
                G.SPOTIFY.ipc.set_volume(target_final_vol)
            end
        end
    end
end

return GameHooks
