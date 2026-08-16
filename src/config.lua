local Config = {}

Config.defaults = {
    enabled = true,
    auto_start_daemon = true,
    daemon_port = 53188,
    device_name = "Balatro Deck Player",
    mute_vanilla_music = true,
    sync_volume = true,
    hud_enabled = true,
    hud_scale = 1.0,
    hud_x = 0.78,
    hud_y = 0.03,
    reactive_effects = true,
    target_source = "auto"
}

Config.current = {}

local function deep_copy(obj)
    if type(obj) ~= 'table' then return obj end
    local res = {}
    for k, v in pairs(obj) do res[deep_copy(k)] = deep_copy(v) end
    return res
end

function Config.init(mod_path)
    Config.mod_path = mod_path or ""
    Config.config_path = "spotify_config.json"
    Config.current = deep_copy(Config.defaults)
    Config.load()
end

function Config.load()
    local content = nil
    if NFS and NFS.read and Config.mod_path ~= "" then
        content = NFS.read(Config.mod_path .. "/" .. Config.config_path)
    elseif love.filesystem.getInfo(Config.config_path) then
        content = love.filesystem.read(Config.config_path)
    end

    if content then
        local success, data = pcall(function()
            if JSON and JSON.decode then
                return JSON.decode(content)
            else
                local fn = load("return " .. content:gsub('"(.-)"%s*:', '["%1"]='))
                return fn and fn() or nil
            end
        end)
        if success and type(data) == "table" then
            for k, v in pairs(data) do
                if type(v) == "table" and type(Config.current[k]) == "table" then
                    for k2, v2 in pairs(v) do
                        Config.current[k][k2] = v2
                    end
                else
                    Config.current[k] = v
                end
            end
        end
    end
end

function Config.save()
    local function serialize_json(val)
        local t = type(val)
        if t == "number" or t == "boolean" then
            return tostring(val)
        elseif t == "string" then
            return string.format("%q", val)
        elseif t == "table" then
            local is_array = #val > 0
            local items = {}
            if is_array then
                for _, v in ipairs(val) do
                    table.insert(items, serialize_json(v))
                end
                return "[" .. table.concat(items, ",") .. "]"
            else
                for k, v in pairs(val) do
                    table.insert(items, string.format("%q:%s", tostring(k), serialize_json(v)))
                end
                return "{" .. table.concat(items, ",") .. "}"
            end
        end
        return "null"
    end

    local json_str = serialize_json(Config.current)
    if NFS and NFS.write and Config.mod_path ~= "" then
        NFS.write(Config.mod_path .. "/" .. Config.config_path, json_str)
    else
        love.filesystem.write(Config.config_path, json_str)
    end
end

return Config
