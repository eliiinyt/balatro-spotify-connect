local HUDPlayer = {}

local SPOTIFY_GREEN = HEX("1DB954")
local SPOTIFY_DARK = HEX("121212")
local SPOTIFY_GRAY = HEX("535353")
local SPOTIFY_PANEL = HEX("181818")

HUDPlayer.last_title = ""
HUDPlayer.last_artist = ""
HUDPlayer.last_is_playing = false
HUDPlayer.last_connected = false
HUDPlayer.last_sec = -1

local current_cover_img = nil
local current_cover_id = nil

local CoverSprite = Moveable:extend()
function CoverSprite:init(img, w, h, scale_mult)
    Moveable.init(self, 0, 0, w or 0.75, h or 0.75)
    self.img = img
    self.T.w = w or 0.75
    self.T.h = h or 0.75
    self.scale_mult = scale_mult or 1.0
    self.zoom = true
end

function CoverSprite:draw()
    if self.img and self.states.visible then
        prep_draw(self, 1)
        love.graphics.setColor(1, 1, 1, 1)
        local iw = self.img:getWidth()
        local ih = self.img:getHeight()
        local sx = self.VT.w / iw
        local sy = self.VT.h / ih
        love.graphics.draw(self.img, 0, 0, 0, sx, sy)

        local is_playing = G.SPOTIFY and G.SPOTIFY.state and G.SPOTIFY.state.is_playing
        local border_col = is_playing and SPOTIFY_GREEN or SPOTIFY_GRAY
        love.graphics.setColor(border_col[1], border_col[2], border_col[3], border_col[4] or 1)
        love.graphics.setLineWidth(0.04 * self.scale_mult)
        love.graphics.rectangle('line', 0, 0, self.VT.w, self.VT.h, 0.08 * self.scale_mult, 0.08 * self.scale_mult)

        love.graphics.pop()
        add_to_drawhash(self)
    end
end

local function get_mod_path()
    return (G.SPOTIFY and G.SPOTIFY.mod_path and G.SPOTIFY.mod_path ~= "" and G.SPOTIFY.mod_path) or
           (SMODS and SMODS.current_mod and SMODS.current_mod.path) or
           (SMODS and SMODS.Mods and SMODS.Mods["balatro-spotify-connect"] and SMODS.Mods["balatro-spotify-connect"].path) or
           ""
end

local function has_cjk(str)
    if not str then return false end
    for i = 1, #str do
        local b = string.byte(str, i)
        if b and b >= 224 then return true end
    end
    return false
end

local function get_best_font(str)
    if has_cjk(str) then
        if G.LANGUAGES and G.LANGUAGES['ja'] and G.LANGUAGES['ja'].font and G.LANGUAGES['ja'].font.FONT then
            return G.LANGUAGES['ja'].font
        elseif G.FONTS and G.FONTS[5] and G.FONTS[5].FONT then
            return G.FONTS[5]
        elseif G.FONTS and G.FONTS[9] and G.FONTS[9].FONT then
            return G.FONTS[9]
        elseif G.FONTS and G.FONTS[8] and G.FONTS[8].FONT then
            return G.FONTS[8]
        end
    end
    return nil
end

local DraggableContainer = nil
local function get_draggable_container()
    if DraggableContainer then return DraggableContainer end

    local ok_req, res_req = pcall(require, 'spotify.draggablecontainer')
    if ok_req and res_req then
        DraggableContainer = res_req
        return DraggableContainer
    end

    if SMODS and SMODS.load_file then
        local ok, fn = pcall(SMODS.load_file, "src/ui/draggable_container.lua")
        if ok and type(fn) == "function" then
            local ok2, res = pcall(fn)
            if ok2 and res then
                DraggableContainer = res
                return DraggableContainer
            end
        end
    end

    local mod_path = get_mod_path()
    if NFS and NFS.load and mod_path ~= "" then
        local ok, fn = pcall(NFS.load, mod_path .. "/src/ui/draggable_container.lua")
        if ok and type(fn) == "function" then
            local ok2, res = pcall(fn)
            if ok2 and res then
                DraggableContainer = res
                return DraggableContainer
            end
        end
    end

    return DraggableContainer
end

local function load_cover_image(track_id)
    if not track_id or track_id == "" then return nil end
    if track_id == current_cover_id and current_cover_img then return current_cover_img end

    local mod_path = get_mod_path()
    local possible_paths = {
        mod_path ~= "" and (mod_path .. "/.spotify_cache/cover.png") or nil,
        ".spotify_cache/cover.png",
        "bin/.spotify_cache/cover.png"
    }

    local file_content = nil

    for _, p in ipairs(possible_paths) do
        if p then
            if NFS and NFS.read and NFS.getInfo and NFS.getInfo(p) then
                file_content = NFS.read(p)
                break
            elseif love.filesystem.getInfo and love.filesystem.getInfo(p) then
                file_content = love.filesystem.read(p)
                break
            else
                local f = io.open(p, "rb")
                if f then
                    file_content = f:read("*a")
                    f:close()
                    if file_content and #file_content > 100 then
                        break
                    end
                end
            end
        end
    end

    if file_content and #file_content > 500 then
        local ok, data = pcall(love.filesystem.newFileData, file_content, "cover.png")
        if ok and data then
            local ok2, img_data = pcall(love.image.newImageData, data)
            if ok2 and img_data then
                local ok3, img = pcall(love.graphics.newImage, img_data)
                if ok3 and img then
                    current_cover_img = img
                    current_cover_id = track_id
                    return current_cover_img
                end
            end
        end
    end

    return nil
end

function HUDPlayer.init()
    G.FUNCS.spotify_hud_prev = function(e)
        if G.SPOTIFY and G.SPOTIFY.ipc then
            G.SPOTIFY.ipc.previous()
            play_sound('button', 1.1, 0.6)
        end
    end

    G.FUNCS.spotify_hud_toggle = function(e)
        if G.SPOTIFY and G.SPOTIFY.ipc then
            G.SPOTIFY.ipc.toggle()
            play_sound('button', 1.0, 0.8)
        end
    end

    G.FUNCS.spotify_hud_next = function(e)
        if G.SPOTIFY and G.SPOTIFY.ipc then
            G.SPOTIFY.ipc.next()
            play_sound('button', 0.9, 0.6)
        end
    end

    G.FUNCS.spotify_hud_open_menu = function(e)
        if G.SPOTIFY and G.SPOTIFY.modal then
            G.SPOTIFY.modal.open()
            play_sound('button', 1.0, 0.7)
        end
    end
end

local function format_time(ms)
    if not ms or ms < 0 then return "0:00" end
    local total_sec = math.floor(ms / 1000)
    local min = math.floor(total_sec / 60)
    local sec = total_sec % 60
    return string.format("%d:%02d", min, sec)
end

local function utf8_safe_truncate(str, max_chars)
    if not str or str == "" then return "" end
    max_chars = max_chars or 25
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

function HUDPlayer.create_definition()
    local state = G.SPOTIFY and G.SPOTIFY.state or {}
    local track = state.current_track or {}
    local is_playing = state.is_playing or false
    local is_connected = state.connected or false
    local scale = (G.SPOTIFY and G.SPOTIFY.config and G.SPOTIFY.config.current and G.SPOTIFY.config.current.hud_scale) or 1.0

    local raw_title = track.title or "No track playing"
    local raw_artist = track.artist or "Balatro Deck Player"

    local is_cjk = has_cjk(raw_title) or has_cjk(raw_artist)
    local best_custom_font = get_best_font(raw_title) or get_best_font(raw_artist)

    local title_len = is_cjk and 16 or 24
    local artist_len = is_cjk and 18 or 28

    local title_text = utf8_safe_truncate(raw_title, title_len)
    local artist_text = utf8_safe_truncate(raw_artist, artist_len)

    local cur_ms = state.position_ms or 0
    local dur_ms = track.duration_ms or 0
    local time_text = format_time(cur_ms) .. " / " .. format_time(dur_ms)

    local status_col = is_connected and SPOTIFY_GREEN or G.C.ORANGE
    local play_label = is_playing and "II" or ">"

    local cover_img = load_cover_image(track.id)
    local cover_size = 0.72 * scale

    local cover_node = nil
    if cover_img then
        cover_node = {
            n = G.UIT.C,
            config = {
                align = "cm",
                minw = cover_size,
                minh = cover_size,
                padding = 0.02 * scale,
                r = 0.08 * scale,
                colour = G.C.CLEAR
            },
            nodes = {
                {
                    n = G.UIT.O,
                    config = {
                        object = CoverSprite(cover_img, cover_size, cover_size, scale),
                        w = cover_size,
                        h = cover_size
                    }
                }
            }
        }
    else
        cover_node = {
            n = G.UIT.C,
            config = {
                align = "cm",
                minw = cover_size,
                minh = cover_size,
                colour = SPOTIFY_DARK,
                r = 0.08 * scale,
                padding = 0.05 * scale,
                outline = 1,
                outline_colour = is_playing and SPOTIFY_GREEN or SPOTIFY_GRAY
            },
            nodes = {
                {
                    n = G.UIT.R,
                    config = { align = "cm" },
                    nodes = {
                        {
                            n = G.UIT.T,
                            config = {
                                text = "SP",
                                scale = 0.32 * scale,
                                colour = is_playing and SPOTIFY_GREEN or G.C.UI.TEXT_INACTIVE,
                                shadow = true
                            }
                        }
                    }
                }
            }
        }
    end

    local title_font_config = {
        text = title_text,
        scale = (is_cjk and 0.30 or 0.32) * scale,
        colour = G.C.WHITE,
        shadow = false
    }
    if best_custom_font then
        title_font_config.font = best_custom_font
    end

    local artist_font_config = {
        text = artist_text,
        scale = (is_cjk and 0.24 or 0.26) * scale,
        colour = is_playing and SPOTIFY_GREEN or G.C.UI.TEXT_LIGHT,
        shadow = false
    }
    if best_custom_font then
        artist_font_config.font = best_custom_font
    end

    return {
        n = G.UIT.ROOT,
        config = {
            align = "cm",
            colour = SPOTIFY_DARK,
            r = 0.12 * scale,
            padding = 0.08 * scale,
            minw = 3.6 * scale,
            minh = 1.35 * scale,
            outline = 1.5,
            outline_colour = is_playing and SPOTIFY_GREEN or status_col,
            shadow = true,
            can_drag = true
        },
        nodes = {
            {
                n = G.UIT.R,
                config = { align = "cm", colour = SPOTIFY_PANEL, r = 0.1 * scale, padding = 0.06 * scale },
                nodes = {
                    {
                        n = G.UIT.R,
                        config = { align = "cl", padding = 0.04 * scale },
                        nodes = {
                            cover_node,
                            {
                                n = G.UIT.C,
                                config = { align = "cl", padding = 0.04 * scale, minw = 2.4 * scale },
                                nodes = {
                                    {
                                        n = G.UIT.R,
                                        config = { align = "cl" },
                                        nodes = {
                                            {
                                                n = G.UIT.T,
                                                config = title_font_config
                                            }
                                        }
                                    },
                                    {
                                        n = G.UIT.R,
                                        config = { align = "cl", padding = 0.01 * scale },
                                        nodes = {
                                            {
                                                n = G.UIT.T,
                                                config = artist_font_config
                                            }
                                        }
                                    },
                                    {
                                        n = G.UIT.R,
                                        config = { align = "cl" },
                                        nodes = {
                                            {
                                                n = G.UIT.T,
                                                config = {
                                                    text = time_text,
                                                    scale = 0.21 * scale,
                                                    colour = G.C.UI.TEXT_INACTIVE,
                                                    shadow = false
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    },
                    {
                        n = G.UIT.R,
                        config = { align = "cm", padding = 0.04 * scale },
                        nodes = {
                            {
                                n = G.UIT.C,
                                config = { align = "cm", padding = 0.02 * scale },
                                nodes = {
                                    UIBox_button({
                                        label = { "<<" },
                                        button = "spotify_hud_prev",
                                        colour = G.C.BLACK,
                                        minw = 0.6 * scale,
                                        minh = 0.38 * scale,
                                        scale = 0.32 * scale
                                    })
                                }
                            },
                            {
                                n = G.UIT.C,
                                config = { align = "cm", padding = 0.02 * scale },
                                nodes = {
                                    UIBox_button({
                                        label = { play_label },
                                        button = "spotify_hud_toggle",
                                        colour = is_playing and SPOTIFY_GREEN or G.C.ORANGE,
                                        minw = 0.75 * scale,
                                        minh = 0.4 * scale,
                                        scale = 0.35 * scale
                                    })
                                }
                            },
                            {
                                n = G.UIT.C,
                                config = { align = "cm", padding = 0.02 * scale },
                                nodes = {
                                    UIBox_button({
                                        label = { ">>" },
                                        button = "spotify_hud_next",
                                        colour = G.C.BLACK,
                                        minw = 0.6 * scale,
                                        minh = 0.38 * scale,
                                        scale = 0.32 * scale
                                    })
                                }
                            },
                            {
                                n = G.UIT.C,
                                config = { align = "cm", padding = 0.02 * scale },
                                nodes = {
                                    UIBox_button({
                                        label = { "OPT" },
                                        button = "spotify_hud_open_menu",
                                        colour = G.C.PURPLE,
                                        minw = 0.6 * scale,
                                        minh = 0.38 * scale,
                                        scale = 0.28 * scale
                                    })
                                }
                            }
                        }
                    }
                }
            }
        }
    }
end

function HUDPlayer.create_or_update(force)
    if not (G.ROOM and G.ROOM.T and G.STAGE and G.I and G.I.UIBOX and (G.STAGE == G.STAGES.RUN or G.STAGE == G.STAGES.MAIN_MENU)) then
        return
    end

    if not (G.SPOTIFY and G.SPOTIFY.config and G.SPOTIFY.config.current.hud_enabled) then
        if G.HUD_SPOTIFY then
            G.HUD_SPOTIFY:remove()
            G.HUD_SPOTIFY = nil
        end
        return
    end

    local state = G.SPOTIFY.state or {}
    local track = state.current_track or {}
    local title = track.title or ""
    local artist = track.artist or ""
    local is_playing = state.is_playing or false
    local is_connected = state.connected or false
    local cur_sec = math.floor((state.position_ms or 0) / 1000)

    local state_changed = (title ~= HUDPlayer.last_title) or
                          (artist ~= HUDPlayer.last_artist) or
                          (is_playing ~= HUDPlayer.last_is_playing) or
                          (is_connected ~= HUDPlayer.last_connected) or
                          (cur_sec ~= HUDPlayer.last_sec)

    if G.HUD_SPOTIFY then
        local is_dragging = false
        if G.HUD_SPOTIFY.states and G.HUD_SPOTIFY.states.drag and G.HUD_SPOTIFY.states.drag.is then
            is_dragging = true
        end
        if G.CONTROLLER and G.CONTROLLER.dragging and G.CONTROLLER.dragging.target == G.HUD_SPOTIFY then
            is_dragging = true
        end

        if is_dragging then
            HUDPlayer.was_dragging = true
            if G.HUD_SPOTIFY.T and G.SPOTIFY.config and G.SPOTIFY.config.current then
                G.SPOTIFY.config.current.hud_x = G.HUD_SPOTIFY.T.x
                G.SPOTIFY.config.current.hud_y = G.HUD_SPOTIFY.T.y
            end
            return
        end

        if HUDPlayer.was_dragging then
            HUDPlayer.was_dragging = false
            if G.SPOTIFY.config then
                G.SPOTIFY.config.save()
            end
        end
    end

    if not force and not state_changed and G.HUD_SPOTIFY then
        return
    end

    HUDPlayer.last_title = title
    HUDPlayer.last_artist = artist
    HUDPlayer.last_is_playing = is_playing
    HUDPlayer.last_connected = is_connected
    HUDPlayer.last_sec = cur_sec

    local prev_x = nil
    local prev_y = nil
    if G.HUD_SPOTIFY and G.HUD_SPOTIFY.T then
        prev_x = G.HUD_SPOTIFY.T.x
        prev_y = G.HUD_SPOTIFY.T.y
        G.HUD_SPOTIFY:remove()
        G.HUD_SPOTIFY = nil
    end

    local cfg = G.SPOTIFY.config and G.SPOTIFY.config.current or {}
    local spawn_x = prev_x or cfg.hud_x or 10.0
    local spawn_y = prev_y or cfg.hud_y or 0.25

    local Draggable = get_draggable_container()
    if Draggable then
        G.HUD_SPOTIFY = Draggable({
            T = { x = spawn_x, y = spawn_y },
            VT = { x = spawn_x, y = spawn_y },
            config = {
                major = G,
                bond = 'Weak',
                instance_type = 'POPUP',
                can_collide = true,
                can_drag = true
            },
            definition = HUDPlayer.create_definition(),
            zoom = true,
            can_drag = true
        })
    elseif G.ROOM_ATTACH then
        G.HUD_SPOTIFY = UIBox({
            definition = HUDPlayer.create_definition(),
            config = {
                align = "tri",
                offset = { x = -0.25, y = 0.25 },
                major = G.ROOM_ATTACH,
                bond = "Weak"
            }
        })
    end
end

return HUDPlayer
