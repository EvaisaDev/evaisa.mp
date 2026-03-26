hub_state = hub_state or nil
hub_token = hub_token or nil
hub_heartbeat_last_frame = hub_heartbeat_last_frame or -99999
hub_spectator_mode = hub_spectator_mode or false
hub_source_lobby = hub_source_lobby or false

local function hub_http()
    return dofile_once("mods/evaisa.mp/lib/http.lua")
end

local function hub_auth()
    if hub_state == nil then return {} end
    return {
        ["x-hub-token"] = hub_token or "",
        ["x-steam-id"] = tostring(steam_utils.getSteamID() or ""),
    }
end

function hub_is_owner()
    if hub_state == nil then return false end
    return tostring(hub_state.owner_steam_id) == tostring(steam_utils.getSteamID())
end

function hub_is_mod()
    if hub_state == nil then return false end
    local my_id = tostring(steam_utils.getSteamID())
    for _, v in ipairs(hub_state.moderators or {}) do
        if tostring(v) == my_id then return true end
    end
    return false
end

function hub_is_owner_or_mod()
    return hub_is_owner() or hub_is_mod()
end

function hub_create(name, steam_id, cb)
    hub_http().post("/hub/create", {
        owner_steam_id = tostring(steam_id),
        name = name
    }, nil, function(data, err)
        print("[HUB] hub_create inner cb: cb=" .. tostring(cb) .. " data=" .. tostring(data) .. " err=" .. tostring(err))
        if cb then cb(data, err) end
    end)
end

function hub_join_by_code(invite_code, steam_id, cb)
    hub_http().post("/hub/join", {
        invite_code = invite_code,
        steam_id = tostring(steam_id)
    }, nil, function(data, err)
        if cb then cb(data, err) end
    end)
end

function hub_leave()
    if hub_state == nil then return end
    hub_http().post("/hub/" .. hub_state.id .. "/leave", {}, hub_auth(), nil)
    hub_state = nil
    hub_token = nil
    hub_source_lobby = false
    hub_spectator_mode = false
    menu_status = status.main_menu
end

function hub_heartbeat()
    if hub_state == nil then return end
    hub_http().post("/hub/" .. hub_state.id .. "/heartbeat", {}, hub_auth(), function(data, err)
        if data then
            if data.online_members then hub_state.online_members = data.online_members end
            if data.lobbies then hub_state.lobbies = data.lobbies end
            if data.feed then hub_state.feed = data.feed end
        end
    end)
end

function hub_refresh(cb)
    if hub_state == nil then return end
    hub_http().get("/hub/" .. hub_state.id, hub_auth(), function(data, err)
        if data then
            hub_state.online_members = data.online_members or {}
            hub_state.lobbies = data.lobbies or {}
            hub_state.feed = data.feed or {}
            hub_state.moderators = data.moderators or {}
            hub_state.settings = data.settings or {}
            hub_state.name = data.name or hub_state.name
        end
        if cb then cb(data, err) end
    end)
end

function hub_create_lobby(name, gamemode, settings, cb)
    if hub_state == nil then return end
    hub_http().post("/hub/" .. hub_state.id .. "/lobby", {
        name = name,
        gamemode = gamemode or "",
        settings = settings or {}
    }, hub_auth(), function(data, err)
        if data and data.lobby then
            hub_state.lobbies = hub_state.lobbies or {}
            hub_state.lobbies[data.lobby.token_id] = data.lobby
        end
        if cb then cb(data and data.lobby, err) end
    end)
end

function hub_delete_lobby(token_id, cb)
    if hub_state == nil then return end
    hub_http().delete("/hub/" .. hub_state.id .. "/lobby/" .. token_id, hub_auth(), function(data, err)
        if not err and hub_state.lobbies then
            hub_state.lobbies[token_id] = nil
        end
        if cb then cb(data, err) end
    end)
end

function hub_update_lobby_state(token_id, fields, cb)
    if hub_state == nil then return end
    hub_http().put("/hub/" .. hub_state.id .. "/lobby/" .. token_id .. "/state", fields, hub_auth(), function(data, err)
        if data and data.lobby and hub_state.lobbies then
            hub_state.lobbies[token_id] = data.lobby
        end
        if cb then cb(data, err) end
    end)
end

function hub_activate_lobby(token_id, steam_lobby_id, cb)
    hub_update_lobby_state(token_id, { steam_lobby_id = tostring(steam_lobby_id) }, cb)
end

function hub_set_lobby_in_progress(token_id, in_progress, cb)
    hub_update_lobby_state(token_id, { in_progress = in_progress }, cb)
end

function hub_add_moderator(steam_id, cb)
    if hub_state == nil then return end
    hub_http().post("/hub/" .. hub_state.id .. "/moderator", { steam_id = tostring(steam_id) }, hub_auth(), function(data, err)
        if data then hub_state.moderators = data.moderators or hub_state.moderators end
        if cb then cb(data, err) end
    end)
end

function hub_remove_moderator(steam_id, cb)
    if hub_state == nil then return end
    hub_http().delete("/hub/" .. hub_state.id .. "/moderator/" .. tostring(steam_id), hub_auth(), function(data, err)
        if data then hub_state.moderators = data.moderators or hub_state.moderators end
        if cb then cb(data, err) end
    end)
end

function hub_update_settings(settings, cb)
    if hub_state == nil then return end
    hub_http().put("/hub/" .. hub_state.id .. "/settings", settings, hub_auth(), function(data, err)
        if data then hub_state.settings = data.settings or hub_state.settings end
        if cb then cb(data, err) end
    end)
end

function hub_report_feed(event_type, lobby_name, winner, score, extra)
    if hub_state == nil then return end
    hub_http().post("/hub/" .. hub_state.id .. "/feed", {
        event_type = event_type,
        lobby_name = lobby_name or "",
        winner = winner or "",
        score = score or "",
        extra = extra or ""
    }, hub_auth(), nil)
end

function hub_delete(hub_id, cb)
    if hub_state == nil then return end
    hub_http().delete("/hub/" .. hub_id, hub_auth(), function(data, err)
        if not err then
            hub_state = nil
            hub_token = nil
            hub_source_lobby = false
            hub_spectator_mode = false
            menu_status = status.main_menu
        end
        if cb then cb(data, err) end
    end)
end

function hub_lobbies_as_sorted_list()
    if hub_state == nil or hub_state.lobbies == nil then return {} end
    local list = {}
    for _, v in pairs(hub_state.lobbies) do
        table.insert(list, v)
    end
    table.sort(list, function(a, b) return (a.created_at or 0) < (b.created_at or 0) end)
    return list
end

function hub_feed_sorted()
    if hub_state == nil or hub_state.feed == nil then return {} end
    local copy = {}
    for _, v in ipairs(hub_state.feed) do
        table.insert(copy, v)
    end
    table.sort(copy, function(a, b) return (a.timestamp or 0) > (b.timestamp or 0) end)
    return copy
end
