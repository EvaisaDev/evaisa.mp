local pollnet = dofile_once("mods/evaisa.mp/lib/pollnet.lua")
local json = dofile_once("mods/evaisa.mp/lib/json.lua")

hub_http_pending = hub_http_pending or {}

local function request(method, path, body, extra_headers, callback)
    local base = hub_server_url or "http://localhost:3000"
    local url = base .. path

    local headers = { ["content-type"] = "application/json" }
    if extra_headers then
        for k, v in pairs(extra_headers) do headers[k] = v end
    end

    local sock = pollnet.Socket()
    if method == "GET" or method == "DELETE" then
        sock:http_get(url, headers, true)
    else
        local body_str = body and json.stringify(body) or "{}"
        if method == "DELETE" then
            headers["x-http-method-override"] = "DELETE"
            sock:http_post(url, headers, body_str, true)
        else
            sock:http_post(url, headers, body_str, true)
        end
    end

    table.insert(hub_http_pending, { sock = sock, cb = callback, method = method })
end

local http = {}

http.poll = function()
    local i = 1
    while i <= #hub_http_pending do
        local entry = hub_http_pending[i]
        local ok, msg = entry.sock:poll()
        if msg ~= nil then
            entry.sock:close()
            table.remove(hub_http_pending, i)
            if entry.cb then
                if not ok then
                    entry.cb(nil, msg)
                else
                    local pok, data = pcall(json.parse, msg)
                    if not pok or not data then
                        entry.cb(nil, "bad_json")
                    elseif data.error then
                        entry.cb(nil, data.error)
                    else
                        entry.cb(data, nil)
                    end
                end
            end
        elseif not ok then
            entry.sock:close()
            table.remove(hub_http_pending, i)
            if entry.cb then entry.cb(nil, "error") end
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
