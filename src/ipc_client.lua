local IPCClient = {}

local last_logged_track = nil
local last_logged_playing = nil
local last_logged_online = nil

local function parse_simple_json(str)
    if not str or str == "" then return nil end
    if JSON and JSON.decode then
        local ok, res = pcall(JSON.decode, str)
        if ok and res then return res end
    end
    local ok, res = pcall(function()
        local sanitized = str:gsub('"(.-)"%s*:', '["%1"]='):gsub(':null', '=nil'):gsub(':true', '=true'):gsub(':false', '=false')
        local fn = load("return " .. sanitized)
        return fn and fn() or nil
    end)
    if ok and res then return res end
    return nil
end

function IPCClient.init(mod_path, port)
    IPCClient.mod_path = mod_path or ""
    IPCClient.port = port or 53188
    IPCClient.req_counter = 0

    IPCClient.in_channel_name = "spotify_ipc_in_" .. tostring(os.time())
    IPCClient.out_channel_name = "spotify_ipc_out_" .. tostring(os.time())

    IPCClient.in_channel = love.thread.getChannel(IPCClient.in_channel_name)
    IPCClient.out_channel = love.thread.getChannel(IPCClient.out_channel_name)

    local worker_file = IPCClient.mod_path .. "/src/ipc_worker.lua"
    local worker_code = nil
    if NFS and NFS.read then
        worker_code = NFS.read(worker_file)
    elseif love.filesystem.getInfo("src/ipc_worker.lua") then
        worker_code = love.filesystem.read("src/ipc_worker.lua")
    end

    if worker_code then
        IPCClient.thread = love.thread.newThread(worker_code)
    else
        IPCClient.thread = love.thread.newThread("src/ipc_worker.lua")
    end

    IPCClient.thread:start(IPCClient.in_channel_name, IPCClient.out_channel_name, tostring(IPCClient.port))
end

function IPCClient.send_request(method, path, body_tbl)
    IPCClient.req_counter = IPCClient.req_counter + 1
    local req_id = tostring(IPCClient.req_counter)
    local body_str = ""

    if body_tbl then
        local parts = {}
        for k, v in pairs(body_tbl) do
            if type(v) == "string" then
                table.insert(parts, string.format('"%s":"%s"', k, v))
            elseif type(v) == "number" or type(v) == "boolean" then
                table.insert(parts, string.format('"%s":%s', k, tostring(v)))
            end
        end
        body_str = "{" .. table.concat(parts, ",") .. "}"
    end

    IPCClient.in_channel:push({
        id = req_id,
        method = method,
        path = path,
        body = body_str
    })
    return req_id
end

function IPCClient.play(uri)
    if uri and uri ~= "" then
        IPCClient.send_request("POST", "/play", { uri = uri })
    else
        IPCClient.send_request("POST", "/resume", {})
    end
end

function IPCClient.pause()
    IPCClient.send_request("POST", "/pause", {})
end

function IPCClient.resume()
    IPCClient.send_request("POST", "/resume", {})
end

function IPCClient.toggle()
    IPCClient.send_request("POST", "/toggle", {})
end

function IPCClient.next()
    IPCClient.send_request("POST", "/next", {})
end

function IPCClient.previous()
    IPCClient.send_request("POST", "/prev", {})
end

function IPCClient.set_volume(vol)
    IPCClient.send_request("POST", "/volume", { volume = math.floor(vol) })
end

function IPCClient.set_audio_effect(effect_type, params)
    local body = { effect = effect_type or "none" }
    if params and type(params) == "table" then
        for k, v in pairs(params) do body[k] = v end
    end
    IPCClient.send_request("POST", "/effect", body)
end

function IPCClient.set_target_source(source)
    IPCClient.send_request("POST", "/source", { source = source or "auto" })
end

function IPCClient.update()
    if not IPCClient.out_channel then return end

    while true do
        local msg = IPCClient.out_channel:pop()
        if not msg then break end

        if msg.type == "STATUS_UPDATE" and msg.data then
            local state_data = parse_simple_json(msg.data)
            if state_data and G.SPOTIFY then
                G.SPOTIFY.state.online = true
                G.SPOTIFY.state.connected = state_data.connected or false
                G.SPOTIFY.state.username = state_data.username
                G.SPOTIFY.state.device_name = state_data.device_name or "Balatro Deck Player"
                G.SPOTIFY.state.is_playing = state_data.is_playing or false
                G.SPOTIFY.state.volume = state_data.volume or 80
                G.SPOTIFY.state.target_source = state_data.target_source or "auto"
                G.SPOTIFY.state.available_sources = state_data.available_sources or { "auto" }
                if not IPCClient.initial_source_synced then
                    IPCClient.initial_source_synced = true
                    if G.SPOTIFY and G.SPOTIFY.config and G.SPOTIFY.config.current and G.SPOTIFY.config.current.target_source then
                        IPCClient.set_target_source(G.SPOTIFY.config.current.target_source)
                    end
                end

                local new_track = state_data.current_track
                local track_changed = false
                if new_track then
                    local cur_id = G.SPOTIFY.state.current_track and G.SPOTIFY.state.current_track.id or ""
                    if cur_id ~= new_track.id then
                        track_changed = true
                        G.SPOTIFY.state.current_track = new_track
                    end
                end

                local daemon_pos = state_data.position_ms or 0
                local cur_pos = G.SPOTIFY.state.position_ms or 0
                local now = love.timer and love.timer.getTime() or (socket and socket.gettime() or 0)
                if track_changed or not state_data.is_playing or math.abs(daemon_pos - cur_pos) > 1500 then
                    G.SPOTIFY.state.anchor_pos = daemon_pos
                    G.SPOTIFY.state.anchor_time = now
                    G.SPOTIFY.state.position_ms = daemon_pos
                end
            end
        elseif msg.type == "STATUS_OFFLINE" then
            if G.SPOTIFY then
                G.SPOTIFY.state.online = false
                G.SPOTIFY.state.is_playing = false
            end
        end
    end
end

function IPCClient.stop()
    if IPCClient.in_channel then
        IPCClient.in_channel:push({ type = "SHUTDOWN" })
    end
end

return IPCClient
