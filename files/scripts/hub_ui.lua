hub_ui_new_lobby_name     = hub_ui_new_lobby_name or ""
hub_ui_new_lobby_gamemode = hub_ui_new_lobby_gamemode or 1
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
hub_ui_busy            = hub_ui_busy or false
hub_ui_busy_frame      = hub_ui_busy_frame or 0
if hub_ui_busy and (GameGetFrameNum() - hub_ui_busy_frame) > 600 then
    hub_ui_busy = false
end
hub_pending_spectate      = hub_pending_spectate or false
hub_ui_show_code          = hub_ui_show_code or false

local sw, sh = GuiGetScreenDimensions(menu_gui)
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
    GuiColorSetForNextWidget(menu_gui, 1, 0.3, 0.3, 1)
    GuiZSetForNextWidget(menu_gui, -7000)
    GuiText(menu_gui, cx - 80, sh - 30, hub_ui_hub_err)
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

local hub_showing = hub_state ~= nil and (menu_status == status.hub or hub_source_lobby == true) and not IsPaused()

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

    DrawWindow(menu_gui, -5000, cx, cy, CENTER_W, CENTER_H, function()
        local code = hub_state.invite_code or "?"
        local display_code = hub_ui_show_code and code or censorString(code)
        GuiColorSetForNextWidget(menu_gui, 0, 0, 0, 0.3)
        GuiText(menu_gui, 0, 0, hub_state.name .. "  [" .. display_code .. "]")

        GuiColorSetForNextWidget(menu_gui, 74/255, 62/255, 46/255, 0.5)
        if GuiImageButton(menu_gui, NewID("hub_title"), 1, 1.5, "", hub_ui_show_code and "mods/evaisa.mp/files/gfx/ui/hide.png" or "mods/evaisa.mp/files/gfx/ui/show.png") then
            hub_ui_show_code = not hub_ui_show_code
            GamePlaySound("data/audio/Desktop/ui.bank", "ui/button_click", 0, 0)
        end

        GuiColorSetForNextWidget(menu_gui, 74/255, 62/255, 46/255, 0.5)
        if GuiImageButton(menu_gui, NewID("hub_title"), 6, 1.5, "", "mods/evaisa.mp/files/gfx/ui/copy.png") then
            steam.utils.setClipboard(code)
            GamePlaySound("data/audio/Desktop/ui.bank", "ui/button_click", 0, 0)
        end
    end, true, function()
        GuiLayoutBeginVertical(menu_gui, 0, 0, true, 0, 0)
        local members_btn = hub_ui_right_panel == "members" and ts("$hub_members") .. " <" or ts("$hub_members") .. " >"
        local mtw = GuiGetTextDimensions(menu_gui, members_btn)
        if GuiButton(menu_gui, NewID("hub_btn"), CENTER_W - mtw, 0, members_btn) then
            if hub_ui_right_panel == "members" then
                hub_ui_right_panel = nil
            else
                hub_ui_right_panel = "members"
            end
        end
        local feed_btn = hub_ui_right_panel == "feed" and ts("$hub_feed") .. " <" or ts("$hub_feed") .. " >"
        local ftw = GuiGetTextDimensions(menu_gui, feed_btn)
        if GuiButton(menu_gui, NewID("hub_btn"), CENTER_W - ftw, 0, feed_btn) then
            if hub_ui_right_panel == "feed" then
                hub_ui_right_panel = nil
            else
                hub_ui_right_panel = "feed"
            end
        end
        GuiLayoutEnd(menu_gui)

        GuiLayoutBeginVertical(menu_gui, 0, 0, true, 0, 0)

        if GuiButton(menu_gui, NewID("hub_btn"), 0, 0, ts("$hub_leave")) then
            hub_leave()
        end

        if is_owner then
            local settings_btn = hub_ui_left_panel == "settings" and "< " .. ts("$hub_settings") or "> " .. ts("$hub_settings")
            if GuiButton(menu_gui, NewID("hub_btn"), 0, 0, settings_btn) then
                if hub_ui_left_panel == "settings" then
                    hub_ui_left_panel = nil
                else
                    hub_ui_left_panel = "settings"
                    hub_ui_new_lobby_name = ""
                end
            end
        end

        GuiText(menu_gui, 2, 0, " ")

        if is_owner then
            if GuiButton(menu_gui, NewID("hub_btn"), 0, 0, ts("$hub_create_lobby")) then
                hub_creating_lobby = true
                menu_status = status.creating_lobby
            end
        end

        if GuiButton(menu_gui, NewID("hub_btn"), 0, 0, ts("$hub_refresh")) then
            hub_refresh()
        end

        if GuiButton(menu_gui, NewID("hub_btn"), 0, 0, hub_spectator_mode and ts("$mp_spectator_mode_enabled") or ts("$mp_spectator_mode_disabled")) then
            hub_spectator_mode = not hub_spectator_mode
        end

        GuiText(menu_gui, 2, 0, "--------------------")

        if #lobby_list == 0 then
            GuiColorSetForNextWidget(menu_gui, 0.5, 0.5, 0.5, 1)
            GuiText(menu_gui, 2, 0, ts("$hub_no_lobbies"))
        end

        for _, lobby in ipairs(lobby_list) do
            local token_id  = lobby.token_id
            local steam_lid = lobby.steam_lobby_id
            local is_active = steam_lid and steam_lid ~= "" and steam_lid ~= "null"
            local gm_name   = lobby_gamemode_name(lobby.gamemode)

            GuiLayoutBeginHorizontal(menu_gui, 0, 0, true, 0, 0)

            if is_active then
                GuiColorSetForNextWidget(menu_gui, 0.4, 1, 0.4, 1)
            end

            if lobby.in_progress then
                GuiColorSetForNextWidget(menu_gui, 1, 0.8, 0.2, 1)
            end

            local lobby_label = lobby.name .. " [" .. gm_name .. "]"
            if is_active then lobby_label = lobby_label .. " *" end

            if GuiButton(menu_gui, NewID("hub_lobby_" .. token_id), 0, 0, lobby_label) then
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
                    GuiColorSetForNextWidget(menu_gui, 0.5, 0.5, 0.5, 1)
                    GuiText(menu_gui, 2, 0, "...")
                else
                    if not is_active then
                        if GuiButton(menu_gui, NewID("hub_lobby_act_" .. token_id), 2, 0, ts("$hub_activate")) then
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
                        if GuiButton(menu_gui, NewID("hub_lobby_del_" .. token_id), 2, 0, ts("$hub_remove_lobby")) then
                            hub_delete_lobby(token_id)
                        end
                    end
                end

                if hub_ui_editing_lobby == token_id then
                    GuiColorSetForNextWidget(menu_gui, 1, 1, 0.2, 1)
                end
                if GuiButton(menu_gui, NewID("hub_lobby_edit_" .. token_id), 2, 0, ts("$hub_edit")) then
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

            GuiLayoutEnd(menu_gui)

            if hub_ui_editing_lobby == token_id then
                local gm = FindGamemode(lobby.gamemode)
                if gm and gm.settings then
                    GuiLayoutBeginVertical(menu_gui, 8, 0, true, 2, 0)
                    local lsettings = hub_ui_lobby_settings[token_id] or {}
                    local changed = false
                    for _, setting in ipairs(gm.settings) do
                        if setting.type == "bool" then
                            local val = lsettings[setting.id]
                            if type(val) == "string" then val = val == "true" end
                            if val == nil then val = setting.default end
                            local col = val and {0.4,1,0.4,1} or {1,0.4,0.4,1}
                            GuiColorSetForNextWidget(menu_gui, col[1], col[2], col[3], col[4])
                            if GuiButton(menu_gui, NewID("hub_ls_" .. token_id .. setting.id), 0, 0,
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
                            if GuiButton(menu_gui, NewID("hub_ls_" .. token_id .. setting.id), 0, 0,
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
                    GuiLayoutEnd(menu_gui)
                end
            end
        end

        GuiLayoutEnd(menu_gui)
    end, function()
        hub_ui_right_panel = nil
        hub_ui_left_panel  = nil
        if hub_source_lobby then
            hub_source_lobby = false
            menu_status = status.main_menu
        end
    end, "hub_main_window")

    if hub_ui_right_panel == "members" then
        DrawWindow(menu_gui, -5500, cx + (CENTER_W / 2) + (SIDE_W / 2) + PANEL_GAP, cy, SIDE_W, SIDE_H,
            ts("$hub_members"), true, function()
                GuiLayoutBeginVertical(menu_gui, 0, 0, true, 0, 0)
                GuiText(menu_gui, 2, 0, tostring(#(hub_state.online_members or {})) .. " " .. ts("$hub_online"))
                GuiText(menu_gui, 2, 0, "--------------------")

                local my_id = tostring(steam_utils.getSteamID())
                for _, sid_raw in ipairs(hub_state.online_members or {}) do
                    local sid = tostring(sid_raw)
                    local is_me = sid == my_id
                    local is_hub_owner = sid == tostring(hub_state.owner_steam_id)
                    local is_hub_mod = false
                    for _, mod_id in ipairs(hub_state.moderators or {}) do
                        if tostring(mod_id) == sid then is_hub_mod = true; break end
                    end

                    GuiLayoutBeginHorizontal(menu_gui, 0, 0, true, 0, 0)

                    local sid_num = steam.extra.parseUint64(sid)
                    GuiImage(menu_gui, NewID("hub_member_av"), 0, 0, steam_utils.getUserAvatar(sid_num), 1, 10 / 32, 10 / 32, 0)

                    local prefix = ""
                    if is_hub_owner then
                        prefix = "[O] "
                        GuiColorSetForNextWidget(menu_gui, 1, 0.85, 0.2, 1)
                    elseif is_hub_mod then
                        prefix = "[M] "
                        GuiColorSetForNextWidget(menu_gui, 0.6, 0.85, 1, 1)
                    end

                    if hub_ui_selected_member == sid then
                        GuiColorSetForNextWidget(menu_gui, 1, 1, 0.2, 1)
                    end

                    local name = steam_utils.getTranslatedPersonaName(sid_num)
                    if GuiButton(menu_gui, NewID("hub_member_" .. sid), 2, 0, prefix .. name) then
                        hub_ui_selected_member = hub_ui_selected_member == sid and nil or sid
                    end

                    GuiLayoutEnd(menu_gui)

                    if hub_ui_selected_member == sid and is_owner and not is_me and not is_hub_owner then
                        GuiLayoutBeginHorizontal(menu_gui, 8, 0, true, 0, 0)
                        if is_hub_mod then
                            if GuiButton(menu_gui, NewID("hub_mod_rem_" .. sid), 0, 0, ts("$hub_remove_mod")) then
                                hub_remove_moderator(sid)
                                hub_ui_selected_member = nil
                            end
                        else
                            if GuiButton(menu_gui, NewID("hub_mod_add_" .. sid), 0, 0, ts("$hub_make_mod")) then
                                hub_add_moderator(sid)
                                hub_ui_selected_member = nil
                            end
                        end
                        GuiLayoutEnd(menu_gui)
                    end
                end

                GuiLayoutEnd(menu_gui)
            end, function()
                hub_ui_right_panel = nil
                hub_ui_selected_member = nil
            end, "hub_members_window")
    end

    if hub_ui_right_panel == "feed" then
        DrawWindow(menu_gui, -5500, cx + (CENTER_W / 2) + (SIDE_W / 2) + PANEL_GAP, cy, SIDE_W, SIDE_H,
            ts("$hub_feed"), true, function()
                GuiLayoutBeginVertical(menu_gui, 0, 0, true, 0, 0)
                local feed = hub_feed_sorted()
                if #feed == 0 then
                    GuiColorSetForNextWidget(menu_gui, 0.5, 0.5, 0.5, 1)
                    GuiText(menu_gui, 2, 0, ts("$hub_feed_empty"))
                end
                for _, entry in ipairs(feed) do
                    GuiColorSetForNextWidget(menu_gui, 1, 0.85, 0.4, 1)
                    GuiText(menu_gui, 2, 0, format_feed_entry(entry))
                    GuiText(menu_gui, 2, -4, " ")
                end
                GuiLayoutEnd(menu_gui)
            end, function()
                hub_ui_right_panel = nil
            end, "hub_feed_window")
    end

    if hub_ui_left_panel == "settings" and is_owner then
        DrawWindow(menu_gui, -5500, cx - (CENTER_W / 2) - (SIDE_W / 2) - PANEL_GAP, cy, SIDE_W, SIDE_H,
            ts("$hub_settings"), true, function()
                GuiLayoutBeginVertical(menu_gui, 0, 0, true, 0, 0)

                local box_w = SIDE_W - 4
                local only_mods = hub_state.settings and hub_state.settings.only_mods_can_start or false
                local val_r, val_g, val_b = only_mods and 0.4 or 1, only_mods and 1 or 0.4, 0.4
                local val_text = only_mods and ts("$mp_setting_enabled") or ts("$mp_setting_disabled")
                local label = ts("$hub_only_mods_start") .. ": "
                local lw, lh = GuiGetTextDimensions(menu_gui, label .. val_text)
                Gui9Piece(menu_gui, function() return NewID("hub_settings") end, 0, 0, box_w, lh + 2, 0.1, -5600, "mods/evaisa.mp/files/gfx/ui/9piece_white.xml", 3)
                if GuiTextButton(menu_gui, function() return NewID("hub_settings") end, 4, 2, {
                    { text = label, color = {1, 1, 1, 1} },
                    { text = val_text, color = {val_r, val_g, val_b, 1} }
                }, -5600, 1, val_r, val_g, val_b, 1, box_w) then
                    hub_update_settings({ only_mods_can_start = not only_mods })
                end

                GuiText(menu_gui, 2, 0, " ")

                GuiColorSetForNextWidget(menu_gui, 1, 0.3, 0.3, 1)
                if GuiButton(menu_gui, NewID("hub_settings"), 0, 0, ts("$hub_delete_hub")) then
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

                GuiLayoutEnd(menu_gui)
            end, function()
                hub_ui_left_panel = nil
            end, "hub_settings_window")
    end

    draw_err()

end
