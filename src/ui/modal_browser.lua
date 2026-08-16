local ModalBrowser = {}

local SPOTIFY_GREEN = HEX("1DB954")
local SPOTIFY_DARK = HEX("181818")
local SPOTIFY_LIGHT = HEX("282828")

local function sanitize_utf8(str, max_chars)
    if not str or str == "" then return "" end
    max_chars = max_chars or 40
    local chars = {}
    local i = 1
    local len = #str
    while i <= len do
        local b = string.byte(str, i)
        if not b then break end
        local char_bytes = 1
        if b >= 0 and b <= 127 then
            char_bytes = 1
        elseif b >= 192 and b <= 223 then
            char_bytes = 2
        elseif b >= 224 and b <= 239 then
            char_bytes = 3
        elseif b >= 240 and b <= 247 then
            char_bytes = 4
        else
            char_bytes = 0
        end

        if char_bytes > 0 and (i + char_bytes - 1 <= len) then
            local valid = true
            for j = 1, char_bytes - 1 do
                local cb = string.byte(str, i + j)
                if not cb or cb < 128 or cb > 191 then
                    valid = false
                    break
                end
            end
            if valid then
                table.insert(chars, str:sub(i, i + char_bytes - 1))
                i = i + char_bytes
            else
                i = i + 1
            end
        else
            i = i + 1
        end
    end

    if #chars <= max_chars then
        return table.concat(chars)
    else
        local truncated = {}
        local cut_len = math.max(1, max_chars - 1)
        for k = 1, cut_len do
            table.insert(truncated, chars[k])
        end
        table.insert(truncated, "..")
        return table.concat(truncated)
    end
end

function ModalBrowser.init()
    G.FUNCS.spotify_modal_open = function(e)
        ModalBrowser.open()
    end

    G.FUNCS.spotify_change_hud_scale = function(args)
        if G.SPOTIFY and G.SPOTIFY.config then
            G.SPOTIFY.config.current.hud_scale = args.to_val or G.SPOTIFY.config.current.hud_scale or 1.0
            G.SPOTIFY.config.save()
        end
        if G.SPOTIFY and G.SPOTIFY.hud then
            G.SPOTIFY.hud.create_or_update(true)
        end
    end

    G.FUNCS.spotify_cycle_source = function(e)
        local detected = (G.SPOTIFY and G.SPOTIFY.state and G.SPOTIFY.state.available_sources) or { "auto" }
        local chosen = detected[e.to_key] or "auto"
        if G.SPOTIFY and G.SPOTIFY.config then
            G.SPOTIFY.config.current.target_source = chosen
            G.SPOTIFY.config.save()
        end
        if G.SPOTIFY and G.SPOTIFY.ipc then
            G.SPOTIFY.ipc.set_target_source(chosen)
        end
        play_sound('button', 1.0, 0.6)
    end

    G.FUNCS.spotify_restart_daemon = function(e)
        if G.SPOTIFY and G.SPOTIFY.daemon then
            G.SPOTIFY.daemon.stop()
            G.E_MANAGER:add_event(Event({
                trigger = 'after',
                delay = 0.5,
                func = function()
                    G.SPOTIFY.daemon.start()
                    ModalBrowser.open()
                    return true
                end
            }))
        end
    end

    G.FUNCS.spotify_play_uri = function(e)
        local uri = e.config.uri
        if uri and G.SPOTIFY and G.SPOTIFY.ipc then
            G.SPOTIFY.ipc.play(uri)
            play_sound('button', 1.0, 0.8)
        end
    end
end

local function create_tab_player()
    local state = G.SPOTIFY and G.SPOTIFY.state or {}
    local track = state.current_track or {}
    local is_playing = state.is_playing or false
    local is_connected = state.connected or false
    local username = sanitize_utf8(state.username or "Desconocido")

    local conn_text = is_connected and ("Conectado como: " .. username) or "Buscando en red local (mDNS)..."
    local conn_col = is_connected and SPOTIFY_GREEN or G.C.ORANGE

    local track_title = sanitize_utf8(track.title or "No hay cancion en reproduccion")
    local track_artist = sanitize_utf8(track.artist or "Balatro Spotify Sidecar")
    local track_album = sanitize_utf8(track.album or "")

    return {
        n = G.UIT.ROOT,
        config = { align = "cm", padding = 0.15, colour = G.C.CLEAR },
        nodes = {
            {
                n = G.UIT.R,
                config = { align = "cm", colour = SPOTIFY_DARK, r = 0.1, padding = 0.1, minw = 7.0, outline = 1, outline_colour = conn_col },
                nodes = {
                    {
                        n = G.UIT.C,
                        config = { align = "cm" },
                        nodes = {
                            {
                                n = G.UIT.R,
                                config = { align = "cm" },
                                nodes = {
                                    { n = G.UIT.T, config = { text = "SPOTIFY CONNECT: ", scale = 0.38, colour = G.C.WHITE, shadow = true } },
                                    { n = G.UIT.T, config = { text = "Balatro Deck Player", scale = 0.38, colour = SPOTIFY_GREEN, shadow = true } }
                                }
                            },
                            {
                                n = G.UIT.R,
                                config = { align = "cm", padding = 0.05 },
                                nodes = {
                                    { n = G.UIT.T, config = { text = conn_text, scale = 0.3, colour = conn_col, shadow = true } }
                                }
                            }
                        }
                    }
                }
            },
            {
                n = G.UIT.R,
                config = { align = "cm", colour = SPOTIFY_LIGHT, r = 0.1, padding = 0.15, minw = 7.0, minh = 1.8 },
                nodes = {
                    {
                        n = G.UIT.C,
                        config = { align = "cm" },
                        nodes = {
                            {
                                n = G.UIT.R,
                                config = { align = "cm" },
                                nodes = {
                                    { n = G.UIT.T, config = { text = track_title, scale = 0.45, colour = G.C.WHITE, shadow = true } }
                                }
                            },
                            {
                                n = G.UIT.R,
                                config = { align = "cm", padding = 0.05 },
                                nodes = {
                                    { n = G.UIT.T, config = { text = track_artist, scale = 0.35, colour = SPOTIFY_GREEN, shadow = true } }
                                }
                            },
                            track_album ~= "" and {
                                n = G.UIT.R,
                                config = { align = "cm" },
                                nodes = {
                                    { n = G.UIT.T, config = { text = "Album: " .. track_album, scale = 0.26, colour = G.C.UI.TEXT_INACTIVE } }
                                }
                            } or nil
                        }
                    }
                }
            },
            {
                n = G.UIT.R,
                config = { align = "cm", padding = 0.1 },
                nodes = {
                    {
                        n = G.UIT.C,
                        config = { align = "cm", padding = 0.05 },
                        nodes = {
                            UIBox_button({ label = { "< Anterior" }, button = "spotify_hud_prev", colour = G.C.BLACK, minw = 1.8, minh = 0.6, scale = 0.35 })
                        }
                    },
                    {
                        n = G.UIT.C,
                        config = { align = "cm", padding = 0.05 },
                        nodes = {
                            UIBox_button({ label = { is_playing and "II Pausa" or "> Reproducir" }, button = "spotify_hud_toggle", colour = is_playing and SPOTIFY_GREEN or G.C.ORANGE, minw = 2.2, minh = 0.6, scale = 0.4 })
                        }
                    },
                    {
                        n = G.UIT.C,
                        config = { align = "cm", padding = 0.05 },
                        nodes = {
                            UIBox_button({ label = { "Siguiente >" }, button = "spotify_hud_next", colour = G.C.BLACK, minw = 1.8, minh = 0.6, scale = 0.35 })
                        }
                    }
                }
            }
        }
    }
end

local function create_tab_settings()
    local config = G.SPOTIFY and G.SPOTIFY.config and G.SPOTIFY.config.current or {}

    local detected = (G.SPOTIFY and G.SPOTIFY.state and G.SPOTIFY.state.available_sources) or { "auto" }
    local source_options = {}
    local current_opt_index = 1
    local current_saved_source = config.target_source or "auto"

    for idx, src in ipairs(detected) do
        local label = (src == "auto" and "Auto (Activo)") or src
        table.insert(source_options, label)
        if src == current_saved_source or (current_saved_source == "auto" and src == "auto") then
            current_opt_index = idx
        end
    end

    return {
        n = G.UIT.ROOT,
        config = { align = "cm", padding = 0.15, colour = G.C.CLEAR },
        nodes = {
            {
                n = G.UIT.R,
                config = { align = "cm", colour = SPOTIFY_DARK, r = 0.1, padding = 0.15, minw = 7.0 },
                nodes = {
                    {
                        n = G.UIT.R,
                        config = { align = "cm", padding = 0.05 },
                        nodes = {
                            create_toggle({
                                label = "Activar reproductor Spotify Connect",
                                ref_table = config,
                                ref_value = "enabled",
                                callback = function() if G.SPOTIFY.config then G.SPOTIFY.config.save() end end
                            })
                        }
                    },
                    {
                        n = G.UIT.R,
                        config = { align = "cm", padding = 0.05 },
                        nodes = {
                            create_toggle({
                                label = "Silenciar musica nativa de Balatro al sonar Spotify",
                                ref_table = config,
                                ref_value = "mute_vanilla_music",
                                callback = function() if G.SPOTIFY.config then G.SPOTIFY.config.save() end end
                            })
                        }
                    },
                    {
                        n = G.UIT.R,
                        config = { align = "cm", padding = 0.05 },
                        nodes = {
                            create_toggle({
                                label = "Efectos reactivos de audio (Booster Packs / Pausa)",
                                ref_table = config,
                                ref_value = "reactive_effects",
                                callback = function() if G.SPOTIFY.config then G.SPOTIFY.config.save() end end
                            })
                        }
                    },
                    {
                        n = G.UIT.R,
                        config = { align = "cm", padding = 0.05 },
                        nodes = {
                            create_option_cycle({
                                label = "Fuente / Reproductor Multimedia",
                                scale = 0.8,
                                label_scale = 0.8 * 0.45,
                                w = 4.5,
                                options = source_options,
                                current_option = current_opt_index,
                                opt_callback = "spotify_cycle_source"
                            })
                        }
                    },
                    {
                        n = G.UIT.R,
                        config = { align = "cm", padding = 0.05 },
                        nodes = {
                            create_toggle({
                                label = "Mostrar Mini-Player flotante en HUD",
                                ref_table = config,
                                ref_value = "hud_enabled",
                                callback = function()
                                    if G.SPOTIFY.config then G.SPOTIFY.config.save() end
                                    if G.SPOTIFY.hud then G.SPOTIFY.hud.create_or_update(true) end
                                end
                            })
                        }
                    },
                    {
                        n = G.UIT.R,
                        config = { align = "cm", padding = 0.08 },
                        nodes = {
                            create_slider({
                                label = "Tamaño del HUD (Escala)",
                                scale = 0.8,
                                label_scale = 0.8 * 0.45,
                                ref_table = config,
                                ref_value = "hud_scale",
                                w = 4.5,
                                min = 0.5,
                                max = 1.8,
                                step = 0.05,
                                decimal_places = 2,
                                callback = "spotify_change_hud_scale"
                            })
                        }
                    },
                    {
                        n = G.UIT.R,
                        config = { align = "cm", padding = 0.05 },
                        nodes = {
                            create_toggle({
                                label = "Iniciar daemon automaticamente con Balatro",
                                ref_table = config,
                                ref_value = "auto_start_daemon",
                                callback = function() if G.SPOTIFY.config then G.SPOTIFY.config.save() end end
                            })
                        }
                    },
                    {
                        n = G.UIT.R,
                        config = { align = "cm", padding = 0.1 },
                        nodes = {
                            UIBox_button({
                                label = { "Reiniciar Servicio Spotify Connect" },
                                button = "spotify_restart_daemon",
                                colour = G.C.ORANGE,
                                minw = 3.5,
                                minh = 0.5,
                                scale = 0.35
                            })
                        }
                    }
                }
            }
        }
    }
end

function ModalBrowser.open()
    local tabs = {
        {
            label = "Reproductor",
            chosen = true,
            tab_definition_function = create_tab_player
        },
        {
            label = "Ajustes",
            chosen = false,
            tab_definition_function = create_tab_settings
        }
    }

    local t = create_UIBox_generic_options({
        back_func = "exit_overlay_menu",
        contents = {
            {
                n = G.UIT.R,
                config = { align = "cm", padding = 0.1 },
                nodes = {
                    create_tabs({
                        tabs = tabs,
                        snap_to_nav = true,
                        colour = SPOTIFY_DARK
                    })
                }
            }
        }
    })

    G.FUNCS.overlay_menu({
        definition = t,
        config = { no_esc = false }
    })
end

return ModalBrowser
