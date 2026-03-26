local pollnet_ok, pollnet = pcall(dofile_once, "mods/evaisa.mp/lib/pollnet.lua")
local json = dofile_once("mods/evaisa.mp/lib/json.lua")

if pollnet_ok then
    pcall(function() pollnet.init_hack_static() end)
end

hub_http_pending = hub_http_pending or {}

local function request(method, path, body, extra_headers, callback)
    local base = hub_server_url or "http://localhost:3000"
    local url = base .. path

    if not pollnet_ok then
        if callback then callback(nil, "pollnet_load_failed: " .. tostring(pollnet)) end
        return
    end

    local headers = { ["content-type"] = "application/json" }
    if extra_headers then
        for k, v in pairs(extra_headers) do headers[k] = v end
    end

    local ok, err = pcall(function()
        local sock = pollnet.Socket()
        if method == "GET" then
            sock:http_get(url, headers, true)
        elseif method == "DELETE" then
            headers["x-http-method-override"] = "DELETE"
            sock:http_post(url, headers, "{}", true)
        else
            local body_str = body and json.stringify(body) or "{}"
            sock:http_post(url, headers, body_str, true)
        end
        table.insert(hub_http_pending, { sock = sock, cb = callback, method = method })
    end)
    if not ok then
        if callback then callback(nil, "socket_open_failed: " .. tostring(err)) end
    end
end

local http = {}

http.poll = function()
    local i = 1
    while i <= #hub_http_pending do
        local entry = hub_http_pending[i]
        local poll_ok, msg = entry.sock:poll()
        if msg ~= nil then
            entry.sock:close()
            table.remove(hub_http_pending, i)
            if entry.cb then
                if not poll_ok then
                    entry.cb(nil, tostring(msg))
                else
                    local pok, data = pcall(json.parse, msg)
                    if not pok or not data then
                        entry.cb(nil, "bad_json: " .. tostring(msg):sub(1, 80))
                    elseif data.error then
                        entry.cb(nil, data.error)
                    else
                        entry.cb(data, nil)
                    end
                end
            end
        elseif not poll_ok then
            entry.sock:close()
            table.remove(hub_http_pending, i)
            if entry.cb then entry.cb(nil, "poll_error") end
        else
            i = i + 1
        end
    end
end

http.get = function(path, headers, cb)
    request("GET", path, nil, headers, cb)
end
http.post = function(path, body, headers, cb)
    request("POST", path, body, headers, cb)
end
http.put = function(path, body, headers, cb)
    request("PUT", path, body, headers, cb)
end
http.delete = function(path, headers, cb)
    request("DELETE", path, nil, headers, cb)
end

return http
