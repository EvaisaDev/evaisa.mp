local ffi = require("ffi")

local _run_hidden = nil

pcall(function()
    ffi.cdef([[
        typedef struct {
            unsigned int   cb;
            char*          r1;
            char*          desk;
            char*          title;
            unsigned int   x, y, xs, ys, xcc, ycc, fa, flags;
            unsigned short ws, cr;
            unsigned char* r2;
            void*          si;
            void*          so;
            void*          se;
        } _EmpStartupInfo;
        typedef struct {
            void*        hp;
            void*        ht;
            unsigned int pid;
            unsigned int tid;
        } _EmpProcInfo;
        int CreateProcessA(const char*, char*, void*, void*, int, unsigned int, void*, const char*, _EmpStartupInfo*, _EmpProcInfo*);
        unsigned int WaitForSingleObject(void*, unsigned int);
        int CloseHandle(void*);
    ]])
    local k32 = ffi.load("kernel32")
    _run_hidden = function(cmd, timeout_ms)
        local si = ffi.new("_EmpStartupInfo")
        si.cb = ffi.sizeof(si)
        local pi = ffi.new("_EmpProcInfo")
        local buf = ffi.new("char[?]", #cmd + 1, cmd)
        local ok = k32.CreateProcessA(nil, buf, nil, nil, 0, 0x08000000, nil, nil, si, pi)
        if ok == 0 then return false end
        k32.WaitForSingleObject(pi.hp, timeout_ms or 13000)
        k32.CloseHandle(pi.hp)
        k32.CloseHandle(pi.ht)
        return true
    end
end)

local _req_seq = 0

local function request(method, path, body, extra_headers)
    _req_seq = _req_seq + 1
    local uid = tostring(_req_seq)
    local base = ModSettingGet("evaisa.mp.hub_server_url") or "http://localhost:3000"
    local url = base .. path
    local tmp = os.getenv("TEMP") or os.getenv("TMP") or "C:\\Temp"
    local fin  = tmp .. "\\emp_hub_in_"  .. uid .. ".json"
    local fout = tmp .. "\\emp_hub_out_" .. uid .. ".json"

    local parts = {"curl.exe", "-s", "--max-time", "11", "-X", method}

    if body then
        local f = io.open(fin, "w")
        if f then
            f:write(json.stringify(body))
            f:close()
            table.insert(parts, '-H "Content-Type: application/json"')
            table.insert(parts, '-d @"' .. fin .. '"')
        end
    end

    if extra_headers then
        for k, v in pairs(extra_headers) do
            table.insert(parts, '-H "' .. k .. ': ' .. v .. '"')
        end
    end

    table.insert(parts, '-o "' .. fout .. '"')
    table.insert(parts, '"' .. url .. '"')

    local cmd = table.concat(parts, " ")

    if _run_hidden then
        _run_hidden(cmd, 13000)
    else
        os.execute(cmd)
    end

    os.remove(fin)

    local f = io.open(fout, "r")
    if not f then return nil, "no_response" end
    local raw = f:read("*all")
    f:close()
    os.remove(fout)

    if not raw or raw == "" then return nil, "empty" end

    local ok, data = pcall(json.parse, raw)
    if not ok or not data then return nil, "bad_json" end
    if data.error then return nil, data.error end
    return data, nil
end

local http = {}
http.get = function(path, headers) return request("GET", path, nil, headers) end
http.post = function(path, body, headers) return request("POST", path, body, headers) end
http.put = function(path, body, headers) return request("PUT", path, body, headers) end
http.delete = function(path, headers) return request("DELETE", path, nil, headers) end
return http
