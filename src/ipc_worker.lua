local in_channel_name, out_channel_name, port = ...

local socket = require("socket")
local in_channel = love.thread.getChannel(in_channel_name)
local out_channel = love.thread.getChannel(out_channel_name)

local daemon_host = "127.0.0.1"
local daemon_port = tonumber(port) or 53188

local function http_request(method, path, body_str, timeout)
    timeout = timeout or 0.2
    local tcp = socket.tcp()
    tcp:settimeout(timeout)

    local succ, err = tcp:connect(daemon_host, daemon_port)
    if not succ then
        tcp:close()
        return nil, "Connection failed: " .. tostring(err)
    end

    body_str = body_str or ""
    local headers = string.format(
        "%s %s HTTP/1.1\r\nHost: %s:%d\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s",
        method, path, daemon_host, daemon_port, #body_str, body_str
    )

    tcp:send(headers)

    local response = ""
    while true do
        local chunk, status, partial = tcp:receive(4096)
        if chunk then
            response = response .. chunk
        elseif partial then
            response = response .. partial
        end
        if status == "closed" or status == "timeout" then
            break
        end
    end
    tcp:close()

    local header_end = response:find("\r\n\r\n")
    if header_end then
        local body = response:sub(header_end + 4)
        return body, nil
    end

    return response, nil
end

local last_poll = 0
local poll_interval = 0.35

while true do
    local now = socket.gettime()

    local req = in_channel:pop()
    if req then
        if req.type == "SHUTDOWN" then
            break
        end

        local method = req.method or "GET"
        local path = req.path or "/status"
        local body = req.body or ""
        local res_body, err = http_request(method, path, body, 0.4)

        out_channel:push({
            req_id = req.id,
            path = path,
            data = res_body,
            error = err
        })
    end

    if now - last_poll >= poll_interval then
        last_poll = now
        local status_body, err = http_request("GET", "/status", "", 0.2)
        if status_body and not err then
            out_channel:push({
                type = "STATUS_UPDATE",
                data = status_body
            })
        else
            out_channel:push({
                type = "STATUS_OFFLINE",
                error = err
            })
        end
    end

    socket.sleep(0.02)
end
