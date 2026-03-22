dofile_once("data/scripts/lib/utilities.lua")

hub_ui_new_lobby_name     = hub_ui_new_lobby_name or ""
hub_ui_new_lobby_gamemode = hub_ui_new_lobby_gamemode or 1
hub_ui_creating_lobby     = hub_ui_creating_lobby or false
hub_ui_right_panel        = hub_ui_right_panel or nil
hub_ui_left_panel         = hub_ui_left_panel or nil
hub_ui_hub_name_input     = hub_ui_hub_name_input or ""
hub_ui_join_code_input    = hub_ui_join_code_input or ""
hub_ui_hub_err            = hub_ui_hub_err or nil
hub_ui_hub_err_frame      = hub_ui_hub_err_frame or 0
hub_ui_selected_member    = hub_ui_selected_member or nil
hub_ui_activate_busy      = hub_ui_activate_busy or {}
hub_ui_feed_scroll_pos    = hub_ui_feed_scroll_pos or 0
hub_ui_lobby_settings     = hub_ui_lobby_settings or {}
hub_ui_editing_lobby      = hub_ui_editing_lobby or nil
hub_pending_spectate      = hub_pending_spectate or false

local hub_gui = hub_gui or GuiCreate()
GuiStartFrame(hub_gui)

local sw, sh = GuiGetScreenDimensions(hub_gui)
local cx      = sw / 2
local cy      = sh / 2

local CENTER_W  = 220
local CENTER_H  = 300
local SIDE_W    = 188
local SIDE_H    = 300
local PANEL_GAP = 10

local function hub_err(msg_str)
    hub_ui_hub_err       = msg_str
    hub_ui_hub_err_frame = GameGetFrameNum()
end

local function draw_err()
    if hub_ui_hub_err == nil then return end
    if GameGetFrameNum() - hub_ui_hub_err_frame > 300 then
        hub_ui_hub_err = nil
        return
    end
    GuiColorSetForNextWidget(hub_gui, 1, 0.3, 0.3, 1)
    GuiZSetForNextWidget(hub_gui, -7000)
    GuiText(hub_gui, cx - 80, sh - 30, hub_ui_hub_err)
end

local function ts(key)
    return GameTextGetTranslatedOrNot(key)
end

local function lobby_gamemode_name(gamemode_id)
    if gamemode_id == nil or gamemode_id == "" then return "?" end
    local gm = FindGamemode(gamemode_id)
    if gm then return ts(gm.name) end
    return gamemode_id
end

local function format_feed_entry(entry)
    if entry.event_type == "win" then
        local s = entry.lobby_name ~= "" and ("[" .. entry.lobby_name .. "] ") or ""
        s = s .. ts("$hub_feed_win") .. ": " .. entry.winner
        if entry.score and entry.score ~= "" then s = s .. " (" .. entry.score .. ")" end
        return s
    end
    return entry.event_type .. (entry.extra ~= "" and (": " .. entry.extra) or "")
end

local hub_showing = hub_state ~= nil and (menu_status == status.hub or hub_source_lobby == true)

if hub_showing and hub_source_lobby and lobby_code and hub_pending_spectate then
    hub_pending_spectate = false
    steam_utils.send("spectate", {}, steam_utils.messageTypes.AllPlayers, lobby_code, true, true)
end

if hub_showing then

    local heartbeat_interval = 600
    if GameGetFrameNum() - hub_heartbeat_last_frame >= heartbeat_interval then
        hub_heartbeat_last_frame = GameGetFrameNum()
        hub_heartbeat()
    end

    local is_owner     = hub_is_owner()
    local is_owner_mod = hub_is_owner_or_mod()

    local lobby_list = hub_lobbies_as_sorted_list()

    DrawWindow(hub_gui, -5000, cx, cy, CENTER_W, CENTER_H, function()
        GuiColorSetForNextWidget(hub_gui, 0, 0, 0, 0.3)
        GuiText(hub_gui, 0, 0, hub_state.name .. "  [" .. (hub_state.invite_code or "?") .. "]")
    end, true, function()
        GuiLayoutBeginVertical(hub_gui, 0, 0, true, 0, 0)

        GuiLayoutBeginHorizontal(hub_gui, 0, 0, true, 0, 0)
        if GuiButton(hub_gui, NewID("hub_btn"), 0, 0, ts("$hub_leave")) then
            hub_leave()
        end

        if hub_spectator_mode then
            GuiColorSetForNextWidget(hub_gui, 0.4, 1, 0.4, 1)
        end
        if GuiButton(hub_gui, NewID("hub_btn"), 0, 0, hub_spectator_mode and ts("$hub_spectator_on") or ts("$hub_spectator_off")) then
            hub_spectator_mode = not hub_spectator_mode
        end
        GuiLayoutEnd(hub_gui)

        GuiLayoutBeginHorizontal(hub_gui, 0, 0, true, 0, 0)
        if GuiButton(hub_gui, NewID("hub_btn"), 0, 0, ts("$hub_refresh")) then
            hub_refresh()
        end

        local members_btn = ts("$hub_members") .. " >"
        if hub_ui_right_panel == "members" then members_btn = ts("$hub_members") .. " <" end
        if GuiButton(hub_gui, NewID("hub_btn"), 0, 0, members_btn) then
            hub_ui_right_panel = hub_ui_right_panel == "members" and nil or "members"
        end

        local feed_btn = ts("$hub_feed") .. " >"
        if hub_ui_right_panel == "feed" then feed_btn = ts("$hub_feed") .. " <" end
        if GuiButton(hub_gui, NewID("hub_btn"), 0, 0, feed_btn) then
            hub_ui_right_panel = hub_ui_right_panel == "feed" and nil or "feed"
        end
        GuiLayoutEnd(hub_gui)

        if is_owner then
            local settings_btn = "> " .. ts("$hub_settings")
            if hub_ui_left_panel == "settings" then settings_btn = "< " .. ts("$hub_settings") end
            if GuiButton(hub_gui, NewID("hub_btn"), 0, 0, settings_btn) then
                hub_ui_left_panel = hub_ui_left_panel == "settings" and nil or "settings"
            end
        end

        GuiText(hub_gui, 2, 0, "--------------------")
        GuiText(hub_gui, 2, 0, ts("$hub_lobbies"))

        if is_owner then
            if hub_ui_creating_lobby then
                GuiLayoutBeginVertical(hub_gui, 0, 0, true, 2, 2)

                GuiText(hub_gui, 0, 0, ts("$hub_new_lobby_name"))
                hub_ui_new_lobby_name = GuiTextInput(hub_gui, NewID("hub_new_lobby"), 0, 0, hub_ui_new_lobby_name, 150, 30,
                    "qwertyuiopasdfghjklzxcvbnmQWERTYUIOPASDFGHJKLZXCVBNM1234567890 !@#$%^&*()_-+")
                local _, _, hov = GuiGetPreviousWidgetInfo(hub_gui)
                if hov then GameAddFlagRun("chat_bind_disabled") end

                GuiText(hub_gui, 0, 0, ts("$hub_new_lobby_mode"))
                local gm_names = {}
                for _, gm in ipairs(gamemodes) do
                    table.insert(gm_names, ts(gm.name))
                end
                if #gm_names == 0 then
                    GuiColorSetForNextWidget(hub_gui, 0.5, 0.5, 0.5, 1)
                    GuiText(hub_gui, 0, 0, ts("$mp_no_gamemodes"))
                else
                    hub_ui_new_lobby_gamemode = hub_ui_new_lobby_gamemode or 1
                    if hub_ui_new_lobby_gamemode > #gm_names then hub_ui_new_lobby_gamemode = 1 end
                    if GuiButton(hub_gui, NewID("hub_new_lobby"), 0, 0, gm_names[hub_ui_new_lobby_gamemode]) then
                        hub_ui_new_lobby_gamemode = (hub_ui_new_lobby_gamemode % #gm_names) + 1
                    end
                end

                GuiLayoutBeginHorizontal(hub_gui, 0, 0, true, 0, 0)
                if GuiButton(hub_gui, NewID("hub_new_lobby"), 0, 0, ts("$mp_create_lobby")) then
                    if hub_ui_new_lobby_name and #hub_ui_new_lobby_name > 0 then
                        local gm_id = (gamemodes[hub_ui_new_lobby_gamemode] or {}).id or ""
                        local lobby, err = hub_create_lobby(hub_ui_new_lobby_name, gm_id, {})
                        if err then
                            hub_err(ts("$hub_err_create_lobby") .. ": " .. tostring(err))
                        else
                            hub_ui_creating_lobby = false
                            hub_ui_new_lobby_name = ""
                        end
                    end
                end
                if GuiButton(hub_gui, NewID("hub_new_lobby"), 0, 0, ts("$hub_cancel")) then
                    hub_ui_creating_lobby = false
                    hub_ui_new_lobby_name = ""
                end
                GuiLayoutEnd(hub_gui)
                GuiLayoutEnd(hub_gui)
            else
                if GuiButton(hub_gui, NewID("hub_btn"), 0, 0, ts("$hub_create_lobby")) then
                    hub_ui_creating_lobby = true
                end
            end
        end

        if #lobby_list == 0 then
            GuiColorSetForNextWidget(hub_gui, 0.5, 0.5, 0.5, 1)
            GuiText(hub_gui, 2, 0, ts("$hub_no_lobbies"))
        end

        for _, lobby in ipairs(lobby_list) do
            local token_id  = lobby.token_id
            local steam_lid = lobby.steam_lobby_id
            local is_active = steam_lid and steam_lid ~= "" and steam_lid ~= "null"
            local gm_name   = lobby_gamemode_name(lobby.gamemode)

            GuiLayoutBeginHorizontal(hub_gui, 0, 0, true, 0, 0)

            if is_active then
                GuiColorSetForNextWidget(hub_gui, 0.4, 1, 0.4, 1)
            end

            if lobby.in_progress then
                GuiColorSetForNextWidget(hub_gui, 1, 0.8, 0.2, 1)
            end

            local lobby_label = lobby.name .. " [" .. gm_name .. "]"
            if is_active then lobby_label = lobby_label .. " *" end

            if GuiButton(hub_gui, NewID("hub_lobby_" .. token_id), 0, 0, lobby_label) then
                if is_active then
                    local sid = steam.extra.parseUint64(steam_lid)
                    if sid and steam.extra.isSteamIDValid(sid) then
                        hub_pending_spectate = hub_spectator_mode
                        hub_source_lobby = true
                        steam_utils.Leave(lobby_code)
                        steam.matchmaking.joinLobby(sid, function(e) end)
                    else
                        hub_err(ts("$hub_err_lobby_gone"))
                    end
                else
                    hub_err(ts("$hub_err_lobby_not_active"))
                end
            end

            if is_owner_mod then
                if hub_ui_activate_busy[token_id] then
                    GuiColorSetForNextWidget(hub_gui, 0.5, 0.5, 0.5, 1)
                    GuiText(hub_gui, 2, 0, "...")
                else
                    if not is_active then
                        if GuiButton(hub_gui, NewID("hub_lobby_act_" .. token_id), 2, 0, ts("$hub_activate")) then
                            hub_ui_activate_busy[token_id] = true
                            local gm = FindGamemode(lobby.gamemode)
                            if gm == nil and #gamemodes > 0 then gm = gamemodes[1] end
                            if gm then
                                local settings = lobby.settings or {}
                                CreateLobby(1, 16, function(new_lid)
                                    steam_utils.TrySetLobbyData(new_lid, "System", "NoitaOnline")
                                    steam_utils.TrySetLobbyData(new_lid, "gamemode", gm.id)
                                    steam_utils.TrySetLobbyData(new_lid, "version", tostring(MP_VERSION))
                                    steam_utils.TrySetLobbyData(new_lid, "game_version", tostring(noita_version))
                                    steam_utils.TrySetLobbyData(new_lid, "game_version_hash", tostring(noita_version_hash))
                                    steam_utils.TrySetLobbyData(new_lid, "gamemode_version", tostring(gm.version))
                                    steam_utils.TrySetLobbyData(new_lid, "name", lobby.name)
                                    steam_utils.TrySetLobbyData(new_lid, "in_progress", "false")
                                    steam_utils.TrySetLobbyData(new_lid, "hub_token_id", token_id)
                                    steam_utils.TrySetLobbyData(new_lid, "hub_id", hub_state.id)
                                    for k, v in pairs(settings) do
                                        steam_utils.TrySetLobbyData(new_lid, "setting_" .. k, tostring(v))
                                    end
                                    hub_activate_lobby(token_id, new_lid)
                                    hub_ui_activate_busy[token_id] = nil
                                    hub_source_lobby = true
                                    lobby_code = new_lid
                                    lobby_gamemode = gm
                                    active_mode = gm
                                    get_preset_folder_name()
                                    generate_lobby_menus_list()
                                    gamemode_settings = {}
                                    for _, setting in ipairs(gm.settings or {}) do
                                        gamemode_settings[setting.id] = settings[setting.id] or setting.default
                                    end
                                    gm.enter(new_lid)
                                    menu_status = status.lobby
                                end)
                            else
                                hub_err(ts("$mp_no_gamemodes"))
                                hub_ui_activate_busy[token_id] = nil
                            end
                        end
                    end

                    if is_owner then
                        if GuiButton(hub_gui, NewID("hub_lobby_del_" .. token_id), 2, 0, ts("$hub_remove_lobby")) then
                            hub_delete_lobby(token_id)
                        end
                    end
                end

                if hub_ui_editing_lobby == token_id then
                    GuiColorSetForNextWidget(hub_gui, 1, 1, 0.2, 1)
                end
                if GuiButton(hub_gui, NewID("hub_lobby_edit_" .. token_id), 2, 0, ts("$hub_edit")) then
                    hub_ui_editing_lobby = hub_ui_editing_lobby == token_id and nil or token_id
                    if hub_ui_editing_lobby then
                        hub_ui_lobby_settings[token_id] = {}
                        local gm = FindGamemode(lobby.gamemode)
                        for k, setting in ipairs((gm and gm.settings) or {}) do
                            hub_ui_lobby_settings[token_id][setting.id] = lobby.settings and lobby.settings[setting.id] or setting.default
                        end
                    end
                end
            end

            GuiLayoutEnd(hub_gui)

            if hub_ui_editing_lobby == token_id then
                local gm = FindGamemode(lobby.gamemode)
                if gm and gm.settings then
                    GuiLayoutBeginVertical(hub_gui, 8, 0, true, 2, 0)
                    local lsettings = hub_ui_lobby_settings[token_id] or {}
                    local changed = false
                    for _, setting in ipairs(gm.settings) do
                        if setting.type == "bool" then
                            local val = lsettings[setting.id]
                            if type(val) == "string" then val = val == "true" end
                            if val == nil then val = setting.default end
                            local col = val and {0.4,1,0.4,1} or {1,0.4,0.4,1}
                            GuiColorSetForNextWidget(hub_gui, col[1], col[2], col[3], col[4])
                            if GuiButton(hub_gui, NewID("hub_ls_" .. token_id .. setting.id), 0, 0,
                                ts(setting.name) .. ": " .. (val and ts("$mp_setting_enabled") or ts("$mp_setting_disabled"))) then
                                lsettings[setting.id] = not val
                                changed = true
                            end
                        elseif setting.type == "enum" then
                            local val = lsettings[setting.id] or setting.default
                            local sel_name = val
                            local sel_idx = 1
                            for ki, opt in ipairs(setting.options) do
                                if opt[1] == val then sel_name = opt[2]; sel_idx = ki end
                            end
                            if GuiButton(hub_gui, NewID("hub_ls_" .. token_id .. setting.id), 0, 0,
                                ts(setting.name) .. ": " .. ts(sel_name)) then
                                sel_idx = (sel_idx % #setting.options) + 1
                                lsettings[setting.id] = setting.options[sel_idx][1]
                                changed = true
                            end
                        end
                    end
                    hub_ui_lobby_settings[token_id] = lsettings
                    if changed then
                        hub_update_lobby_state(token_id, { settings = lsettings })
                    end
                    GuiLayoutEnd(hub_gui)
                end
            end
        end

        GuiLayoutEnd(hub_gui)
    end, function()
        hub_ui_right_panel = nil
        hub_ui_left_panel  = nil
        if hub_source_lobby then
            hub_source_lobby = false
            menu_status = status.main_menu
        end
    end, "hub_main_window")

    if hub_ui_right_panel == "members" then
        DrawWindow(hub_gui, -5500, cx + (CENTER_W / 2) + (SIDE_W / 2) + PANEL_GAP, cy, SIDE_W, SIDE_H,
            ts("$hub_members"), true, function()
                GuiLayoutBeginVertical(hub_gui, 0, 0, true, 0, 0)
                GuiText(hub_gui, 2, 0, tostring(#(hub_state.online_members or {})) .. " " .. ts("$hub_online"))
                GuiText(hub_gui, 2, 0, "--------------------")

                local my_id = tostring(steam_utils.getSteamID())
                for _, sid_raw in ipairs(hub_state.online_members or {}) do
                    local sid = tostring(sid_raw)
                    local is_me = sid == my_id
                    local is_hub_owner = sid == tostring(hub_state.owner_steam_id)
                    local is_hub_mod = false
                    for _, mod_id in ipairs(hub_state.moderators or {}) do
                        if tostring(mod_id) == sid then is_hub_mod = true; break end
                    end

                    GuiLayoutBeginHorizontal(hub_gui, 0, 0, true, 0, 0)

                    local sid_num = steam.extra.parseUint64(sid)
                    GuiImage(hub_gui, NewID("hub_member_av"), 0, 0, steam_utils.getUserAvatar(sid_num), 1, 10 / 32, 10 / 32, 0)

                    local prefix = ""
                    if is_hub_owner then
                        prefix = "[O] "
                        GuiColorSetForNextWidget(hub_gui, 1, 0.85, 0.2, 1)
                    elseif is_hub_mod then
                        prefix = "[M] "
                        GuiColorSetForNextWidget(hub_gui, 0.6, 0.85, 1, 1)
                    end

                    if hub_ui_selected_member == sid then
                        GuiColorSetForNextWidget(hub_gui, 1, 1, 0.2, 1)
                    end

                    local name = steam_utils.getTranslatedPersonaName(sid_num)
                    if GuiButton(hub_gui, NewID("hub_member_" .. sid), 2, 0, prefix .. name) then
                        hub_ui_selected_member = hub_ui_selected_member == sid and nil or sid
                    end

                    GuiLayoutEnd(hub_gui)

                    if hub_ui_selected_member == sid and is_owner and not is_me and not is_hub_owner then
                        GuiLayoutBeginHorizontal(hub_gui, 8, 0, true, 0, 0)
                        if is_hub_mod then
                            if GuiButton(hub_gui, NewID("hub_mod_rem_" .. sid), 0, 0, ts("$hub_remove_mod")) then
                                hub_remove_moderator(sid)
                                hub_ui_selected_member = nil
                            end
                        else
                            if GuiButton(hub_gui, NewID("hub_mod_add_" .. sid), 0, 0, ts("$hub_make_mod")) then
                                hub_add_moderator(sid)
                                hub_ui_selected_member = nil
                            end
                        end
                        GuiLayoutEnd(hub_gui)
                    end
                end

                GuiLayoutEnd(hub_gui)
            end, function()
                hub_ui_right_panel = nil
                hub_ui_selected_member = nil
            end, "hub_members_window")
    end

    if hub_ui_right_panel == "feed" then
        DrawWindow(hub_gui, -5500, cx + (CENTER_W / 2) + (SIDE_W / 2) + PANEL_GAP, cy, SIDE_W, SIDE_H,
            ts("$hub_feed"), true, function()
                GuiLayoutBeginVertical(hub_gui, 0, 0, true, 0, 0)
                local feed = hub_feed_sorted()
                if #feed == 0 then
                    GuiColorSetForNextWidget(hub_gui, 0.5, 0.5, 0.5, 1)
                    GuiText(hub_gui, 2, 0, ts("$hub_feed_empty"))
                end
                for _, entry in ipairs(feed) do
                    GuiColorSetForNextWidget(hub_gui, 1, 0.85, 0.4, 1)
                    GuiText(hub_gui, 2, 0, format_feed_entry(entry))
                    GuiText(hub_gui, 2, -4, " ")
                end
                GuiLayoutEnd(hub_gui)
            end, function()
                hub_ui_right_panel = nil
            end, "hub_feed_window")
    end

    if hub_ui_left_panel == "settings" and is_owner then
        DrawWindow(hub_gui, -5500, cx - (CENTER_W / 2) - (SIDE_W / 2) - PANEL_GAP, cy, SIDE_W, SIDE_H,
            ts("$hub_settings"), true, function()
                GuiLayoutBeginVertical(hub_gui, 0, 0, true, 0, 0)

                local only_mods = hub_state.settings and hub_state.settings.only_mods_can_start or false
                local col = only_mods and {0.4, 1, 0.4, 1} or {1, 0.4, 0.4, 1}
                GuiColorSetForNextWidget(hub_gui, col[1], col[2], col[3], col[4])
                if GuiButton(hub_gui, NewID("hub_settings"), 0, 0,
                    ts("$hub_only_mods_start") .. ": " .. (only_mods and ts("$mp_setting_enabled") or ts("$mp_setting_disabled"))) then
                    hub_update_settings({ only_mods_can_start = not only_mods })
                end

                GuiText(hub_gui, 2, 0, " ")

                GuiColorSetForNextWidget(hub_gui, 1, 0.3, 0.3, 1)
                if GuiButton(hub_gui, NewID("hub_settings"), 0, 0, ts("$hub_delete_hub")) then
                    popup.create("hub_delete_confirm", ts("$hub_delete_hub"),
                        ts("$hub_delete_hub_confirm"),
                        {
                            {
                                text = ts("$hub_delete_hub_yes"),
                                callback = function()
                                    hub_delete(hub_state.id)
                                end
                            },
                            {
                                text = ts("$mp_close_popup"),
                                callback = function() end
                            }
                        }, -6000)
                end

                GuiLayoutEnd(hub_gui)
            end, function()
                hub_ui_left_panel = nil
            end, "hub_settings_window")
    end

    draw_err()

elseif menu_status == status.creating_hub then

    DrawWindow(hub_gui, -5000, cx, cy, 200, 100, ts("$hub_create"), true, function()
        GuiLayoutBeginVertical(hub_gui, 0, 0, true, 0, 0)

        GuiText(hub_gui, 0, 0, ts("$hub_name"))
        hub_ui_hub_name_input = GuiTextInput(hub_gui, NewID("hub_create_inp"), 0, 0, hub_ui_hub_name_input, 170, 40,
            "qwertyuiopasdfghjklzxcvbnmQWERTYUIOPASDFGHJKLZXCVBNM1234567890 !@#$%^&*()-_")
        local _, _, hov = GuiGetPreviousWidgetInfo(hub_gui)
        if hov then GameAddFlagRun("chat_bind_disabled") end

        if hub_ui_hub_err then
            GuiColorSetForNextWidget(hub_gui, 1, 0.3, 0.3, 1)
            GuiText(hub_gui, 0, 0, hub_ui_hub_err)
        end

        GuiLayoutBeginHorizontal(hub_gui, 0, 0, true, 0, 0)
        if GuiButton(hub_gui, NewID("hub_create_btn"), 0, 0, ts("$mp_create_lobby")) then
            if #hub_ui_hub_name_input > 0 then
                local my_id = steam_utils.getSteamID()
                local data, err = hub_create(hub_ui_hub_name_input, my_id)
                if err then
                    hub_ui_hub_err = ts("$hub_err_create") .. ": " .. tostring(err)
                else
                    hub_state = {
                        id             = data.hub_id,
                        name           = hub_ui_hub_name_input,
                        invite_code    = data.invite_code,
                        owner_steam_id = tostring(my_id),
                        moderators     = {},
                        lobbies        = {},
                        feed           = {},
                        settings       = { only_mods_can_start = false },
                        online_members = { tostring(my_id) }
                    }
                    hub_token = data.token
                    hub_ui_hub_name_input = ""
                    hub_ui_hub_err = nil
                    menu_status = status.hub
                end
            else
                hub_ui_hub_err = ts("$hub_err_no_name")
            end
        end
        if GuiButton(hub_gui, NewID("hub_create_btn"), 0, 0, ts("$hub_cancel")) then
            hub_ui_hub_name_input = ""
            hub_ui_hub_err = nil
            menu_status = status.main_menu
        end
        GuiLayoutEnd(hub_gui)

        GuiLayoutEnd(hub_gui)
    end, function()
        hub_ui_hub_name_input = ""
        hub_ui_hub_err = nil
        menu_status = status.main_menu
    end, "hub_create_window")

elseif menu_status == status.joining_hub then

    DrawWindow(hub_gui, -5000, cx, cy, 200, 100, ts("$hub_join"), true, function()
        GuiLayoutBeginVertical(hub_gui, 0, 0, true, 0, 0)

        GuiText(hub_gui, 0, 0, ts("$hub_invite_code"))
        hub_ui_join_code_input = GuiTextInput(hub_gui, NewID("hub_join_inp"), 0, 0, hub_ui_join_code_input, 170, 15,
            "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyz")
        local _, _, hov = GuiGetPreviousWidgetInfo(hub_gui)
        if hov then GameAddFlagRun("chat_bind_disabled") end

        GuiLayoutBeginHorizontal(hub_gui, 0, 0, true, 0, 0)
        if GuiButton(hub_gui, NewID("hub_join_paste"), 0, 0, ts("$mp_paste_code")) then
            local clip = steam.utils.getClipboard()
            if clip and clip ~= "" then hub_ui_join_code_input = clip end
        end
        GuiLayoutEnd(hub_gui)

        if hub_ui_hub_err then
            GuiColorSetForNextWidget(hub_gui, 1, 0.3, 0.3, 1)
            GuiText(hub_gui, 0, 0, hub_ui_hub_err)
        end

        GuiLayoutBeginHorizontal(hub_gui, 0, 0, true, 0, 0)
        if GuiButton(hub_gui, NewID("hub_join_btn"), 0, 0, ts("$mp_join_lobby")) then
            if #hub_ui_join_code_input > 0 then
                local my_id = steam_utils.getSteamID()
                local data, err = hub_join_by_code(hub_ui_join_code_input, my_id)
                if err then
                    hub_ui_hub_err = ts("$hub_err_join") .. ": " .. tostring(err)
                else
                    hub_state = {
                        id             = data.hub_id,
                        name           = data.name,
                        invite_code    = data.invite_code,
                        owner_steam_id = data.owner_steam_id,
                        moderators     = data.moderators or {},
                        lobbies        = data.lobbies or {},
                        feed           = data.feed or {},
                        settings       = data.settings or {},
                        online_members = data.online_members or {}
                    }
                    hub_token = data.token
                    hub_ui_join_code_input = ""
                    hub_ui_hub_err = nil
                    menu_status = status.hub
                end
            else
                hub_ui_hub_err = ts("$hub_err_no_code")
            end
        end
        if GuiButton(hub_gui, NewID("hub_join_btn"), 0, 0, ts("$hub_cancel")) then
            hub_ui_join_code_input = ""
            hub_ui_hub_err = nil
            menu_status = status.main_menu
        end
        GuiLayoutEnd(hub_gui)

        GuiLayoutEnd(hub_gui)
    end, function()
        hub_ui_join_code_input = ""
        hub_ui_hub_err = nil
        menu_status = status.main_menu
    end, "hub_join_window")

end
