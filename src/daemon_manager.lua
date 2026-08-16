local DaemonManager = {}

DaemonManager.process_handle = nil
DaemonManager.is_running = false
DaemonManager.executable_path = nil

function DaemonManager.init(mod_path, config)
    DaemonManager.mod_path = mod_path or ""
    DaemonManager.config = config

    local os_name = love.system.getOS()
    local exe_name = "daemon-x86_64-windows.exe"

    if os_name == "Linux" then
        exe_name = "daemon-x86_64-linux"
    elseif os_name == "OS X" then
        exe_name = "daemon-x86_64-apple-darwin"
    end

    local full_path = DaemonManager.mod_path .. "/bin/" .. exe_name
    if os_name == "Windows" then
        full_path = full_path:gsub("/", "\\")
    end

    DaemonManager.executable_path = full_path
    DaemonManager.os_name = os_name
end

function DaemonManager.binary_exists()
    if not DaemonManager.executable_path then return false end
    if NFS and NFS.getInfo then
        return NFS.getInfo(DaemonManager.executable_path) ~= nil
    end
    local file = io.open(DaemonManager.executable_path, "r")
    if file then
        file:close()
        return true
    end
    return false
end

function DaemonManager.start()
    if DaemonManager.is_running then return true end

    if not DaemonManager.binary_exists() then
        return false
    end

    local port = DaemonManager.config.current.daemon_port or 53188
    local device_name = DaemonManager.config.current.device_name or "Balatro Deck Player"
    local creds_dir = DaemonManager.mod_path .. "/.spotify_cache"

    if DaemonManager.os_name == "Windows" then
        creds_dir = creds_dir:gsub("/", "\\")
        local cmd = string.format('start "" /B "%s" --port %d --device-name "%s" --credentials-dir "%s"',
            DaemonManager.executable_path, port, device_name, creds_dir)
        os.execute(cmd)
    else
        local cmd = string.format('"%s" --port %d --device-name "%s" --credentials-dir "%s" > /dev/null 2>&1 &',
            DaemonManager.executable_path, port, device_name, creds_dir)
        os.execute(cmd)
    end

    DaemonManager.is_running = true
    return true
end

function DaemonManager.stop()
    if not DaemonManager.is_running then return end
    DaemonManager.is_running = false

    pcall(function()
        if G.SPOTIFY and G.SPOTIFY.ipc then
            G.SPOTIFY.ipc.post("/shutdown", {})
        end
    end)

    pcall(function()
        if DaemonManager.os_name == "Windows" then
            os.execute('start "" /B taskkill /F /IM daemon-x86_64-windows.exe >nul 2>&1')
        else
            os.execute('killall -9 daemon-x86_64-linux >/dev/null 2>&1 &')
        end
    end)
end

return DaemonManager
