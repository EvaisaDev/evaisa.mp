dofile_once("data/scripts/lib/utilities.lua")

pretty = require("pretty_print")

menu_gui = menu_gui or GuiCreate()

GuiStartFrame(menu_gui)

local text_input = dofile("mods/evaisa.mp/files/scripts/text_input.lua")

status = {
	main_menu = 1,
	lobby = 2,
	creating_lobby = 3,
	joining_lobby = 4,
	disconnected = 5,
	hub = 6,
	creating_hub = 7,
	joining_hub = 8,
}

GuiOptionsAdd( menu_gui, GUI_OPTION.NoPositionTween )

local lobby_types = {
	GameTextGetTranslatedOrNot("$mp_public"),
	GameTextGetTranslatedOrNot("$mp_private"),
	GameTextGetTranslatedOrNot("$mp_friends_only"),
}

local function split_message(msg, max_width)
	local words = {}
	local index = 1

	-- split string by \n
	for line in string.gmatch(msg, "[^\n]+") do
		for word in string.gmatch(line, "%S+") do

			-- split word into chunks of 200 pixels or less
	
			local width, height = GuiGetTextDimensions(menu_gui, word)
	
			if (width > max_width) then
				local chunks = {}
				local chunk = ""
				for i = 1, #word do
					local char = word:sub(i, i)
					local char_width, char_height = GuiGetTextDimensions(menu_gui, chunk .. char)
					if (char_width <= max_width) then
						chunk = chunk .. char
					else
						table.insert(chunks, chunk)
						chunk = char
					end
				end
				table.insert(chunks, chunk)
	
				for i, chunk in ipairs(chunks) do
					table.insert(words, chunk)
				end
			else
				table.insert(words, word)
			end
	
	
			index = index + 1
		end
		table.insert(words, "\n")
	end




	local chunks = {}
	local chunk = ""
	local last_word
	for i, word in ipairs(words) do
		local width, height = GuiGetTextDimensions(chat_gui, chunk .. " " .. word)

		if width <= max_width then
			if chunk == "" then
				chunk = word
			else
				if(last_word ~= "\n")then
					chunk = chunk .. " " .. word
				else
					chunk = chunk .. word
				end
			end
		else
			table.insert(chunks, chunk)
			chunk = word
		end
		last_word = word
	end
	table.insert(chunks, chunk)

	return chunks
end

local function get_split_string(str, max_width)
	local chunks = split_message(str, max_width)

	-- combine with \n
	local result = table.concat(chunks, "\n")


	return result, #chunks
end

presets = presets or {}
reserved_preset_names = reserved_preset_names or {}

function get_preset_folder_name()
	presets_folder_name = os.getenv('APPDATA'):gsub("\\Roaming", "") .. "\\LocalLow\\Nolla_Games_Noita\\save00\\evaisa.mp_presets"
	gamemode_preset_folder_name = presets_folder_name .. "\\"..active_mode.id

	return presets_folder_name, gamemode_preset_folder_name
end


gui_closed = gui_closed or false
invite_menu_open = invite_menu_open or false
mod_list_open = mod_list_open or false
lobby_settings_open = lobby_settings_open or false
lobby_presets_open = lobby_presets_open or false
was_lobby_presets_open = was_lobby_presets_open or false
settings_changed = settings_changed or false

lobby_filter_show_full = (lobby_filter_show_full == nil) and true or lobby_filter_show_full
lobby_filter_show_friends = (lobby_filter_show_friends == nil) and true or lobby_filter_show_friends
lobby_filter_show_public = (lobby_filter_show_public == nil) and true or lobby_filter_show_public
lobby_filter_distance = lobby_filter_distance or "worldwide"
lobby_filter_max_players = lobby_filter_max_players or 0

local is_in_lobby = lobby_code ~= nil and true or false

selected_player = selected_player or nil

menu_status = menu_status or status.main_menu

show_lobby_code = show_lobby_code or false

if(is_in_lobby)then
	menu_status = status.lobby
end

active_lobby_menu_right = active_lobby_menu_right or nil
active_lobby_menu_left = active_lobby_menu_left or nil

active_mode = active_mode or nil

local screen_width, screen_height = GuiGetScreenDimensions( menu_gui );

-- replace each letter in string with *
function censorString(input)
	return string.rep("X", #input)
end


function CreateLobby(type, max_players, callback)
	--print("yeah?")
	steam.matchmaking.createLobby(type, max_players, function(e) 
		--print("did this run?")
		if(tostring(e.result) == "1")then
			callback(e.lobby)
		else
			mp_log:print("CreateLobby failed: " .. tostring(e.result))
		end
	end )
end


local function GenerateDefaultPreset()
	local default_name = GameTextGetTranslatedOrNot("$mp_default_preset_name")
	local preset_data = {version = MP_PRESET_VERSION, settings = {}}
	for k, v in ipairs(active_mode.settings)do
		preset_data.settings[v.id] = v.default
	end
	reserved_preset_names[default_name] = true
	table.insert(presets, 1, {name=default_name, data=preset_data, default=true})
end

local function AddGamemodePresets()
	if(active_mode.default_presets ~= nil)then
		for name, data in pairs(active_mode.default_presets)do
			reserved_preset_names[name] = true
			table.insert(presets, 1, {name=name, data=data, default=true})
		end
	end

	if(active_mode.preset_registry ~= nil)then
		local data_table = active_mode.preset_registry()
		for _, data in ipairs(data_table)do
			data.default = true
			table.insert(presets, 1, data)
		end
	end
end

local function RefreshPresets()
	-- create folder if doesn't exist
	if not os.rename(presets_folder_name, presets_folder_name) then
		os.execute("mkdir \"" .. presets_folder_name .. "\"")
	end
	
	if not os.rename(gamemode_preset_folder_name, gamemode_preset_folder_name) then
		os.execute("mkdir \"" .. gamemode_preset_folder_name .. "\"")
	end

	presets = {}

	-- loop through files in folder, without luafilesystem
	local pfile = io.popen([[dir "]] .. gamemode_preset_folder_name .. [[" /b]])
	for filename in pfile:lines() do

		-- if filename ends in .mp_preset
		if(filename:sub(-10) == ".mp_preset")then
			local preset_data = {}
			local file = io.open(gamemode_preset_folder_name .. "\\" .. filename, "r")
			if(file ~= nil)then
				local data = file:read("*all")
				file:close()
				filename = filename:gsub(".mp_preset", "")
				local valid, preset_data = pcall(bitser.loads, data)
				if(valid and preset_data ~= nil)then
					table.insert(presets, {name = filename, extension = ".mp_preset", data = preset_data})
				else
					table.insert(presets, {name = filename, extension = ".mp_preset",	corrupt = true, data = {
						version = MP_PRESET_VERSION,
						settings = {}
					}})
				end
			end
		elseif(filename:sub(-5) == ".json")then
			local preset_data = {}
			local file = io.open(gamemode_preset_folder_name .. "\\" .. filename, "r")
			if(file ~= nil)then
				local data = file:read("*all")
				file:close()
				filename = filename:gsub(".json", "")
				local valid, preset_data = pcall(json.parse, data)
				if(valid and preset_data ~= nil)then
					table.insert(presets, {name = filename, extension = ".json", data = preset_data})
				else
					table.insert(presets, {name = filename, extension = ".json", corrupt = true, data = {
						version = MP_PRESET_VERSION,
						settings = {}
					}})
				end
			end
		end
	end

	AddGamemodePresets()
	GenerateDefaultPreset()
end

local function SavePreset(name)
	if(not reserved_preset_names[name])then

		local settings_data = {version = MP_PRESET_VERSION, settings = gamemode_settings}

		if(active_mode.save_preset)then
			settings_data = active_mode.save_preset(lobby_code, settings_data)
		end

		local serialized_data = nil
		local extension = ""
		if(ModSettingGet("evaisa.mp.presets_as_json"))then
			serialized_data = json.stringify(settings_data)
			extension = ".json"
		else
			serialized_data = bitser.dumps(settings_data)
			extension = ".mp_preset"
		end
		--print(json.stringify(settings_data))
		local file = io.open(gamemode_preset_folder_name .. "\\" .. name .. extension, "w")
		if(file ~= nil)then
			file:write(serialized_data)
			file:close()
		end
	else
		print("Preset name is reserved")
		GamePrint("Preset name is reserved")
	end
end

local function RemovePreset(name, extension)
	if(name ~= " " and name ~= "_" and #name > 0)then
		os.remove(gamemode_preset_folder_name .. "\\" .. name .. extension)
	end
end


local function GetMenuSettings(location)
	if(location == "center")then

		width = 220


		local x = screen_width / 2


		return width, x
	elseif(location == "left")then
		-- 10 pixels to the left of center
		-- if right is closed, but left is open, 300 pixels wide
		local width = 188

		local center_width, center_x = GetMenuSettings("center")
		local x = center_x - (center_width / 2) - (width / 2) - 10
		return width, x
	elseif(location == "right")then
		-- 10 pixels to the right of center
		-- if left is closed, but right is open, 300 pixels wide
		local width = 188

		local center_width, center_x = GetMenuSettings("center")
		local x = center_x + (center_width / 2) + (width / 2) + 10
		return width, x
	end

end


initial_refreshes = initial_refreshes or 10

if(initial_refreshes > 0)then
	initial_refreshes = initial_refreshes - 1
	if(initial_refreshes == 0)then
		refreshLobbies()
	end
end

local default_lobby_menus = {
	{
		id = "lobby_settings",
		name = "$mp_lobby_settings",
		button_text = "$mp_lobby_settings",
		menu_left = true,
		draw = function(lobby, gui, new_id)
			local owner = steam.matchmaking.getLobbyOwner(lobby_code)

			local internal_types = { "Public", "Private", "FriendsOnly"}
			local internal_type_map = { Public = 1, Private = 2, FriendsOnly = 3 }


			edit_lobby_type = internal_type_map[steam_utils.GetLobbyData("LobbyType")]

			local true_max = 250

			local default_max_players = 8

			edit_lobby_max_players = steam_utils.getSteamID() and (edit_lobby_max_players or steam.matchmaking.getLobbyMemberLimit(lobby_code)) or steam.matchmaking.getLobbyMemberLimit(lobby_code)

			edit_lobby_name = owner == steam_utils.getSteamID() and (edit_lobby_name or steam_utils.GetLobbyData("name"))  or steam_utils.GetLobbyData("name")

			edit_lobby_seed = owner == steam_utils.getSteamID() and (edit_lobby_seed or steam_utils.GetLobbyData("seed")) or steam_utils.GetLobbyData("seed")
		
			local current_y = 0
			local box_w = 180

			-- Lobby Type Field
			local lobby_type_string = get_split_string(GameTextGetTranslatedOrNot("$mp_lobby_type")..": "..lobby_types[edit_lobby_type], 150)

			local chunks = select(2, lobby_type_string:gsub('\n', '\n'))

			local last_w, last_h = GuiGetTextDimensions(menu_gui, lobby_type_string)
			local box_h = last_h + (chunks <= 1 and 2 or 0)
			
			Gui9Piece(menu_gui, function() return NewID("EditLobby") end, 0, 0, box_w, box_h, 0.1, -5600, "mods/evaisa.mp/files/gfx/ui/9piece_white.xml", 3)

			if(GuiTextButton(menu_gui, function() return NewID("EditLobby") end, 4, 2, lobby_type_string, -5600, 1))then
				edit_lobby_type = edit_lobby_type + 1
				if(edit_lobby_type > #lobby_types and owner == steam_utils.getSteamID())then
					edit_lobby_type = 1
				end
				settings_changed = true
			end

			current_y = current_y + box_h + 2

			-- Lobby name field
			local lobby_name_string = GameTextGetTranslatedOrNot("$mp_lobby_name")..": "
			local last_w, last_h = GuiGetTextDimensions(menu_gui, lobby_name_string)
			local box_h = last_h + 18
			Gui9Piece(menu_gui, function() return NewID("EditLobby") end, 0, current_y, box_w, box_h, 0.1, -5600, "mods/evaisa.mp/files/gfx/ui/9piece_white.xml", 3)
			GuiText(menu_gui, 4, current_y + 2, lobby_name_string)
			name_change_frame = name_change_frame or nil
			local lobby_name_value = GuiTextInput(menu_gui, NewID("EditLobby"), 4, current_y + last_h + 2, edit_lobby_name, 156, 25, "qwertyuiopasdfghjklzxcvbnm1234567890QWERTYUIOPASDFGHJKLZXCVBNM!@#$%^&*()_' ")
			local _, _, hover = GuiGetPreviousWidgetInfo(menu_gui)
			
			if(hover)then
				GameAddFlagRun("chat_bind_disabled")
			end
			if(lobby_name_value ~= edit_lobby_name and owner == steam_utils.getSteamID())then
				edit_lobby_name = lobby_name_value
				name_change_frame = GameGetFrameNum()
			end
		
			if(name_change_frame and GameGetFrameNum() - name_change_frame > 30)then
				settings_changed = true
				name_change_frame = nil
			end

			current_y = current_y + box_h + 2

			-- lobby max players field
			local max_player_string = GameTextGetTranslatedOrNot("$mp_max_players")..": "
			local last_w, last_h = GuiGetTextDimensions(menu_gui, max_player_string)
			local box_h = last_h + 16
			Gui9Piece(menu_gui, function() return NewID("EditLobby") end, 0, current_y, box_w, box_h, 0.1, -5600, "mods/evaisa.mp/files/gfx/ui/9piece_white.xml", 3)
			GuiText(menu_gui, 4, current_y + 2, max_player_string)
			max_player_change_frame = max_player_change_frame or nil
			local slider_value = GuiSlider(menu_gui, NewID("EditLobby"), 2, current_y + last_h + 2, "", edit_lobby_max_players, 2, true_max, default_max_players, 1, "        ", 146)
			
			GuiColorSetForNextWidget(menu_gui, 1, 1, 1, 0.7)
			local value_text = tostring(math.floor(slider_value))
			GuiText(menu_gui, 153, current_y + last_h + 1, value_text)
			
			if(slider_value ~= edit_lobby_max_players and owner == steam_utils.getSteamID())then
				edit_lobby_max_players = slider_value
				max_player_change_frame = GameGetFrameNum()
			end

			if(max_player_change_frame and GameGetFrameNum() - max_player_change_frame > 30)then
				settings_changed = true
				max_player_change_frame = nil
			end

			current_y = current_y + box_h + 2

			-- world seed field
			local seed_string = GameTextGetTranslatedOrNot("$mp_world_seed")..": "
			local last_w, last_h = GuiGetTextDimensions(menu_gui, seed_string)
			local box_h = last_h + 18
			Gui9Piece(menu_gui, function() return NewID("EditLobby") end, 0, current_y, box_w, box_h, 0.1, -5600, "mods/evaisa.mp/files/gfx/ui/9piece_white.xml", 3)
			GuiText(menu_gui, 4, current_y + 2, seed_string)
			seed_change_frame = seed_change_frame or nil
			local edit_lobby_seed_value = GuiTextInput(menu_gui, NewID("EditLobby"), 4, current_y + last_h + 2, edit_lobby_seed, 156, 25, "1234567890")
			local _, _, hover = GuiGetPreviousWidgetInfo(menu_gui)
			if(hover)then
				GameAddFlagRun("chat_bind_disabled")
			end
			if(edit_lobby_seed_value ~= edit_lobby_seed and owner == steam_utils.getSteamID())then
				edit_lobby_seed = edit_lobby_seed_value
				seed_change_frame = GameGetFrameNum()
			end
		
			if(seed_change_frame and GameGetFrameNum() - seed_change_frame > 30)then
				settings_changed = true
				seed_change_frame = nil
			end

			current_y = current_y + box_h + 2

			for k, setting in ipairs(active_mode.settings or {})do
				if(owner ~= steam_utils.getSteamID())then
					gamemode_settings[setting.id] = steam.matchmaking.getLobbyData(lobby_code, "setting_"..setting.id)
				end
		
				if(gamemode_settings[setting.id] == nil)then
					gamemode_settings[setting.id] = setting.default
					print("Setting "..setting.id.." to default: "..tostring(setting.default))
					--settings_changed = true
					--GlobalsSetValue("setting_next_"..setting.id, tostring(setting.default))
				else
					
					if(setting.type == "bool" and type(gamemode_settings[setting.id]) == "string")then
						if(gamemode_settings[setting.id] == "true")then
							gamemode_settings[setting.id] = true
						else
							gamemode_settings[setting.id] = false
						end
					elseif(setting.type == "slider" and type(gamemode_settings[setting.id]) == "string")then
						gamemode_settings[setting.id] = tonumber(gamemode_settings[setting.id])
					end
				end
		
				if(gamemode_settings[setting.id] ~= nil)then
					local setting_next = GlobalsGetValue("setting_next_"..setting.id)
					if(setting_next ~= nil)then
						if(setting_next ~= tostring(gamemode_settings[setting.id]))then
							GlobalsSetValue("setting_next_"..setting.id, tostring(gamemode_settings[setting.id]))
						end
					end
				end

				if(setting.require == nil or setting.require(setting))then
					--print(setting.id.."; "..tostring(setting.require).."; "..(setting.require and tostring(setting.require(setting)) or "nil"))
					if(setting.type == "enum")then
						local selected_name = ""
						local selected_index = nil
		
						local selected_value = gamemode_settings[setting.id]
						--print("Selected value: "..tostring(selected_value))
						if(selected_value == nil)then
							selected_value = setting.default
							gamemode_settings[setting.id] = setting.default
							settings_changed = true
						end
						
						for k, v in ipairs(setting.options)do
							if(v[1] == selected_value)then
								selected_name = v[2]
								selected_index = k
							end
						end
		
						-- if selected index is nil, reset to default
						if(selected_index == nil)then
							for k, v in ipairs(setting.options)do
								if(v[1] == setting.default)then
									selected_name = v[2]
									selected_index = k
									settings_changed = true
									gamemode_settings[setting.id] = setting.default
								end
							end
						end

						local enum_string = get_split_string(GameTextGetTranslatedOrNot(setting.name or "")..": "..GameTextGetTranslatedOrNot(selected_name or ""), 150)
						local chunks = select(2, enum_string:gsub('\n', '\n'))
						local last_w, last_h = GuiGetTextDimensions(menu_gui, enum_string)
						local box_h = last_h + (chunks <= 1 and 2 or 0)

						Gui9Piece(menu_gui, function() return NewID("EditLobby") end, 0, current_y, box_w, box_h, 0.1, -5600, "mods/evaisa.mp/files/gfx/ui/9piece_white.xml", 3)
						if(setting.options[selected_index][3] ~= nil)then
							local info = setting.options[selected_index][3]
							local info_name = "???"
							local info_desc = ""
							if(type(info) == "function")then
								info_name, info_desc = info()
							elseif(type(info) == "table")then
								info_name, info_desc = info[1], info[2]
							else
								info_name = info
							end
		
							if(info_name ~= nil)then
								GuiColorSetForNextWidget( menu_gui, 1, 0.4, 0.4, 1.0 )
								GuiText(menu_gui, 0, 0, "[?]")
								GuiTooltip(menu_gui, GameTextGetTranslatedOrNot(info_name or ""), GameTextGetTranslatedOrNot(info_desc or ""))
							end
						end
						
						if(GuiTextButton(menu_gui, function() return NewID("EditLobby") end, 4, current_y + 2, enum_string, -5600, 1, nil, nil, nil, nil, nil, function() GuiTooltip(menu_gui, GameTextGetTranslatedOrNot(setting.name or ""), GameTextGetTranslatedOrNot(setting.description or "")) end))then
							selected_index = selected_index + 1
							if(selected_index > #setting.options)then
								selected_index = 1
							end
							gamemode_settings[setting.id] = setting.options[selected_index][1]
							settings_changed = true
						end

						

						current_y = current_y + box_h + 2
					elseif(setting.type == "bool")then
						local bool_string = get_split_string(GameTextGetTranslatedOrNot(setting.name or "")..":"..(gamemode_settings[setting.id] and GameTextGetTranslatedOrNot("$mp_setting_enabled") or GameTextGetTranslatedOrNot("$mp_setting_disabled")), 170)
						local chunks = select(2, bool_string:gsub('\n', '\n'))
						local last_w, last_h = GuiGetTextDimensions(menu_gui, bool_string)
						local box_h = last_h + (chunks <= 1 and 2 or 0)
						Gui9Piece(menu_gui, function() return NewID("EditLobby") end, 0, current_y, box_w, box_h, 0.1, -5600, "mods/evaisa.mp/files/gfx/ui/9piece_white.xml", 3)
						
						local r, g, b, a = 1, 1, 1, 1

						-- split bool string by :
						local str1, str2 = bool_string:match("([^,]+:)([^,]+)")
						
						if(gamemode_settings[setting.id])then
							r, g, b, a = 0.4, 1, 0.4, 1
						else
							r, g, b, a = 1, 0.4, 0.4, 1
						end
						

						if(GuiTextButton(menu_gui, function() return NewID("EditLobby") end, 4, current_y + 2, {
							{
								text = str1,
								color = {1, 1, 1, 1}
							},
							{
								text = str2,
								color = {r, g, b, a}
							}
						}, -5600, 1, r, g, b, a, 170, function() GuiTooltip(menu_gui, GameTextGetTranslatedOrNot(setting.name or ""), GameTextGetTranslatedOrNot(setting.description or "")) end))then
							gamemode_settings[setting.id] = not gamemode_settings[setting.id]
							settings_changed = true
						end
						GuiTooltip(menu_gui, GameTextGetTranslatedOrNot(setting.name or ""), GameTextGetTranslatedOrNot(setting.description or ""))
						current_y = current_y + box_h + 2
					elseif(setting.type == "slider")then

						setting.display_multiplier = setting.display_multiplier or 1
						setting.formatting_string = setting.formatting_string or " $0"
						setting.formatting_func = setting.formatting_func or function(value) return value end
						setting.modifier = setting.modifier

						if(setting.modifier == nil)then
							setting.modifier = function(value) return value end
						end

						setting.display_fractions = setting.display_fractions or false
						
						local slider_string = get_split_string(GameTextGetTranslatedOrNot(setting.name or "")..": ", 150)

						local chunks = select(2, slider_string:gsub('\n', '\n'))

						local last_w, last_h = GuiGetTextDimensions(menu_gui, slider_string)
						local box_h = last_h + 16
						Gui9Piece(menu_gui, function() return NewID("EditLobby") end, 0, current_y, box_w, box_h, 0.1, -5600, "mods/evaisa.mp/files/gfx/ui/9piece_white.xml", 3)
						GuiTextMultiline(menu_gui, 4, current_y + 2, slider_string, -5600, 1, 1, 1, 1, 1, 170, function() GuiTooltip(menu_gui, GameTextGetTranslatedOrNot(setting.name), GameTextGetTranslatedOrNot(setting.description)) end)
						

						local slider_value = GuiSlider(menu_gui, NewID("EditLobby"), 2, current_y + last_h + 2, "", gamemode_settings[setting.id], setting.min, setting.max, setting.default, setting.display_multiplier, "        ", 146)
						slider_value = setting.modifier(slider_value)
						local clicked, _, hovered = GuiGetPreviousWidgetInfo(menu_gui)
						GuiTooltip(menu_gui, GameTextGetTranslatedOrNot(setting.name), GameTextGetTranslatedOrNot(setting.description))

						-- take setting.formatting_string, replace $0 with slider_value, take display multiplier into account
						GuiColorSetForNextWidget(menu_gui, 1, 1, 1, 0.7)
						local value_text = string.gsub(setting.formatting_string, "$0", tostring(setting.display_fractions and (slider_value * setting.display_multiplier) or math.floor(slider_value * setting.display_multiplier)))
						value_text = setting.formatting_func(value_text)
						GuiText(menu_gui, 150, current_y + last_h + 1, value_text)

						was_slider_changed = was_slider_changed or {}

						if(tostring(slider_value) ~= tostring(gamemode_settings[setting.id]))then
		
							gamemode_settings[setting.id] = slider_value
							was_slider_changed[setting.id] = GameGetFrameNum()
						end
		
						if(was_slider_changed[setting.id] and (GameGetFrameNum() - was_slider_changed[setting.id]) > 30)then
						
							settings_changed = true
							was_slider_changed[setting.id] = nil
		
							--GlobalsSetValue("setting_next_"..setting.id, tostring(gamemode_settings[setting.id]))
						end
		
						current_y = current_y + box_h + 2
					end
                                    elseif(setting.type == "custom")then
                                            if(setting.draw ~= nil)then
                                                    local drew_h = setting.draw(lobby_code, menu_gui, function() return NewID("EditLobby") end, current_y, box_w) or 0
                                                    current_y = current_y + drew_h
                                            end
				end

				if(settings_changed and owner == steam_utils.getSteamID())then
					steam.matchmaking.setLobbyMemberLimit(lobby_code, edit_lobby_max_players)
					steam_utils.TrySetLobbyData(code, "max_players", tostring(edit_lobby_max_players))
					steam_utils.TrySetLobbyData(lobby_code, "name", edit_lobby_name)
					
					steam_utils.TrySetLobbyData(lobby_code, "seed", edit_lobby_seed)
					for k, setting in ipairs(active_mode.settings or  {})do
						steam_utils.TrySetLobbyData(lobby_code, "setting_"..setting.id, tostring(gamemode_settings[setting.id]))
						mp_log:print("Updated gamemode setting: "..setting.id.." to "..tostring(gamemode_settings[setting.id]))
					end
					print("Updating lobby type: "..internal_types[edit_lobby_type])
					steam.matchmaking.setLobbyType(lobby_code, internal_types[edit_lobby_type])
					steam_utils.send("refresh", {}, steam_utils.messageTypes.AllPlayers, lobby_code, true, true)
					mp_log:print("Updated limit: "..tostring(edit_lobby_max_players))
					mp_log:print("Updated name: "..tostring(edit_lobby_name))
					mp_log:print("Updated type: "..tostring(internal_types[edit_lobby_type]))
					settings_changed = false
					if(active_mode and active_mode.refresh)then
						active_mode.refresh(lobby_code)
					end
					--print("lobby settings changed!")
				end				

			end

		end,
	},
	{
		id = "lobby_presets",
		name = "$mp_lobby_presets",
		button_text = "$mp_lobby_presets",
		draw = function()

			

			if(active_mode ~= nil)then



				if(not was_lobby_presets_open)then
					RefreshPresets()
				end

				GuiLayoutBeginVertical(menu_gui, 0, 0, true, 0, 0)

				preset_name = preset_name or ("Preset_"..tostring(Random(1, 1000000)))
				GuiLayoutBeginHorizontal(menu_gui, 0, 0)
				GuiText(menu_gui, 0, 0, GameTextGetTranslatedOrNot("$mp_preset_name"))
				preset_name = GuiTextInput(menu_gui, NewID("save_preset_name"), 0, 0, preset_name, 90, 15)

				local illegal_chars = {
					"/",
					"\\",
					":",
					"*",
					"?",
					"\"",
					"<",
					">",
					"|",
				}

				for i, char in ipairs(illegal_chars)do
					preset_name = preset_name:gsub(char, "")
				end

				-- remove control characters
				preset_name = preset_name:gsub("%c", "")


				local _, _, hover = GuiGetPreviousWidgetInfo(menu_gui)

				if(hover)then
					GameAddFlagRun("chat_bind_disabled")
				end

				
				GuiLayoutEnd(menu_gui)

				if(GuiButton(menu_gui, NewID("save_preset"), 0, 0, GameTextGetTranslatedOrNot("$mp_save_preset")))then
					if(preset_name ~= " " and preset_name ~= "_" and #preset_name > 0)then
						SavePreset(preset_name)
						RefreshPresets()
					end
				end

				if(GuiButton(menu_gui, NewID("open_presets_folder"), 0, 10, GameTextGetTranslatedOrNot("$mp_open_preset_folder")))then
					os.execute("explorer \"" .. gamemode_preset_folder_name .. "\"")
				end

				if(GuiButton(menu_gui, NewID("refresh_presets"), 0, 0, GameTextGetTranslatedOrNot("$mp_refresh_presets")))then
					RefreshPresets()
				end
				
				GuiText(menu_gui, 0, 0, "--------------------")
				
				for i, preset in ipairs(presets) do
					GuiLayoutBeginHorizontal(menu_gui, 0, 0)
					
					if(preset.default)then
						GuiColorSetForNextWidget( menu_gui, 0.5, 0.5, 0.5, 1.0 )
						if(GuiButton(menu_gui, NewID(), 0, 0, "[?]"))then
							-- nothing here
						end
						GuiTooltip(menu_gui, GameTextGetTranslatedOrNot("$mp_preset_default"), "")
					end

					if(preset.corrupt)then
						GuiColorSetForNextWidget( menu_gui, 1, 0.4, 0.4, 1.0 )
						if(GuiButton(menu_gui, NewID(), 0, 0, "[!]"))then
							-- nothing here
						end
						GuiTooltip(menu_gui, GameTextGetTranslatedOrNot("$mp_preset_corrupt"), "")
					end

					if(preset.data.version == nil or preset.data.version < MP_PRESET_VERSION)then
						GuiColorSetForNextWidget( menu_gui, 1, 0.4, 0.4, 1.0 )
						if(GuiButton(menu_gui, NewID(), 0, 0, "[!]"))then
							-- nothing here
						end
						GuiTooltip(menu_gui, GameTextGetTranslatedOrNot("$mp_preset_outdated"), "")
					end
					
					if((not preset.default) and GuiButton(menu_gui, NewID("remove_preset_"..tostring(preset.name)), 0, 0, GameTextGetTranslatedOrNot("$mp_remove_preset")))then
						popup.create("delete_preset_prompt", string.format(GameTextGetTranslatedOrNot("$mp_delete_preset_confirm"), preset.name),{
							{
								text = GameTextGetTranslatedOrNot("$mp_delete_preset_confirm_description"),
								color = {214 / 255, 60 / 255, 60 / 255, 1}
							},
						}, {
							{
								text = GameTextGetTranslatedOrNot("$mp_delete_preset_confirm_delete"),
								callback = function()
									RemovePreset(preset.name, preset.extension)
									RefreshPresets()
								end
							},
							{
								text = GameTextGetTranslatedOrNot("$mp_delete_preset_confirm_cancel"),
								callback = function()
								end
							}
						}, -6000)
						
						--[[
						RemovePreset(preset.name)
						RefreshPresets()
						]]
					end

					if(GuiButton(menu_gui, NewID("load_preset_"..tostring(preset.name)), 0, 0, ((preset.corrupt and "[invalid]") or "") .. preset.name))then
						
						local data_copy_str = bitser.dumps(preset)
						local data_copy = bitser.loads(data_copy_str)

						preset = data_copy

						local preset_info = preset

						

						if(preset.data.version == nil or preset.data.version < MP_PRESET_VERSION)then
							preset_info = {
								outdated = true,
								name = preset.name,
								data = {
									version = preset.data.version or 1,
									settings = preset.data
								}
							}
						end

						


						gamemode_settings = preset_info.data.settings

						-- loop through 
						for k, setting in ipairs(active_mode.settings or {})do
							if(gamemode_settings[setting.id] == nil)then
								gamemode_settings[setting.id] = setting.default
								print("Setting "..setting.id.." to default: "..tostring(setting.default))
							end
						end


						print("loaded: "..json.stringify(gamemode_settings))



						preset_name = preset_info.name
						--settings_changed = true

						for k, setting in ipairs(active_mode.settings or {})do
							steam_utils.TrySetLobbyData(lobby_code, "setting_"..setting.id, tostring(gamemode_settings[setting.id]))
							mp_log:print("Updated gamemode setting: "..setting.id.." to "..tostring(gamemode_settings[setting.id]))
						end

						--steam.matchmaking.sendLobbyChatMsg(lobby_code, "refresh")
						steam_utils.send("refresh", {}, steam_utils.messageTypes.AllPlayers, lobby_code, true, true)

						if(active_mode.load_preset)then
							active_mode.load_preset(lobby_code, preset_info.data)
						end
					end
					
					GuiLayoutEnd(menu_gui)
				end
				

				GuiLayoutEnd(menu_gui)
		
			end
			was_lobby_presets_open = true

		end,
		close = function()
			was_lobby_presets_open = false
		end
	},
	{
		id = "voice_volumes",
		name = "Voice Volumes",
		button_text = "Voice",
		draw = function(lobby, gui, new_id)
			local players = steam_utils.getLobbyMembers(lobby, true)
			local my_id = steam_utils.getSteamID()
			local box_w = 180
			local current_y = 0

			for _, v in pairs(players) do
				if v.id ~= my_id then
					local name = tostring(v.name)
					local key = "evaisa.mp.player_vol_" .. tostring(v.id)
					local cur_vol = tonumber(ModSettingGet(key)) or 1.0

					local label = name
					if #label > 18 then label = label:sub(1, 18) .. ".." end

					local lw, lh = GuiGetTextDimensions(gui, label)
					local box_h = lh + 16
					Gui9Piece(gui, function() return new_id("vc_vol_" .. tostring(v.id)) end, 0, current_y, box_w, box_h, 0.1, -5600, "mods/evaisa.mp/files/gfx/ui/9piece_white.xml", 3)
					GuiText(gui, 4, current_y + 2, label)

					local new_vol = GuiSlider(gui, new_id("vc_vol_sl_" .. tostring(v.id)), 2, current_y + lh + 2, "", cur_vol, 0.0, 2.0, 1.0, 0.05, "        ", 146)

					GuiColorSetForNextWidget(gui, 1, 1, 1, 0.7)
					GuiText(gui, 153, current_y + lh + 1, math.floor(new_vol * 100) .. "%")

					if math.abs(new_vol - cur_vol) > 0.01 then
						ModSettingSet(key, new_vol)
					end

					current_y = current_y + box_h + 2
				end
			end

			if current_y == 0 then
				GuiText(gui, 4, 0, "No other players")
			end
		end,
	}
}
lobby_menus = lobby_menus or {}

function generate_lobby_menus_list()
	local new_lobby_menus = {}

	for i, v in ipairs(default_lobby_menus)do
		table.insert(new_lobby_menus, v)
	end

	local active_mode = FindGamemode(steam.matchmaking.getLobbyData(lobby_code, "gamemode"))
	if(active_mode ~= nil and active_mode.lobby_menus ~= nil)then
		for i, lobby_menu in ipairs(active_mode.lobby_menus)do
			table.insert(new_lobby_menus, lobby_menu)
		end
	end

	lobby_menus = new_lobby_menus
end


function custom_menu_close_callback_right()
	if(lobby_code ~= nil and active_lobby_menu_right ~= nil)then
		for i, lobby_menu in ipairs(lobby_menus)do
			if(lobby_menu.id == active_lobby_menu_right)then
				if(lobby_menu.close ~= nil)then
					lobby_menu.close()
				end
			end
		end
	end
end

function custom_menu_close_callback_left()
	if(lobby_code ~= nil and active_lobby_menu_left ~= nil)then
		for i, lobby_menu in ipairs(lobby_menus)do
			if(lobby_menu.id == active_lobby_menu_left)then
				if(lobby_menu.close ~= nil)then
					lobby_menu.close()
				end
			end
		end
	end
end

local windows = {
	{
		name = "Menu",
		func = function()

			local window_width = 200
			local window_height = 180
		
			local window_text = GameTextGetTranslatedOrNot("$mp_lobby_list_header")
		
			DrawWindow(menu_gui, -4000, screen_width / 2, screen_height / 2, window_width, window_height, window_text, true, function()
				GuiLayoutBeginVertical(menu_gui, 0, 0, true, 0, 0)

				if(GuiButton(menu_gui, NewID(), 0, 0, GameTextGetTranslatedOrNot("$mp_create_lobby")))then
					menu_status = status.creating_lobby
				end

				if(GuiButton(menu_gui, NewID(), 0, 0, GameTextGetTranslatedOrNot("$mp_join_with_code")))then
					menu_status = status.joining_lobby
				end

				GuiText(menu_gui, 2, 0, " ")

				if(GuiButton(menu_gui, NewID(), 0, 0, GameTextGetTranslatedOrNot("$hub_create")))then
					menu_status = status.creating_hub
				end

				if(GuiButton(menu_gui, NewID(), 0, 0, GameTextGetTranslatedOrNot("$hub_join")))then
					menu_status = status.joining_hub
				end

				GuiText(menu_gui, 2, 0, " ")
				if(GuiButton(menu_gui, NewID(), 0, 0, GameTextGetTranslatedOrNot("$mp_refresh_lobby_list")))then
					refreshLobbies()
				end
				GuiText(menu_gui, 2, 0, " ")
				if(lobby_filter_show_friends)then
				GuiText(menu_gui, 2, 0, "----- "..GameTextGetTranslatedOrNot("$mp_friend_lobbies").." -----")
				if(#lobbies.friend > 0)then
					for k, v in ipairs(lobbies.friend)do
						if(steam.matchmaking.requestLobbyData(v))then
							local lobby_mode_id = steam.matchmaking.getLobbyData(v, "gamemode")
							local active_mode = FindGamemode(steam.matchmaking.getLobbyData(v, "gamemode"))
							local lobby_name = steam.matchmaking.getLobbyData(v, "name")
							local custom_lobby_string = (active_mode and active_mode.custom_lobby_string) and active_mode.custom_lobby_string(v) or ""

							if(custom_lobby_string ~= "")then
								custom_lobby_string = custom_lobby_string .. " "
							end	

							local lobby_members = steam.matchmaking.getNumLobbyMembers(v)
							local lobby_max_players = steam.matchmaking.getLobbyMemberLimit(v)

							if(lobby_name ~= nil and active_mode ~= nil and lobby_mode_id ~= nil and lobby_members ~= nil and lobby_max_players ~= nil and (lobby_filter_show_full or lobby_members < lobby_max_players) and (lobby_filter_max_players == 0 or lobby_max_players == lobby_filter_max_players))then
								GuiLayoutBeginHorizontal(menu_gui, 0, 0, true, 0, 0)
								if(not IsCorrectVersion(v))then
									--[[
									if(GuiButton(menu_gui, NewID(), 0, 0, GameTextGetTranslatedOrNot("$mp_version_mismatch").." "..lobby_name))then
										steam_utils.Leave(v)
										steam.matchmaking.joinLobby(v, function(e)
										end)
									end
									]]
									GuiColorSetForNextWidget( menu_gui, 1, 0.4, 0.4, 1.0 )
									if(GuiButton(menu_gui, NewID(), 0, 0, "[?]"))then
										-- nothing here
									end
									CustomTooltip(menu_gui, function() 

										local info = VersionInfo(v)
										
										--GuiZSetForNextWidget(menu_gui, -6110)
										GuiColorSetForNextWidget( menu_gui, 1, 0.4, 0.4, 1.0 )
										--GuiText(menu_gui, 0, 0, "Hide Code")
										GuiZSetForNextWidget(menu_gui, -6210)
										GuiText(menu_gui, 0, 0, GameTextGetTranslatedOrNot("$mp_version_mismatch"))
	
										GuiColorSetForNextWidget( menu_gui, 0.8, 0.8, 0.8, 1.0 )
										GuiZSetForNextWidget(menu_gui, -6210)
										GuiText(menu_gui, 0, 0, info.mp_version_string)
										if(not info.mp_version_same)then
											GuiColorSetForNextWidget( menu_gui, 0.8, 0.8, 0.8, 1.0 )
											GuiZSetForNextWidget(menu_gui, -6210)
											GuiText(menu_gui, 0, 0, info.mp_version_string_user)
										end
	
										GuiText(menu_gui, 0, 0, " ")
										
										GuiColorSetForNextWidget( menu_gui, 0.8, 0.8, 0.8, 1.0 )
										GuiZSetForNextWidget(menu_gui, -6210)
										GuiText(menu_gui, 0, 0, info.gamemode_version_string)
										if(not info.gamemode_missing and not info.gamemode_version_same)then
											GuiColorSetForNextWidget( menu_gui, 0.8, 0.8, 0.8, 1.0 )
											GuiZSetForNextWidget(menu_gui, -6210)
											GuiText(menu_gui, 0, 0, info.gamemode_version_string_user)
										end

										-- game version
										GuiText(menu_gui, 0, 0, " ")

										GuiColorSetForNextWidget( menu_gui, 0.8, 0.8, 0.8, 1.0 )
										GuiZSetForNextWidget(menu_gui, -6210)
										GuiText(menu_gui, 0, 0, info.game_version_string)
										if(not info.game_version_same)then
											GuiColorSetForNextWidget( menu_gui, 0.8, 0.8, 0.8, 1.0 )
											GuiZSetForNextWidget(menu_gui, -6210)
											GuiText(menu_gui, 0, 0, info.game_version_string_user)
										end
	
	
									end, -6200, 0, 0)
									
									GuiZSetForNextWidget(menu_gui, -6000)
									GuiColorSetForNextWidget( menu_gui, 0.5, 0.5, 0.5, 1 )
									GuiText(menu_gui, 0, 0, "("..tostring(lobby_members).."/"..tostring(lobby_max_players)..") "..custom_lobby_string..lobby_name)

								else
									if(active_mode ~= nil)then

										if(HasRequiredMods(v))then
											GuiZSetForNextWidget(menu_gui, -6000)
											if(GuiButton(menu_gui, NewID(), 0, 0, "("..tostring(lobby_members).."/"..tostring(lobby_max_players)..") "..custom_lobby_string..lobby_name))then
												steam_utils.Leave(v)
												steam.matchmaking.joinLobby(v, function(e)
												end)
											end
										else
											GuiColorSetForNextWidget( menu_gui, 1, 0.4, 0.4, 1.0 )
											if(GuiButton(menu_gui, NewID(), 0, 0, "[?]"))then
											
											end
											CustomTooltip(menu_gui, function() 
												local info = ModInfo(v)

												GuiColorSetForNextWidget( menu_gui, 1, 0.4, 0.4, 1.0 )
												--GuiText(menu_gui, 0, 0, "Hide Code")
												GuiZSetForNextWidget(menu_gui, -6210)
												GuiText(menu_gui, 0, 0, GameTextGetTranslatedOrNot("$mp_lobby_info_missing_mods"))
		
												local strings = split_message(info.missing_mods_string, 200) or {}

												for k, v in ipairs(strings)do
													GuiColorSetForNextWidget( menu_gui, 0.8, 0.8, 0.8, 1.0 )
													GuiZSetForNextWidget(menu_gui, -6210)
													GuiText(menu_gui, 0, 0, v)
												end
											
											end, -6200, 0, 0)
		
											GuiZSetForNextWidget(menu_gui, -6000)
											GuiColorSetForNextWidget( menu_gui, 0.5, 0.5, 0.5, 1 )
											GuiText(menu_gui, 0, 0, "("..tostring(lobby_members).."/"..tostring(lobby_max_players)..") "..custom_lobby_string..lobby_name)
										end
									else
										--[[if(GuiButton(menu_gui, NewID(), 0, 0, "("..lobby_mode_id..""..GameTextGetTranslatedOrNot("$mp_missing")..")("..tostring(lobby_members).."/"..tostring(lobby_max_players)..") "..lobby_name))then
											steam_utils.Leave(v)
											steam.matchmaking.joinLobby(v, function(e)
											end)
										end]]
										GuiColorSetForNextWidget( menu_gui, 1, 0.4, 0.4, 1.0 )
										if(GuiButton(menu_gui, NewID(), 0, 0, "[?]"))then
										
										end
										CustomTooltip(menu_gui, function() 
											GuiColorSetForNextWidget( menu_gui, 1, 0.4, 0.4, 1.0 )
											--GuiText(menu_gui, 0, 0, "Hide Code")
											GuiZSetForNextWidget(menu_gui, -6210)
											GuiText(menu_gui, 0, 0, GameTextGetTranslatedOrNot("$mp_missing"))
	
											GuiColorSetForNextWidget( menu_gui, 0.8, 0.8, 0.8, 1.0 )
											GuiZSetForNextWidget(menu_gui, -6210)
											GuiText(menu_gui, 0, 0, string.format(GameTextGetTranslatedOrNot("mp_lobby_info_gm_missing"), lobby_mode_id, steam.matchmaking.getLobbyData(VersionInfo, "version")))
										
										end, -6200, 0, 0)
	
										GuiZSetForNextWidget(menu_gui, -6000)
										GuiColorSetForNextWidget( menu_gui, 0.5, 0.5, 0.5, 1 )
										GuiText(menu_gui, 0, 0, "("..tostring(lobby_members).."/"..tostring(lobby_max_players)..") "..custom_lobby_string..lobby_name)
									end
								end

								GuiLayoutEnd(menu_gui)
							end
						end
					end
				else
					GuiText(menu_gui, 2, 0, GameTextGetTranslatedOrNot("$mp_no_lobbies_found"))
				end
				end
				GuiText(menu_gui, 2, 0, " ")
				if(lobby_filter_show_public)then
				GuiText(menu_gui, 2, 0, "----- "..GameTextGetTranslatedOrNot("$mp_public_lobbies").." -----")
				if(#lobbies.public > 0)then
					for k, v in ipairs(lobbies.public)do
						local lobby_mode_id = steam.matchmaking.getLobbyData(v, "gamemode")
						local active_mode = FindGamemode(steam.matchmaking.getLobbyData(v, "gamemode"))
						local lobby_name = steam.matchmaking.getLobbyData(v, "name")
						local custom_lobby_string = (active_mode and active_mode.custom_lobby_string) and active_mode.custom_lobby_string(v) or ""

						if(custom_lobby_string ~= "")then
							custom_lobby_string = custom_lobby_string .. " "
						end

						local lobby_members = steam.matchmaking.getNumLobbyMembers(v)
						local lobby_max_players = steam.matchmaking.getLobbyMemberLimit(v)

						if(lobby_name ~= nil and active_mode ~= nil and lobby_mode_id ~= nil and lobby_members ~= nil and lobby_max_players ~= nil and (lobby_filter_show_full or lobby_members < lobby_max_players) and (lobby_filter_max_players == 0 or lobby_max_players == lobby_filter_max_players))then
							GuiLayoutBeginHorizontal(menu_gui, 0, 0, true, 0, 0)
							if(not IsCorrectVersion(v))then
								--[[if(GuiButton(menu_gui, NewID(), 0, 0, GameTextGetTranslatedOrNot("$mp_version_mismatch").." "..lobby_name))then
									steam_utils.Leave(v)
									steam.matchmaking.joinLobby(v, function(e)
									end)
								end]]
								GuiColorSetForNextWidget( menu_gui, 1, 0.4, 0.4, 1.0 )
								if(GuiButton(menu_gui, NewID(), 0, 0, "[?]"))then
									-- nothing here
								end
								CustomTooltip(menu_gui, function() 

									local info = VersionInfo(v)
									
									--GuiZSetForNextWidget(menu_gui, -6110)
									GuiColorSetForNextWidget( menu_gui, 1, 0.4, 0.4, 1.0 )
									--GuiText(menu_gui, 0, 0, "Hide Code")
									GuiZSetForNextWidget(menu_gui, -6210)
									GuiText(menu_gui, 0, 0, GameTextGetTranslatedOrNot("$mp_version_mismatch"))

									GuiColorSetForNextWidget( menu_gui, 0.8, 0.8, 0.8, 1.0 )
									GuiZSetForNextWidget(menu_gui, -6210)
									GuiText(menu_gui, 0, 0, info.mp_version_string)
									if(not info.mp_version_same)then
										GuiColorSetForNextWidget( menu_gui, 0.8, 0.8, 0.8, 1.0 )
										GuiZSetForNextWidget(menu_gui, -6210)
										GuiText(menu_gui, 0, 0, info.mp_version_string_user)
									end

									GuiText(menu_gui, 0, 0, " ")
									
									GuiColorSetForNextWidget( menu_gui, 0.8, 0.8, 0.8, 1.0 )
									GuiZSetForNextWidget(menu_gui, -6210)
									GuiText(menu_gui, 0, 0, info.gamemode_version_string)
									if(not info.gamemode_missing and not info.gamemode_version_same)then
										GuiColorSetForNextWidget( menu_gui, 0.8, 0.8, 0.8, 1.0 )
										GuiZSetForNextWidget(menu_gui, -6210)
										GuiText(menu_gui, 0, 0, info.gamemode_version_string_user)
									end

									-- game version
									GuiText(menu_gui, 0, 0, " ")

									GuiColorSetForNextWidget( menu_gui, 0.8, 0.8, 0.8, 1.0 )
									GuiZSetForNextWidget(menu_gui, -6210)
									GuiText(menu_gui, 0, 0, info.game_version_string)
									if(not info.game_version_same)then
										GuiColorSetForNextWidget( menu_gui, 0.8, 0.8, 0.8, 1.0 )
										GuiZSetForNextWidget(menu_gui, -6210)
										GuiText(menu_gui, 0, 0, info.game_version_string_user)
									end


								end, -6200, 0, 0)

								GuiZSetForNextWidget(menu_gui, -6000)
								GuiColorSetForNextWidget( menu_gui, 0.5, 0.5, 0.5, 1 )
								GuiText(menu_gui, 0, 0, "("..tostring(lobby_members).."/"..tostring(lobby_max_players)..") "..custom_lobby_string..lobby_name)
							else
								if(active_mode ~= nil)then
									if(HasRequiredMods(v))then
										GuiZSetForNextWidget(menu_gui, -6000)
										if(GuiButton(menu_gui, NewID(), 0, 0, "("..tostring(lobby_members).."/"..tostring(lobby_max_players)..") "..custom_lobby_string..lobby_name))then
											steam_utils.Leave(v)
											steam.matchmaking.joinLobby(v, function(e)
											end)
										end
									else
										GuiColorSetForNextWidget( menu_gui, 1, 0.4, 0.4, 1.0 )
										if(GuiButton(menu_gui, NewID(), 0, 0, "[?]"))then
										
										end
										CustomTooltip(menu_gui, function() 
											local info = ModInfo(v)

											GuiColorSetForNextWidget( menu_gui, 1, 0.4, 0.4, 1.0 )
											--GuiText(menu_gui, 0, 0, "Hide Code")
											GuiZSetForNextWidget(menu_gui, -6210)
											GuiText(menu_gui, 0, 0, GameTextGetTranslatedOrNot("$mp_lobby_info_missing_mods"))
	
											local strings = split_message(info.missing_mods_string, 200) or {}

											for k, v in ipairs(strings)do
												GuiColorSetForNextWidget( menu_gui, 0.8, 0.8, 0.8, 1.0 )
												GuiZSetForNextWidget(menu_gui, -6210)
												GuiText(menu_gui, 0, 0, v)
											end
										
										end, -6200, 0, 0)
	
										GuiZSetForNextWidget(menu_gui, -6000)
										GuiColorSetForNextWidget( menu_gui, 0.5, 0.5, 0.5, 1 )
										GuiText(menu_gui, 0, 0, "("..tostring(lobby_members).."/"..tostring(lobby_max_players)..") "..custom_lobby_string..lobby_name)
									end
								else
									--[[if(GuiButton(menu_gui, NewID(), 0, 0, "("..lobby_mode_id..GameTextGetTranslatedOrNot("$mp_missing")..")("..tostring(lobby_members).."/"..tostring(lobby_max_players)..") "..lobby_name))then

									end]]
									GuiColorSetForNextWidget( menu_gui, 1, 0.4, 0.4, 1.0 )
									if(GuiButton(menu_gui, NewID(), 0, 0, "[?]"))then

									end
									CustomTooltip(menu_gui, function() 
										GuiColorSetForNextWidget( menu_gui, 1, 0.4, 0.4, 1.0 )
										--GuiText(menu_gui, 0, 0, "Hide Code")
										GuiZSetForNextWidget(menu_gui, -6210)
										GuiText(menu_gui, 0, 0, GameTextGetTranslatedOrNot("$mp_missing"))

										GuiColorSetForNextWidget( menu_gui, 0.8, 0.8, 0.8, 1.0 )
										GuiZSetForNextWidget(menu_gui, -6210)
										GuiText(menu_gui, 0, 0, string.format(GameTextGetTranslatedOrNot("mp_lobby_info_gm_missing"), lobby_mode_id, steam.matchmaking.getLobbyData(VersionInfo, "version")))
									
									end, -6200, 0, 0)

									GuiZSetForNextWidget(menu_gui, -6000)
									GuiColorSetForNextWidget( menu_gui, 0.5, 0.5, 0.5, 1 )
									GuiText(menu_gui, 0, 0, "("..tostring(lobby_members).."/"..tostring(lobby_max_players)..") "..custom_lobby_string..lobby_name)
								end
							end
							

							GuiLayoutEnd(menu_gui)
						end
					end
				else
					GuiText(menu_gui, 2, 0, GameTextGetTranslatedOrNot("$mp_no_lobbies_found"))
				end
				end
					
				
				--[[
				for i = 1, 40 do
					GuiText(menu_gui, 2, 0, " ")
				end
				]]

				GuiLayoutEnd(menu_gui)
			end, function() 
				gui_closed = true; 
				invite_menu_open = false 
				selected_player = nil
			end, "main_menu_gui")

			local filter_panel_width = 160
			DrawWindow(menu_gui, -4000, (screen_width / 2 - window_width / 2) - (filter_panel_width / 2) - 10, screen_height / 2, filter_panel_width, window_height, "Filters", true, function()
				GuiLayoutBeginVertical(menu_gui, 0, 0, true, 0, 0)
				local chk = function(val) return val and "[X]" or "[ ]" end

				if(GuiButton(menu_gui, NewID("LobbyFilter"), 0, 0, chk(lobby_filter_show_full) .. " Show Full"))then
					lobby_filter_show_full = not lobby_filter_show_full
				end
				if(GuiButton(menu_gui, NewID("LobbyFilter"), 0, 0, chk(lobby_filter_show_friends) .. " Friends"))then
					lobby_filter_show_friends = not lobby_filter_show_friends
				end
				if(GuiButton(menu_gui, NewID("LobbyFilter"), 0, 0, chk(lobby_filter_show_public) .. " Public"))then
					lobby_filter_show_public = not lobby_filter_show_public
				end

				GuiText(menu_gui, 2, 0, " ")

				local distance_order = {"close", "default", "far", "worldwide"}
				if(GuiButton(menu_gui, NewID("LobbyFilter"), 0, 0, "Dist: " .. distance[lobby_filter_distance]))then
					for i, d in ipairs(distance_order) do
						if(d == lobby_filter_distance)then
							lobby_filter_distance = distance_order[(i % #distance_order) + 1]
							refreshLobbies()
							break
						end
					end
				end

				GuiText(menu_gui, 2, 0, " ")

				local max_str = lobby_filter_max_players == 0 and "Any" or tostring(lobby_filter_max_players)
				GuiText(menu_gui, 2, 0, "Players: " .. max_str)
				local slider_val = GuiSlider(menu_gui, NewID("LobbyFilter"), 4, 0, "", lobby_filter_max_players, 0, 32, 0, 1, " $0", 120)
				lobby_filter_max_players = math.floor(slider_val)

				GuiLayoutEnd(menu_gui)
			end, nil, "lobby_filter_panel")

		end
	},
	{
		name = "Lobby",
		func 	= function()
			local window_width = 200
			local window_height = 280
			

			function string_to_number(str)
				local num = 0
				local validCharacters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
				local str_len = #validCharacters
				for i=1, str_len do
				  local ch = str:sub(i, i)
				  local value = validCharacters:find(ch)
				  value = value - 1
				  num = num + math.pow(str_len, (#str - i)) * value
				end
				return num
			end

			if(not lobby_code)then
				-- force return to main menu
				print("Disconnected from lobby?? (no lobby code)")
				gui_closed = false
				gamemode_settings = {}
				initial_refreshes = 10
				invite_menu_open = false
				if hub_state ~= nil and hub_source_lobby then
					hub_source_lobby = false
					menu_status = status.hub
				else
					menu_status = status.main_menu
				end
				show_lobby_code = false
				lobby_code = nil
				banned_members = {}
				return;
			end

			local window_width, x_pos = GetMenuSettings("center")

			DrawWindow(menu_gui, -5000, x_pos, screen_height / 2, window_width, window_height, function() 

				GuiColorSetForNextWidget( menu_gui, 0, 0, 0, 0.3 )
				GuiText(menu_gui, 0, 0, GameTextGetTranslatedOrNot("$mp_lobby").." - ("..((not show_lobby_code) and censorString(steam.utils.compressSteamID(lobby_code)) or steam.utils.compressSteamID(lobby_code))..")")

				GuiColorSetForNextWidget( menu_gui, (74 / 2) / 255, (62 / 2) / 255, (46 / 2) / 255, 0.5 )
				--GuiImage(menu_gui, NewID("Lobby"), 1, 1.5, (show_lobby_code) and "mods/evaisa.mp/files/gfx/ui/hide.png" or "mods/evaisa.mp/files/gfx/ui/show.png", 0.5, 1)
				

				GuiColorSetForNextWidget( menu_gui, 74 / 255, 62 / 255, 46 / 255, 0.5 )
				if(GuiImageButton(menu_gui, NewID("Lobby"), 1, 1.5, "", (show_lobby_code) and "mods/evaisa.mp/files/gfx/ui/hide.png" or "mods/evaisa.mp/files/gfx/ui/show.png"))then
					show_lobby_code = not show_lobby_code
					GamePlaySound("data/audio/Desktop/ui.bank", "ui/button_click", 0, 0)
				end
				
				if(show_lobby_code)then
					CustomTooltip(menu_gui, function() 
						--GuiZSetForNextWidget(menu_gui, -5110)
						GuiColorSetForNextWidget( menu_gui, 1, 1, 1, 0.8 )
						--GuiText(menu_gui, 0, 0, "Hide Code")
						GuiZSetForNextWidget(menu_gui, -5110)
						GuiText(menu_gui, 0, 0, GameTextGetTranslatedOrNot("$mp_hide_tooltip"))
					end, -5100, -60, -20)
				else
					CustomTooltip(menu_gui, function() 
						--GuiZSetForNextWidget(menu_gui, -5110)
						GuiColorSetForNextWidget( menu_gui, 1, 1, 1, 0.8 )
						--GuiText(menu_gui, 0, 0, "Show Code")
						GuiZSetForNextWidget(menu_gui, -5110)
						GuiText(menu_gui, 0, 0, GameTextGetTranslatedOrNot("$mp_show_tooltip"))
					end, -5100, -68, -20)
				end

				
				--GuiImage(menu_gui, NewID("Lobby"), 6, 1.5, "mods/evaisa.mp/files/gfx/ui/copy.png", 0.5, 1)

				--[[GuiColorSetForNextWidget( menu_gui, 0, 0, 0, 0.5 )
				if(GuiButton(menu_gui, NewID("Lobby"), -1, 0, " "..GameTextGetTranslatedOrNot("$mp_copy")))then
					steam.utils.setClipboard(steam.utils.compressSteamID(lobby_code))
				end]]

				GuiColorSetForNextWidget( menu_gui, 74 / 255, 62 / 255, 46 / 255, 0.5 )
				if(GuiImageButton(menu_gui, NewID("Lobby"), 6, 1.5, "", "mods/evaisa.mp/files/gfx/ui/copy.png"))then
					steam.utils.setClipboard(steam.utils.compressSteamID(lobby_code))
					GamePlaySound("data/audio/Desktop/ui.bank", "ui/button_click", 0, 0)
				end

				CustomTooltip(menu_gui, function() 
					--GuiZSetForNextWidget(menu_gui, -5110)
					GuiColorSetForNextWidget( menu_gui, 1, 1, 1, 0.8 )
					--GuiText(menu_gui, 0, 0, "Show Code")
					GuiZSetForNextWidget(menu_gui, -5110)
					GuiText(menu_gui, 0, 0, GameTextGetTranslatedOrNot("$mp_copy_tooltip"))
				end, -5100, -180, -20)
				
			end, true, function(window_x, window_y, window_width, window_height)
				


				local owner = steam.matchmaking.getLobbyOwner(lobby_code)



				--local _, _, _, _, _, width, height = GuiGetPreviousWidgetInfo(menu_gui)

				local current_button_height = 0

				-- old presets stuff
		
				--local lobby_presets_translation = GameTextGetTranslatedOrNot("$mp_lobby_presets")
				--local lobby_presets_button_text = lobby_presets_open and lobby_presets_translation.." >" or lobby_presets_translation.." <"
				--local text_width, text_height = GuiGetTextDimensions(menu_gui, lobby_presets_button_text)
				--current_button_height = current_button_height + text_height
				--local button_x_position = window_width - text_width
				GuiLayoutBeginVertical(menu_gui, 0, 0, true, 0, 0)
				--[[if(GuiButton(menu_gui, NewID("lobby_presets_button"), button_x_position, 0, lobby_presets_button_text))then
					lobby_presets_open = not lobby_presets_open
					custom_menu_close_callback()
					active_lobby_menu_right = nil
					selected_player = nil
				end]]


				--current_button_offset = current_button_offset + text_height

				if(lobby_menus ~= nil)then
					for i, lobby_menu in ipairs(lobby_menus)do
						if((lobby_menu.button_location == nil or lobby_menu.button_location == "main_window") and not lobby_menu.menu_left)then
							local button_string = GameTextGetTranslatedOrNot(lobby_menu.button_text)

							local truncate_chars = 20
							local truncate_string = button_string
							if(#button_string > truncate_chars)then
								truncate_string = utf8.sub(button_string, 1, truncate_chars).."..."
							end
							
							local actual_string = button_string
							if(last_button_hovered ~= lobby_menu.id)then
								actual_string = truncate_string
							end
							

							local button_text = active_lobby_menu_right == lobby_menu.id and actual_string.." >" or actual_string.." <"
	
							local text_width, text_height = GuiGetTextDimensions(menu_gui, button_text)
							button_x_position = window_width - text_width
							current_button_height = current_button_height + text_height
							if(GuiButton(menu_gui, NewID("lobby_menu_"..lobby_menu.id), button_x_position, 0, button_text))then
								if(active_lobby_menu_right == lobby_menu.id)then
									custom_menu_close_callback_right()
									active_lobby_menu_right = nil
								else
									custom_menu_close_callback_right()
									active_lobby_menu_right = lobby_menu.id
								end

								lobby_presets_open = false
								selected_player = nil
							end

							local _, _, hover = GuiGetPreviousWidgetInfo(menu_gui)
							if(hover)then
								--print("Hovering over: "..lobby_menu.id)
								last_button_hovered = lobby_menu.id
							end
							--current_button_offset = current_button_offset + text_height
						end
					end
				end
				GuiLayoutEnd(menu_gui)

				GuiLayoutBeginVertical(menu_gui, 0, 0, true, 0, 0)


				if(GuiButton(menu_gui, NewID("lobby_leave_button"), 0, 0, GameTextGetTranslatedOrNot("$mp_leave_lobby")))then
					steam_utils.Leave(lobby_code)
					return
				end


				local invite_translation = GameTextGetTranslatedOrNot("$mp_invite_players")
				if(GuiButton(menu_gui, NewID("lobby_invite_button"), 0, 0, invite_translation) and GameGetFrameNum() > (last_frame_overlay or 0) + 80)then
					-- need to delay this or noita gets angry??
					--steam.friends.activateGameOverlayInviteDialog(lobby_code)
					delay.new(5, function()
						steam.friends.activateGameOverlay("friends")
					end) 
					last_frame_overlay = GameGetFrameNum()
					print("Opening invite menu")
				end

				if(lobby_menus ~= nil)then
					for i, lobby_menu in ipairs(lobby_menus)do
						if((lobby_menu.button_location == nil or lobby_menu.button_location == "main_window") and lobby_menu.menu_left)then
							local button_text = active_lobby_menu_left == lobby_menu.id and "< "..GameTextGetTranslatedOrNot(lobby_menu.button_text) or "> "..GameTextGetTranslatedOrNot(lobby_menu.button_text)
							local text_width, text_height = GuiGetTextDimensions(menu_gui, button_text)
							current_button_height = current_button_height + text_height
							if(GuiButton(menu_gui, NewID("lobby_menu_"..lobby_menu.id), 0, 0, button_text))then
								if(active_lobby_menu_left == lobby_menu.id)then
									custom_menu_close_callback_left()
									active_lobby_menu_left = nil
								else
									custom_menu_close_callback_left()
									active_lobby_menu_left = lobby_menu.id
								end

								selected_player = nil
							end
							--current_button_offset = current_button_offset + text_height
						end
					end
				end

				--[[
				local lobby_settings_translation = GameTextGetTranslatedOrNot("$mp_lobby_settings")
				if(GuiButton(menu_gui, NewID("lobby_settings_button"), 0, 0, lobby_settings_open and "< "..lobby_settings_translation or "> "..lobby_settings_translation))then
					lobby_settings_open = not lobby_settings_open
					invite_menu_open = false
				end
				]]

				-- calculate relative offset from window_y
				local relative_offset = 33

				--GamePrint("relative_offset: "..tostring(relative_offset).."; current_button_height: "..tostring(current_button_height))

				local tw, th = GuiGetTextDimensions(menu_gui, "ABCDEFGHIJKLMNOPQRSTUVWXYZ")

				local extra_offset = 0
				if(active_mode and active_mode.enable_spectator)then
					extra_offset = extra_offset + th
				end
				
				if(owner == steam_utils.getSteamID())then
					extra_offset = extra_offset + th
				end

				local lobby_in_progress = steam.matchmaking.getLobbyData(lobby_code, "in_progress") == "true"
				
				if(lobby_in_progress and not in_game)then
					extra_offset = extra_offset + th
				end


				local offset = 0
				if(current_button_height > relative_offset)then
					offset = current_button_height
					if(extra_offset < current_button_height - relative_offset)then
						offset = offset - extra_offset
					else
						offset = relative_offset
					end
				else
					offset = relative_offset
				end

				GuiLayoutEnd(menu_gui)

				GuiLayoutBeginVertical(menu_gui, 0, offset, true, 0, 0)

				local active_mode = FindGamemode(steam.matchmaking.getLobbyData(lobby_code, "gamemode"))
				local spectating = steamutils.IsSpectator(lobby_code)

	

				if(active_mode and active_mode.enable_spectator)then
					local is_busy = false
					local busy_reason = ""
					if(active_mode.custom_spectator_check)then
						local can_spectate, reason = active_mode.custom_spectator_check(lobby_code)
						if(not can_spectate)then
							GuiOptionsAddForNextWidget(menu_gui, GUI_OPTION.NonInteractive)
							GuiColorSetForNextWidget( menu_gui, 0.5, 0.5, 0.5, 1 )
							is_busy = true
							busy_reason = reason
						end
					end
					if(GuiButton(menu_gui, NewID("lobby_spectate_button"), 0, 0, spectating and GameTextGetTranslatedOrNot("$mp_spectator_mode_enabled")..(active_mode.spectator_unfinished_warning and " [Unfinished]" or "") or GameTextGetTranslatedOrNot("$mp_spectator_mode_disabled")..(active_mode.spectator_unfinished_warning and " [Unfinished]" or "")))then
						if(owner == steam_utils.getSteamID())then
							steam_utils.TrySetLobbyData(lobby_code, tostring(steam_utils.getSteamID()).."_spectator", spectating and "false" or "true")

							if(lobby_gamemode and game_in_progress)then
								in_game = true
								game_in_progress = true

								steam.matchmaking.setLobbyMemberData(lobby_code, "in_game", "true")
								
								gui_closed = true
				
								if(spectating)then
									mp_log:print("Checking if gamemode has spectate function")
									if(lobby_gamemode.spectate ~= nil)then
										mp_log:print("Starting gamemode in spectator mode")
										lobby_gamemode.spectate(lobby_code, true)
									elseif(lobby_gamemode.start ~= nil)then
										mp_log:print("Starting gamemode")
										lobby_gamemode.start(lobby_code, true)
									end
								else
									mp_log:print("Checking if gamemode has start function")
									if(lobby_gamemode.start ~= nil)then
										mp_log:print("Starting gamemode")
										lobby_gamemode.start(lobby_code, true)
									end
								end
							end
				

						else
							--steam.matchmaking.sendLobbyChatMsg(lobby_code, "spectate")
							steam_utils.send("spectate", {}, steam_utils.messageTypes.AllPlayers, lobby_code, true, true)
							
							is_awaiting_spectate = true

							delay.new(function()
								return steamutils.IsSpectator(lobby_code) ~= spectating
							end, function()
								is_awaiting_spectate = false
								if(lobby_gamemode and game_in_progress)then
									in_game = true

									steam.matchmaking.setLobbyMemberData(lobby_code, "in_game", "true")

									game_in_progress = true
									
									gui_closed = true
					
									if(spectating)then
										mp_log:print("Checking if gamemode has spectate function")
										if(lobby_gamemode.spectate ~= nil)then
											mp_log:print("Starting gamemode in spectator mode")
											lobby_gamemode.spectate(lobby_code, true)
										elseif(lobby_gamemode.start ~= nil)then
											mp_log:print("Starting gamemode")
											lobby_gamemode.start(lobby_code, true)
										end
									else
										mp_log:print("Checking if gamemode has start function")
										if(lobby_gamemode.start ~= nil)then
											mp_log:print("Starting gamemode")
											lobby_gamemode.start(lobby_code, true)
										end
									end
								end
							end)
						end
					end
					if(is_busy)then
						GuiTooltip(menu_gui, busy_reason, "")
					end
				end
				

				GuiText(menu_gui, 0, -6, " ")


				if(owner == steam_utils.getSteamID())then

					local hub_blocks_start = hub_state ~= nil
						and hub_state.settings
						and hub_state.settings.only_mods_can_start
						and not hub_is_owner_or_mod()

					local start_string = GameTextGetTranslatedOrNot("$mp_start_game")
					if(steam.matchmaking.getLobbyData(lobby_code, "in_progress") == "true")then
						start_string = GameTextGetTranslatedOrNot("$mp_restart_game")
					end

					if(hub_blocks_start)then
						GuiColorSetForNextWidget(menu_gui, 0.5, 0.5, 0.5, 1)
						GuiText(menu_gui, 0, 0, start_string)
						GuiTooltip(menu_gui, GameTextGetTranslatedOrNot("$hub_only_mods_start"), "")
					elseif(GuiButton(menu_gui, NewID("lobby_start_button"), 0, 0, start_string))then
						gui_closed = not gui_closed
						invite_menu_open = false

						local start_data = {}

						if(active_mode and active_mode.start_data)then
							start_data = active_mode.start_data(lobby_code)
						end

						if(steam.matchmaking.getLobbyData(lobby_code, "in_progress") == "true")then
							--steam.matchmaking.sendLobbyChatMsg(lobby_code, "restart")
							steam_utils.send("restart", start_data, steam_utils.messageTypes.AllPlayers, lobby_code, true, true, 0)
						else
							--steam.matchmaking.sendLobbyChatMsg(lobby_code, "start")
							steam_utils.send("start", start_data, steam_utils.messageTypes.AllPlayers, lobby_code, true, true, 0)
						end
						steam_utils.TrySetLobbyData(lobby_code, "in_progress", "true")
				end
				end

				spectating = steamutils.IsSpectator(lobby_code)

				--print(tostring(spectating))


				local custom_enter_check = true
				local custom_enter_string = ""
				if(active_mode and active_mode.custom_enter_check)then
					custom_enter_check, custom_enter_string = active_mode.custom_enter_check(lobby_code)
				end
				if(lobby_in_progress and not in_game)then
					if(custom_enter_check)then
						if GuiButton(menu_gui, NewID("lobby_enter_button"), 0, 0, GameTextGetTranslatedOrNot("$mp_enter_game")) then
							
							local active_mode = FindGamemode(steam.matchmaking.getLobbyData(lobby_code, "gamemode"))

							mp_log:print("Attempting to load into gamemode: "..(active_mode and active_mode.name or "UNKNOWN"))

							if(active_mode)then
								local lobby_data_count = steam.matchmaking.getLobbyDataCount(lobby_code)
								for i = 1, lobby_data_count do
									local data = steam.matchmaking.getLobbyDataByIndex(lobby_code, i -1 )
									
									if(cached_lobby_data[data.key] ~= data.value)then
										cached_lobby_data[data.key] = data.value
									end
									debug_log:print("Lobby Data: ["..tostring(data.key).."] = "..tostring(data.value))
								end

								in_game = true
								steam.matchmaking.setLobbyMemberData(lobby_code, "in_game", "true")

								game_in_progress = true
								
								gui_closed = true

								mp_log:print("Attempting to start gamemode")
								if(spectating)then
									mp_log:print("Checking if gamemode has spectate function")
									if(active_mode.spectate ~= nil)then
										mp_log:print("Starting gamemode in spectator mode")
										active_mode.spectate(lobby_code, true)
									elseif(active_mode.start ~= nil)then
										mp_log:print("Starting gamemode")
										active_mode.start(lobby_code, true)
									end
								else
									mp_log:print("Checking if gamemode has start function")
									if(active_mode.start ~= nil)then
										mp_log:print("Starting gamemode")
										active_mode.start(lobby_code, true)
									end
								end


							end
						end
					else
						GuiColorSetForNextWidget( menu_gui, 0.5, 0.5, 0.5, 1 )
						GuiText(menu_gui, 0, 0, GameTextGetTranslatedOrNot("$mp_enter_game"))
						GuiTooltip(menu_gui, custom_enter_string, "")
					end
				end


				if(active_mode ~= nil and active_mode.lobby_panel_header ~= nil)then
					active_mode.lobby_panel_header(lobby_code, menu_gui, function(...) return NewID(...) end)
				end

				GuiText(menu_gui, 2, 0, "--------------------")
				local players = steam_utils.getLobbyMembers(lobby_code, true)

				local player_list_items
				if active_mode ~= nil and active_mode.get_player_list_items ~= nil then
					player_list_items = active_mode.get_player_list_items(lobby_code, players)
				else
					player_list_items = players
				end

				for _, v in ipairs(player_list_items) do
					if v.type == "section_header" then
						GuiLayoutBeginHorizontal(menu_gui, 0, 0, true, 0, 0)
						if v.r or v.g or v.b then
							GuiColorSetForNextWidget(menu_gui, v.r or 1, v.g or 1, v.b or 1, 1)
						end
						GuiText(menu_gui, 2, 0, GameTextGetTranslatedOrNot(v.label or ""))
						for _, btn in ipairs(v.buttons or {}) do
							if GuiButton(menu_gui, NewID("section_hdr"), 2, 0, GameTextGetTranslatedOrNot(btn.label or "")) then
								if btn.on_click then btn.on_click() end
							end
						end
						GuiLayoutEnd(menu_gui)
						GuiText(menu_gui, 0, -6, " ")
						goto continue
					end

					GuiLayoutBeginHorizontal(menu_gui, 0, 0, true, 0, 0)
	
					local extra_x = v.indent or 0
					local alpha = 1
					if(v.is_spectator)then
						alpha = 0.5
						extra_x = 0
						GuiImage(menu_gui, NewID("lobby_player"), 0, 0, "mods/evaisa.mp/files/gfx/ui/spectator.png", 1, 1, 1, 0)
						GuiTooltip(menu_gui, GameTextGetTranslatedOrNot("$mp_spectator_hover"), "")
					end


					GuiImage(menu_gui, NewID("lobby_player"), extra_x, 0, steam_utils.getUserAvatar(v.id), alpha, 10 / 32, 10 / 32, 0)

					if(v.id ~= steam_utils.getSteamID() and owner == steam_utils.getSteamID())then
						if(GuiButton(menu_gui, NewID("lobby_player"), 2, 0, GameTextGetTranslatedOrNot("$mp_kick")))then
							steam.matchmaking.kickUserFromLobby(lobby_code, v.id, GameTextGetTranslatedOrNot("$mp_kick_notification"))
						end
						if(GuiButton(menu_gui, NewID("lobby_player"), 0, 0, GameTextGetTranslatedOrNot("$mp_ban")))then

							popup.create("ban_player_blacklist", GameTextGetTranslatedOrNot("$mp_blacklist_player"),
							{
								GameTextGetTranslatedOrNot("$mp_blacklist_player_description"),
								{
									text = GameTextGetTranslatedOrNot("$mp_blacklist_player_description_2"),
									color = {214 / 255, 60 / 255, 60 / 255, 1}
								},
							}, {
								{
									text = GameTextGetTranslatedOrNot("$mp_blacklist_player_option_1"),
									callback = function()
										steam.matchmaking.kickUserFromLobby(lobby_code, v.id, GameTextGetTranslatedOrNot("$mp_ban_notification"))	
										steam_utils.TrySetLobbyData(lobby_code, "banned_"..tostring(v.id), "true")
										banned_members[tostring(v.id)] = true
									end
								},
								{
									text = GameTextGetTranslatedOrNot("$mp_blacklist_player_option_2"),
									callback = function()
										steam.matchmaking.kickUserFromLobby(lobby_code, v.id, GameTextGetTranslatedOrNot("$mp_ban_notification"))	
										steam_utils.TrySetLobbyData(lobby_code, "banned_"..tostring(v.id), "true")
										banned_members[tostring(v.id)] = true
										steam_utils.BlacklistPlayer(v.id)
									end
								},
								{
									text = GameTextGetTranslatedOrNot("$mp_blacklist_player_option_3"),
									callback = function()
										-- nothing!!
									end
								}
							}, -6000)

							--[[
							steam.matchmaking.kickUserFromLobby(lobby_code, v.id, GameTextGetTranslatedOrNot("$mp_ban_notification"))	
							steam_utils.TrySetLobbyData(lobby_code, "banned_"..tostring(v.id), "true")
							banned_members[tostring(v.id)] = true
							]]

						end
						if(GuiButton(menu_gui, NewID("lobby_player"), 0, 0, GameTextGetTranslatedOrNot("$mp_owner")))then
							steam.matchmaking.setLobbyOwner(lobby_code, v.id)
							banned_members = {}
						end
					end
					
					if(v.id == owner)then
						GuiImage(menu_gui, NewID("lobby_player"), 2, -3, "mods/evaisa.mp/files/gfx/ui/crown.png", 1, 1, 1, 0)
						--selected_player
						if(selected_player == v.id)then
							GuiColorSetForNextWidget( menu_gui, 1, 1, 0.2, alpha )
						else
							GuiColorSetForNextWidget( menu_gui, 1, 1, 1, alpha )
						end
						if(GuiButton(menu_gui, NewID("lobby_player"), -5, 0, tostring(v.name)))then
							lobby_presets_open = false
							custom_menu_close_callback_right()
							active_lobby_menu_right = nil
							if(selected_player == v.id)then
								selected_player = nil
							else
								selected_player = v.id
							end
						end
					else
						if(selected_player == v.id)then
							GuiColorSetForNextWidget( menu_gui, 1, 1, 0.2, alpha )
						else
							GuiColorSetForNextWidget( menu_gui, 1, 1, 1,alpha )
						end

						if(GuiButton(menu_gui, NewID("lobby_player"), 2, 0, tostring(v.name)))then
							lobby_presets_open = false
							custom_menu_close_callback_right()
							active_lobby_menu_right = nil
							if(selected_player == v.id)then
								selected_player = nil
							else
								selected_player = v.id
							end
						end
					end

					--[[
					local player_mod_data = getLobbyUserData(lobby_code, v.id) or {}

					CustomTooltip(menu_gui, function() 
						for k, v in pairs(player_mod_data) do
							GuiColorSetForNextWidget( menu_gui, 1, 1, 1, 0.8 )
							GuiZSetForNextWidget(menu_gui, -5110)
							GuiText(menu_gui, 0, 0, v.name .. " ( "..v.id.." )")
						end
					end, -5100, 0, 0)
					]]
	
					GuiLayoutEnd(menu_gui)

					--GuiLayoutEnd(menu_gui)
					GuiText(menu_gui, 0, -6, " ")
					::continue::
				end
	
				--[[
				for i = 1, 40 do
					GuiText(menu_gui, 2, 0, " ")
				end
				]]

				if(active_mode ~= nil and active_mode.lobby_panel_footer ~= nil)then
					active_mode.lobby_panel_footer(lobby_code, menu_gui, function(...) return NewID(...) end)
				end

				GuiLayoutEnd(menu_gui)
			end, function() 
				gui_closed = true; 
				invite_menu_open = false 
			end, "lobby_gui")
		
			if(invite_menu_open)then

				friendfilters_ingame = friendfilters_ingame or false
				friendfilters_inlobby = friendfilters_inlobby or false
				friendfilters_offline = friendfilters_offline or false
				friendfilters_busy = friendfilters_busy or false
				friendfilters_away = friendfilters_away or false

				friends_cache = friends_cache or {
					friends = nil,
					state = {},
					game_info = {},
				}

				DrawWindow(menu_gui, -5500 ,((screen_width / 2) - (window_width / 2)) - (188 / 2) - 10, screen_height / 2, 188, window_height, "Friends", true, function()
					local do_update = GameGetFrameNum() % 60 == 0
					
					GuiLayoutBeginVertical(menu_gui, 0, 0, true, 0, 0)

					if(do_update or friends_cache.friends == nil)then
						friends_cache.friends = steamutils.getSteamFriends();
						friends_cache.state = {}
						friends_cache.game_info = {}
					end

					local friends = friends_cache.friends

					local only_ingame = GameTextGetTranslatedOrNot("$mp_invite_only_ingame")
					if(GuiButton(menu_gui, NewID("Invite"), 0, 0, friendfilters_ingame and "[X] "..only_ingame or "[ ] "..only_ingame))then
						friendfilters_ingame = not friendfilters_ingame
					end

					local show_in_lobby = GameTextGetTranslatedOrNot("$mp_invite_in_lobby")
					if(GuiButton(menu_gui, NewID("Invite"), 0, 0, friendfilters_inlobby and "[X] "..show_in_lobby or "[ ] "..show_in_lobby))then
						friendfilters_inlobby = not friendfilters_inlobby
					end

					local show_offline = GameTextGetTranslatedOrNot("$mp_invite_offline")
					if(GuiButton(menu_gui, NewID("Invite"), 0, 0, friendfilters_offline and "[X] "..show_offline or "[ ] "..show_offline))then
						friendfilters_offline = not friendfilters_offline
					end

					local show_busy = GameTextGetTranslatedOrNot("$mp_invite_busy")
					if(GuiButton(menu_gui, NewID("Invite"), 0, 0, friendfilters_busy and "[X] "..show_busy or "[ ] "..show_busy))then
						friendfilters_busy = not friendfilters_busy
					end

					local show_away = GameTextGetTranslatedOrNot("$mp_invite_away")
					if(GuiButton(menu_gui, NewID("Invite"), 0, 0, friendfilters_away and "[X] "..show_away or "[ ] "..show_away))then
						friendfilters_away = not friendfilters_away
					end

					GuiText(menu_gui, 2, 0, "--------------------")

					for k, v in pairs(friends)do
						local state = friends_cache.state[v.id] or steam.friends.getFriendPersonaState(v.id)
						local game_info = friends_cache.game_info[v.id] or steam.friends.getFriendGamePlayed(v.id)

						--[[
						local state = steam.friends.getFriendPersonaState(v.id)
						local game_info = steam.friends.getFriendGamePlayed(v.id)
						]]

						local online_filter_pass = state == 1 or (state == 0 and friendfilters_offline) or (state == 2 and friendfilters_busy) or (state == 3 and friendfilters_away) or (state == 4 and friendfilters_away)

						local ingame_filter_pass = (not game_info and not friendfilters_ingame) or (game_info and game_info.gameID ~= game_id and not friendfilters_ingame ) or (game_info and game_info.gameID == game_id)

						local inlobby_filter_pass = (not game_info) or (game_info and game_info.gameID ~= game_id) or (game_info and game_info.gameID == game_id and tostring(game_info.lobbyID) ~= "0" and friendfilters_inlobby) or (game_info and game_info.gameID == game_id and tostring(game_info.lobbyID) == "0")


						if(online_filter_pass and ingame_filter_pass and inlobby_filter_pass)then
							GuiLayoutBeginHorizontal(menu_gui, 0, 0, true, 0, 0)
							if(GuiButton(menu_gui, NewID("Invite"), 0, 0, GameTextGetTranslatedOrNot("$mp_invite").." "))then
								if(lobby_code ~= nil)then
									if(steam.matchmaking.inviteUserToLobby(lobby_code, v.id))then
										mp_log:print("Invited "..v.name.." to lobby")
									else
										mp_log:print("Failed to invite "..v.name.." to lobby")
									end
								end
							end
							GuiText(menu_gui, 2, 0, v.name)
							GuiLayoutEnd(menu_gui)
						end
					end

					for i = 1, 40 do
						--[[
						GuiText(menu_gui, 2, 0, " ")
						]]
					end
		
					GuiLayoutEnd(menu_gui)
				end, nil, "invite_gui", 2, 2, true)	
		
			end

			if(selected_player ~= nil)then
				local selected_player_name = steamutils.getTranslatedPersonaName(selected_player)

				local window_width, x_pos = GetMenuSettings("right")
				DrawWindow(menu_gui, -5500 ,x_pos, screen_height / 2, window_width, window_height, GameTextGetTranslatedOrNot("$mp_mods").." ("..selected_player_name..")", true, function()
					GuiLayoutBeginVertical(menu_gui, 0, 0, true, 0, 0)
					
					local player_mod_data = getLobbyUserData(lobby_code, selected_player) or {}

					local mod_count = 0
					
					-- Define a Lua function to sanitize a URL input
					function sanitize_url(url)
						-- Initialize an empty string to store the sanitized URL
						local sanitized_url = ""

						-- Check if the URL starts with "https://"
						if url:sub(1, 8) ~= "https://" then
							-- Inform user if the URL is not allowed
							mp_log:print("Invalid input URL: '"..url.."', Must start with 'https://'.")
							-- Return empty string
							return sanitized_url
						end

						-- Add "https://" to the sanitized URL
						sanitized_url = "https://"

						-- Iterate over each character in the input URL (starting from position 9, after "https://")
						for i = 9, #url do
							-- Extract the current character
							local char = url:sub(i, i)

							-- Check if the character is part of the whitelist (i.e., only alphanumeric, dash, underscore, period, colon, slash,
							-- question mark, equal sign, plus sign, ampersand, or percent sign)
							if char:match("[%w%-%_%.%:%/%?%=%+&%%]") then
								-- If the character is part of the whitelist, append it to the sanitized URL
								sanitized_url = sanitized_url .. char
							end
						end

						mp_log:print("Sanitized URL: " .. sanitized_url)

						-- Return the sanitized URL
						return sanitized_url
					end
										
	

					for k, v in pairs(player_mod_data) do
						local description_truncated = v.description

						-- remove anything after a /n (newline)
						local newline_pos = string.find(description_truncated, "\\n")
						if(newline_pos ~= nil)then
							description_truncated = description_truncated:sub(1, newline_pos - 1)
						end
						if(#description_truncated > 100)then
							description_truncated = description_truncated:sub(1, 100) .. "..."
						end

						GuiColorSetForNextWidget( menu_gui, 1, 1, 1, 0.8 )
						GuiZSetForNextWidget(menu_gui, -5510)
						--GamePrint(tostring(v.workshop_item_id))
						--GuiLayoutBeginHorizontal(menu_gui, 0, 0, true)

						if(v.workshop_item_id ~= 0 and v.workshop_item_id ~= "0")then
							if(GuiButton(menu_gui, NewID("mod_list"), 0, 0, v.name .. (v.id ~= nil and " ( "..v.id.." )" or "")))then
								--steam.utils.openWorkshopItem(v.workshop_item_id)
								popup.create("open_steam_url", v.name, GameTextGetTranslatedOrNot("$mp_open_steam_url_warning"), {
									{
										text="Yes", 
										callback = function() 
											os.execute("start steam://openurl/https://steamcommunity.com/sharedfiles/filedetails/?id="..v.workshop_item_id)
										end
									},
									{
										text="No", 
										callback = function() 
										end
									}
								}, -20000)

							end
							GuiTooltip(menu_gui, GameTextGetTranslatedOrNot("$mp_open_steam_url_tooltip"), description_truncated)
						elseif(v.download_link ~= nil and v.download_link ~= "")then
							if(GuiButton(menu_gui, NewID("mod_list"), 0, 0, v.name .. (v.id ~= nil and " ( "..v.id.." )" or "")))then
								--os.execute("start "..v.workshop_item_id)
								local url = sanitize_url(v.download_link)
								

								popup.create("open_mod_download_page", v.name, string.format(GameTextGetTranslatedOrNot("$mp_open_download_page_warning"), "\""..url.."\""), {
									{
										text="Yes", 
										callback = function() 
											os.execute("start explorer \""..url.."\"")
										end
									},
									{
										text="No", 
										callback = function() 
										end
									}
								}, -20000)

							end
							GuiTooltip(menu_gui, GameTextGetTranslatedOrNot("$mp_open_download_page_tooltip"),  description_truncated)
						else	
							GuiText(menu_gui, 0, 0, v.name .. (v.id ~= nil and " ( "..v.id.." )" or ""))
							GuiTooltip(menu_gui,  description_truncated, "")
						end

						local mod_required = (steam.matchmaking.getLobbyData(lobby_code, "mod_required_"..v.id) == "true") or false

						local required_text = mod_required and GameTextGetTranslatedOrNot("$mp_required") or GameTextGetTranslatedOrNot("$mp_not_required")

						GuiZSetForNextWidget(menu_gui, -5510)

						if(mod_required)then
							GuiColorSetForNextWidget( menu_gui, 1, 0.129, 0, 0.8 )
						else
							GuiColorSetForNextWidget( menu_gui, 0.314, 1, 0, 0.8 )
						end

						if(steamutils.IsOwner())then
							if(GuiButton(menu_gui, NewID("mod_list"), 0, 0, required_text))then
								steam_utils.TrySetLobbyData(lobby_code, "mod_required_"..v.id, tostring(not mod_required))
								if(not mod_required)then
									local required_mods = (steam.matchmaking.getLobbyData(lobby_code, "required_mods") ~= nil and steam.matchmaking.getLobbyData(lobby_code, "required_mods") ~= "") and bitser.loads(steam.matchmaking.getLobbyData(lobby_code, "required_mods")) or {}
								
									table.insert(required_mods, {v.id, v.name})

									steam_utils.TrySetLobbyData(lobby_code, "required_mods", bitser.dumps(required_mods))
								else
									local required_mods = (steam.matchmaking.getLobbyData(lobby_code, "required_mods") ~= nil and steam.matchmaking.getLobbyData(lobby_code, "required_mods") ~= "") and bitser.loads(steam.matchmaking.getLobbyData(lobby_code, "required_mods")) or {}
								
									for i, mod in ipairs(required_mods) do
										if(mod.id == v.id)then
											table.remove(required_mods, i)
											break
										end
									end

									steam_utils.TrySetLobbyData(lobby_code, "required_mods", bitser.dumps(required_mods))
								end
							end
						else
							GuiText(menu_gui, 0, 0, required_text)
						end


						GuiText(menu_gui, 0, -8, " ")

						mod_count = mod_count + 1
					end
					--GuiLayoutEnd(menu_gui)
					
					--[[
					for i = 1, 50 - mod_count do
						GuiText(menu_gui, 2, 0, " ")
					end
					]]
		
					GuiLayoutEnd(menu_gui)
				end, nil, "mod_list_gui")	
		
			end

			if(lobby_code == nil)then
				active_lobby_menu_right = nil
				active_lobby_menu_left = nil
			end

			if(active_lobby_menu_right ~= nil)then
				if(lobby_menus ~= nil)then
					for i, lobby_menu in ipairs(lobby_menus)do
						if(lobby_menu.id == active_lobby_menu_right)then

							local menu_width, pos_x = GetMenuSettings("right")

							DrawWindow(menu_gui, -5500 , pos_x, screen_height / 2, menu_width, window_height, GameTextGetTranslatedOrNot(lobby_menu.name), true, function(win_x, win_y, win_w, win_h)
								get_widget_info = function()
									local clicked, right_clicked, hovered, x, y, width, height, draw_x, draw_y, draw_width, draw_height = GuiGetPreviousWidgetInfo(menu_gui)
									local window_y = ((screen_height / 2) - (window_height / 2)) + 12
									local window_height = window_height
									
									--[[GuiLayoutBeginLayer(menu_gui)
									GuiText(menu_gui, 0, window_y, "------------------")
									GuiText(menu_gui, 0, window_y + window_height, "------------------")
									GuiLayoutEndLayer(menu_gui)]]

									local mouse_x, mouse_y = input:GetUIMousePos(menu_gui)

							

									if(mouse_x < win_x or mouse_x > win_x + win_w or mouse_y < win_y or mouse_y > win_y + win_h + 5)then
										hovered = false
										right_clicked = false
										clicked = false
									end

									return (y + height > window_y and y < window_y + window_height), clicked, right_clicked, hovered, x, y, width, height, draw_x, draw_y, draw_width, draw_height
								end
								if(lobby_menu.draw)then
									lobby_menu.draw(lobby_code, menu_gui, function(id, force) return NewID(id or lobby_menu.id, force) end)
								end
							end, function() 
								active_lobby_menu_right = nil
								lobby_menu.close() 
							end, lobby_menu.id, nil, nil, nil, true)	
						end
					end
				end
			end

			
			if(active_lobby_menu_left ~= nil)then
				if(lobby_menus ~= nil)then
					for i, lobby_menu in ipairs(lobby_menus)do
						if(lobby_menu.id == active_lobby_menu_left)then
							local menu_width, pos_x = GetMenuSettings("left")
							DrawWindow(menu_gui, -5500 , pos_x, screen_height / 2, menu_width, window_height, GameTextGetTranslatedOrNot(lobby_menu.name), true, function(win_x, win_y, win_w, win_h)
								get_widget_info = function()
									local clicked, right_clicked, hovered, x, y, width, height, draw_x, draw_y, draw_width, draw_height = GuiGetPreviousWidgetInfo(menu_gui)
									local window_y = ((screen_height / 2) - (window_height / 2)) + 12
									local window_height = window_height
									
									--[[GuiLayoutBeginLayer(menu_gui)
									GuiText(menu_gui, 0, window_y, "------------------")
									GuiText(menu_gui, 0, window_y + window_height, "------------------")
									GuiLayoutEndLayer(menu_gui)]]

									local mouse_x, mouse_y = input:GetUIMousePos(menu_gui)

							

									if(mouse_x < win_x or mouse_x > win_x + win_w or mouse_y < win_y or mouse_y > win_y + win_h + 5)then
										hovered = false
										right_clicked = false
										clicked = false
									end

									return (y + height > window_y and y < window_y + window_height), clicked, right_clicked, hovered, x, y, width, height, draw_x, draw_y, draw_width, draw_height
								end
								if(lobby_menu.draw)then
									lobby_menu.draw(lobby_code, menu_gui, function(id, force) return NewID(id or lobby_menu.id, force) end)
								end
							end, function() 
								active_lobby_menu_left = nil
								lobby_menu.close() 
							end, lobby_menu.id, nil, nil, nil, true)	
						end
					end
				end
			end

			--[[
			if(lobby_settings_open and lobby_code ~= nil)then
				
				local owner = steam.matchmaking.getLobbyOwner(lobby_code)

				local internal_types = { "Public", "Private", "FriendsOnly"}
				local internal_type_map = { Public = 1, Private = 2, FriendsOnly = 3 }


				edit_lobby_type = internal_type_map[steam_utils.GetLobbyData("LobbyType")]

				local active_mode = FindGamemode(steam_utils.GetLobbyData("gamemode"))
	
				local true_max = 32
	
				local default_max_players = 8

				edit_lobby_max_players = steam_utils.getSteamID() and (edit_lobby_max_players or steam.matchmaking.getLobbyMemberLimit(lobby_code)) or steam.matchmaking.getLobbyMemberLimit(lobby_code)

				edit_lobby_name = owner == steam_utils.getSteamID() and (edit_lobby_name or steam_utils.GetLobbyData("name"))  or steam_utils.GetLobbyData("name")

				edit_lobby_seed = owner == steam_utils.getSteamID() and (edit_lobby_seed or steam_utils.GetLobbyData("seed")) or steam_utils.GetLobbyData("seed")

				DrawWindow(menu_gui, -5500 ,((screen_width / 2) - (window_width / 2)) - (188 / 2) - 10, screen_height / 2, 188, window_height, GameTextGetTranslatedOrNot("$mp_lobby_settings"), true, function()
					local current_y = 0
					local box_w = 180

					-- Lobby Type Field
					local lobby_type_string = get_split_string(GameTextGetTranslatedOrNot("$mp_lobby_type")..": "..lobby_types[edit_lobby_type], 150)

					local chunks = select(2, lobby_type_string:gsub('\n', '\n'))

					local last_w, last_h = GuiGetTextDimensions(menu_gui, lobby_type_string)
					local box_h = last_h + (chunks <= 1 and 2 or 0)
					
					Gui9Piece(menu_gui, function() return NewID("EditLobby") end, 0, 0, box_w, box_h, 0.1, -5600, "mods/evaisa.mp/files/gfx/ui/9piece_white.xml", 3)

					if(GuiTextButton(menu_gui, function() return NewID("EditLobby") end, 4, 2, lobby_type_string, -5600, 1))then
						edit_lobby_type = edit_lobby_type + 1
						if(edit_lobby_type > #lobby_types and owner == steam_utils.getSteamID())then
							edit_lobby_type = 1
						end
						settings_changed = true
					end

					current_y = current_y + box_h + 2

					-- Lobby name field
					local lobby_name_string = GameTextGetTranslatedOrNot("$mp_lobby_name")..": "
					local last_w, last_h = GuiGetTextDimensions(menu_gui, lobby_name_string)
					local box_h = last_h + 18
					Gui9Piece(menu_gui, function() return NewID("EditLobby") end, 0, current_y, box_w, box_h, 0.1, -5600, "mods/evaisa.mp/files/gfx/ui/9piece_white.xml", 3)
					GuiText(menu_gui, 4, current_y + 2, lobby_name_string)
					name_change_frame = name_change_frame or nil
					local lobby_name_value = GuiTextInput(menu_gui, NewID("EditLobby"), 4, current_y + last_h + 2, edit_lobby_name, 156, 25, "qwertyuiopasdfghjklzxcvbnm1234567890QWERTYUIOPASDFGHJKLZXCVBNM!@#$%^&*()_' ")
					local _, _, hover = GuiGetPreviousWidgetInfo(menu_gui)
					
					if(hover)then
						GameAddFlagRun("chat_bind_disabled")
					end
					if(lobby_name_value ~= edit_lobby_name and owner == steam_utils.getSteamID())then
						edit_lobby_name = lobby_name_value
						name_change_frame = GameGetFrameNum()
					end
				
					if(name_change_frame and GameGetFrameNum() - name_change_frame > 30)then
						settings_changed = true
						name_change_frame = nil
					end

					current_y = current_y + box_h + 2

					-- lobby max players field
					local max_player_string = GameTextGetTranslatedOrNot("$mp_max_players")..": "
					local last_w, last_h = GuiGetTextDimensions(menu_gui, max_player_string)
					local box_h = last_h + 16
					Gui9Piece(menu_gui, function() return NewID("EditLobby") end, 0, current_y, box_w, box_h, 0.1, -5600, "mods/evaisa.mp/files/gfx/ui/9piece_white.xml", 3)
					GuiText(menu_gui, 4, current_y + 2, max_player_string)
					max_player_change_frame = max_player_change_frame or nil
					local slider_value = GuiSlider(menu_gui, NewID("EditLobby"), 2, current_y + last_h + 2, "", edit_lobby_max_players, 2, true_max, default_max_players, 1, " ", 146)
					
					GuiColorSetForNextWidget(menu_gui, 1, 1, 1, 0.7)
					local value_text = tostring(math.floor(slider_value))
					GuiText(menu_gui, 153, current_y + last_h + 1, value_text)
					
					if(slider_value ~= edit_lobby_max_players and owner == steam_utils.getSteamID())then
						edit_lobby_max_players = slider_value
						max_player_change_frame = GameGetFrameNum()
					end

					if(max_player_change_frame and GameGetFrameNum() - max_player_change_frame > 30)then
						settings_changed = true
						max_player_change_frame = nil
					end

					current_y = current_y + box_h + 2

					-- world seed field
					local seed_string = GameTextGetTranslatedOrNot("$mp_world_seed")..": "
					local last_w, last_h = GuiGetTextDimensions(menu_gui, seed_string)
					local box_h = last_h + 18
					Gui9Piece(menu_gui, function() return NewID("EditLobby") end, 0, current_y, box_w, box_h, 0.1, -5600, "mods/evaisa.mp/files/gfx/ui/9piece_white.xml", 3)
					GuiText(menu_gui, 4, current_y + 2, seed_string)
					seed_change_frame = seed_change_frame or nil
					local edit_lobby_seed_value = GuiTextInput(menu_gui, NewID("EditLobby"), 4, current_y + last_h + 2, edit_lobby_seed, 156, 25, "1234567890")
					local _, _, hover = GuiGetPreviousWidgetInfo(menu_gui)
					if(hover)then
						GameAddFlagRun("chat_bind_disabled")
					end
					if(edit_lobby_seed_value ~= edit_lobby_seed and owner == steam_utils.getSteamID())then
						edit_lobby_seed = edit_lobby_seed_value
						seed_change_frame = GameGetFrameNum()
					end
				
					if(seed_change_frame and GameGetFrameNum() - seed_change_frame > 30)then
						settings_changed = true
						seed_change_frame = nil
					end

					current_y = current_y + box_h + 2

					for k, setting in ipairs(active_mode.settings or {})do
						if(owner ~= steam_utils.getSteamID())then
							gamemode_settings[setting.id] = steam.matchmaking.getLobbyData(lobby_code, "setting_"..setting.id)
						end
				
						if(gamemode_settings[setting.id] == nil)then
							gamemode_settings[setting.id] = setting.default
							print("Setting "..setting.id.." to default: "..tostring(setting.default))
							--settings_changed = true
							--GlobalsSetValue("setting_next_"..setting.id, tostring(setting.default))
						else
							
							if(setting.type == "bool" and type(gamemode_settings[setting.id]) == "string")then
								if(gamemode_settings[setting.id] == "true")then
									gamemode_settings[setting.id] = true
								else
									gamemode_settings[setting.id] = false
								end
							elseif(setting.type == "slider" and type(gamemode_settings[setting.id]) == "string")then
								gamemode_settings[setting.id] = tonumber(gamemode_settings[setting.id])
							end
						end
				
						if(gamemode_settings[setting.id] ~= nil)then
							local setting_next = GlobalsGetValue("setting_next_"..setting.id)
							if(setting_next ~= nil)then
								if(setting_next ~= tostring(gamemode_settings[setting.id]))then
									GlobalsSetValue("setting_next_"..setting.id, tostring(gamemode_settings[setting.id]))
								end
							end
						end

						if(setting.require == nil or setting.require(setting))then
							--print(setting.id.."; "..tostring(setting.require).."; "..(setting.require and tostring(setting.require(setting)) or "nil"))
							if(setting.type == "enum")then
								local selected_name = ""
								local selected_index = nil
				
								local selected_value = gamemode_settings[setting.id]
								--print("Selected value: "..tostring(selected_value))
								if(selected_value == nil)then
									selected_value = setting.default
									gamemode_settings[setting.id] = setting.default
									settings_changed = true
								end
								
								for k, v in ipairs(setting.options)do
									if(v[1] == selected_value)then
										selected_name = v[2]
										selected_index = k
									end
								end
				
								-- if selected index is nil, reset to default
								if(selected_index == nil)then
									for k, v in ipairs(setting.options)do
										if(v[1] == setting.default)then
											selected_name = v[2]
											selected_index = k
											settings_changed = true
											gamemode_settings[setting.id] = setting.default
										end
									end
								end

								local enum_string = get_split_string(GameTextGetTranslatedOrNot(setting.name or "")..": "..GameTextGetTranslatedOrNot(selected_name or ""), 150)
								local chunks = select(2, enum_string:gsub('\n', '\n'))
								local last_w, last_h = GuiGetTextDimensions(menu_gui, enum_string)
								local box_h = last_h + (chunks <= 1 and 2 or 0)

								Gui9Piece(menu_gui, function() return NewID("EditLobby") end, 0, current_y, box_w, box_h, 0.1, -5600, "mods/evaisa.mp/files/gfx/ui/9piece_white.xml", 3)
								if(setting.options[selected_index][3] ~= nil)then
									local info = setting.options[selected_index][3]
									local info_name = "???"
									local info_desc = ""
									if(type(info) == "function")then
										info_name, info_desc = info()
									elseif(type(info) == "table")then
										info_name, info_desc = info[1], info[2]
									else
										info_name = info
									end
				
									if(info_name ~= nil)then
										GuiColorSetForNextWidget( menu_gui, 1, 0.4, 0.4, 1.0 )
										GuiText(menu_gui, 0, 0, "[?]")
										GuiTooltip(menu_gui, GameTextGetTranslatedOrNot(info_name or ""), GameTextGetTranslatedOrNot(info_desc or ""))
									end
								end
								
								if(GuiTextButton(menu_gui, function() return NewID("EditLobby") end, 4, current_y + 2, enum_string, -5600, 1, nil, nil, nil, nil, nil, function() GuiTooltip(menu_gui, GameTextGetTranslatedOrNot(setting.name or ""), GameTextGetTranslatedOrNot(setting.description or "")) end))then
									selected_index = selected_index + 1
									if(selected_index > #setting.options)then
										selected_index = 1
									end
									gamemode_settings[setting.id] = setting.options[selected_index][1]
									settings_changed = true
								end

								

								current_y = current_y + box_h + 2
							elseif(setting.type == "bool")then
								local bool_string = get_split_string(GameTextGetTranslatedOrNot(setting.name or "")..":"..(gamemode_settings[setting.id] and GameTextGetTranslatedOrNot("$mp_setting_enabled") or GameTextGetTranslatedOrNot("$mp_setting_disabled")), 170)
								local chunks = select(2, bool_string:gsub('\n', '\n'))
								local last_w, last_h = GuiGetTextDimensions(menu_gui, bool_string)
								local box_h = last_h + (chunks <= 1 and 2 or 0)
								Gui9Piece(menu_gui, function() return NewID("EditLobby") end, 0, current_y, box_w, box_h, 0.1, -5600, "mods/evaisa.mp/files/gfx/ui/9piece_white.xml", 3)
								
								local r, g, b, a = 1, 1, 1, 1

								-- split bool string by :
								local str1, str2 = bool_string:match("([^,]+:)([^,]+)")
								
								if(gamemode_settings[setting.id])then
									r, g, b, a = 0.4, 1, 0.4, 1
								else
									r, g, b, a = 1, 0.4, 0.4, 1
								end
								

								if(GuiTextButton(menu_gui, function() return NewID("EditLobby") end, 4, current_y + 2, {
									{
										text = str1,
										color = {1, 1, 1, 1}
									},
									{
										text = str2,
										color = {r, g, b, a}
									}
								}, -5600, 1, r, g, b, a, 170, function() GuiTooltip(menu_gui, GameTextGetTranslatedOrNot(setting.name or ""), GameTextGetTranslatedOrNot(setting.description or "")) end))then
									gamemode_settings[setting.id] = not gamemode_settings[setting.id]
									settings_changed = true
								end
								GuiTooltip(menu_gui, GameTextGetTranslatedOrNot(setting.name or ""), GameTextGetTranslatedOrNot(setting.description or ""))
								current_y = current_y + box_h + 2
							elseif(setting.type == "slider")then

								setting.display_multiplier = setting.display_multiplier or 1
								setting.formatting_string = setting.formatting_string or " $0"
								setting.formatting_func = setting.formatting_func or function(value) return value end
								setting.modifier = setting.modifier

								if(setting.modifier == nil)then
									setting.modifier = function(value) return value end
								end

								setting.display_fractions = setting.display_fractions or false
								
								local slider_string = get_split_string(GameTextGetTranslatedOrNot(setting.name or "")..": ", 150)

								local chunks = select(2, slider_string:gsub('\n', '\n'))

								local last_w, last_h = GuiGetTextDimensions(menu_gui, slider_string)
								local box_h = last_h + 16
								Gui9Piece(menu_gui, function() return NewID("EditLobby") end, 0, current_y, box_w, box_h, 0.1, -5600, "mods/evaisa.mp/files/gfx/ui/9piece_white.xml", 3)
								GuiTextMultiline(menu_gui, 4, current_y + 2, slider_string, -5600, 1, 1, 1, 1, 1, 170, function() GuiTooltip(menu_gui, GameTextGetTranslatedOrNot(setting.name), GameTextGetTranslatedOrNot(setting.description)) end)
								

								local slider_value = GuiSlider(menu_gui, NewID("EditLobby"), 2, current_y + last_h + 2, "", gamemode_settings[setting.id], setting.min, setting.max, setting.default, setting.display_multiplier, " ", 146)
								slider_value = setting.modifier(slider_value)
								local clicked, _, hovered = GuiGetPreviousWidgetInfo(menu_gui)
								GuiTooltip(menu_gui, GameTextGetTranslatedOrNot(setting.name), GameTextGetTranslatedOrNot(setting.description))

								-- take setting.formatting_string, replace $0 with slider_value, take display multiplier into account
								GuiColorSetForNextWidget(menu_gui, 1, 1, 1, 0.7)
								local value_text = string.gsub(setting.formatting_string, "$0", tostring(setting.display_fractions and (slider_value * setting.display_multiplier) or math.floor(slider_value * setting.display_multiplier)))
								value_text = setting.formatting_func(value_text)
								GuiText(menu_gui, 150, current_y + last_h + 1, value_text)

								was_slider_changed = was_slider_changed or {}

								if(tostring(slider_value) ~= tostring(gamemode_settings[setting.id]))then
				
									gamemode_settings[setting.id] = slider_value
									was_slider_changed[setting.id] = GameGetFrameNum()
								end
				
								if(was_slider_changed[setting.id] and (GameGetFrameNum() - was_slider_changed[setting.id]) > 30)then
								
									settings_changed = true
									was_slider_changed[setting.id] = nil
				
									--GlobalsSetValue("setting_next_"..setting.id, tostring(gamemode_settings[setting.id]))
								end
				
								current_y = current_y + box_h + 2
							elseif(setting.type == "custom")then
								if(setting.draw ~= nil)then
									local drew_h = setting.draw(lobby_code, menu_gui, function() return NewID("EditLobby") end, current_y, box_w) or 0
									current_y = current_y + drew_h
								end
							end
						end

						if(settings_changed and owner == steam_utils.getSteamID())then
							steam.matchmaking.setLobbyMemberLimit(lobby_code, edit_lobby_max_players)
							steam_utils.TrySetLobbyData(code, "max_players", tostring(edit_lobby_max_players))
							steam_utils.TrySetLobbyData(lobby_code, "name", edit_lobby_name)
							
							steam_utils.TrySetLobbyData(lobby_code, "seed", edit_lobby_seed)
							for k, setting in ipairs(active_mode.settings or  {})do
								steam_utils.TrySetLobbyData(lobby_code, "setting_"..setting.id, tostring(gamemode_settings[setting.id]))
								mp_log:print("Updated gamemode setting: "..setting.id.." to "..tostring(gamemode_settings[setting.id]))
							end
							print("Updating lobby type: "..internal_types[edit_lobby_type])
							steam.matchmaking.setLobbyType(lobby_code, internal_types[edit_lobby_type])
							steam_utils.send("refresh", {}, steam_utils.messageTypes.AllPlayers, lobby_code, true, true)
							mp_log:print("Updated limit: "..tostring(edit_lobby_max_players))
							mp_log:print("Updated name: "..tostring(edit_lobby_name))
							mp_log:print("Updated type: "..tostring(internal_types[edit_lobby_type]))
							settings_changed = false
							if(active_mode and active_mode.refresh)then
								active_mode.refresh(lobby_code)
							end
							--print("lobby settings changed!")
						end				

					end

					
				end, nil, "lobby_settings_gui", 2, 2, true)	
			
			end]]
		end
	},
	{
		name = "CreateLobby",
		func = function()


			local window_width = 200
			local window_height = 180
		
			local window_text = GameTextGetTranslatedOrNot("$mp_create_lobby")

			lobby_type = lobby_type or 1
			gamemode_index = gamemode_index or 1

			local true_max = 250

			local default_max_players = 8

			lobby_max_players = lobby_max_players or default_max_players

			local default_lobby_name = steamutils.getTranslatedPersonaName(steam_utils.getSteamID())

			-- if default lobby name ends with "s" add ' otherwise add 's

			if(string.sub(default_lobby_name, -1) == "s")then
				default_lobby_name = string.format(GameTextGetTranslatedOrNot("$mp_default_lobby_name_s"), default_lobby_name)
			else
				default_lobby_name = string.format(GameTextGetTranslatedOrNot("$mp_default_lobby_name"), default_lobby_name)
			end

			lobby_name = lobby_name or default_lobby_name
			lobby_seed = lobby_seed or tostring(rand.range(1, 4294967295))

			DrawWindow(menu_gui, -6000, screen_width / 2, screen_height / 2, window_width, window_height, window_text, true, function()
				GuiLayoutBeginVertical(menu_gui, 0, 0, true, 0, 0)

				if(GuiButton(menu_gui, NewID("CreateLobby"), 0, 0, GameTextGetTranslatedOrNot("$mp_return_menu")))then
					if(lobby_code ~= nil)then
						steam_utils.Leave(lobby_code)
						lobby_code = nil
					end
					invite_menu_open = false
					selected_player = nil
					menu_status = status.main_menu
					initial_refreshes = 10
					return
				end

				GuiText(menu_gui, 2, 0, "--------------------")
				GuiText(menu_gui, 2, 0, " ")


				if(#gamemodes > 0)then

					local internal_types = { "Public", "Private", "FriendsOnly",}

					if(GuiButton(menu_gui, NewID("CreateLobby"), 2, 0, GameTextGetTranslatedOrNot("$mp_lobby_type")..": "..lobby_types[lobby_type]))then
						lobby_type = lobby_type + 1
						if(lobby_type > #lobby_types)then
							lobby_type = 1
						end
					end


					--[[if(GuiButton(menu_gui, NewID("CreateLobby"), 2, 1, GameTextGetTranslatedOrNot("$mp_gamemode")..": "..GameTextGetTranslatedOrNot(gamemodes[gamemode_index].name)))then
						gamemode_index = gamemode_index + 1
						if(gamemode_index > #gamemodes)then
							gamemode_index = 1
						end
					end]]

					GuiLayoutBeginHorizontal(menu_gui, 0, 0, true, 0, 0)
					GuiText(menu_gui, 2, 1, GameTextGetTranslatedOrNot("$mp_lobby_name")..": ")
					local lobby_name_value = GuiTextInput(menu_gui, NewID("CreateLobby"), 2, 1, lobby_name, 120, 25, "qwertyuiopasdfghjklzxcvbnm1234567890QWERTYUIOPASDFGHJKLZXCVBNM!@#$%^&*()_' ")
					if(lobby_name_value ~= lobby_name)then
						lobby_name = lobby_name_value
					end
					GuiLayoutEnd(menu_gui)
					
					GuiLayoutBeginHorizontal(menu_gui, 0, 0, true, 0, 0)
					GuiText(menu_gui, 2, 3, GameTextGetTranslatedOrNot("$mp_max_players")..": ")
					local slider_value = GuiSlider(menu_gui, NewID("CreateLobby"), 0, 4, "", lobby_max_players, 2, true_max, default_max_players, 1, " $0", 120)
					if(slider_value ~= lobby_max_players)then
						lobby_max_players = slider_value
					end
					GuiLayoutEnd(menu_gui)

					GuiLayoutBeginHorizontal(menu_gui, 0, 0, true, 0, 0)
					GuiText(menu_gui, 2, 4, GameTextGetTranslatedOrNot("$mp_world_seed")..": ")
					local lobby_seed_value = GuiTextInput(menu_gui, NewID("CreateLobby"), 2, 4, lobby_seed, 120, 10, "1234567890")
					if(lobby_seed_value ~= lobby_seed)then
						lobby_seed = lobby_seed_value
					end
					GuiLayoutEnd(menu_gui)

					GuiText(menu_gui, 2, 0, " ")

					if(GuiButton(menu_gui, NewID("CreateLobby"), 2, 0, GameTextGetTranslatedOrNot("$mp_create_lobby")))then
						CreateLobby(internal_types[lobby_type], lobby_max_players, function (code) 
							msg.log("Created new lobby!")
							print("Created new lobby!")

							for k, setting in ipairs(gamemodes[gamemode_index].settings or {})do
								if(gamemode_settings[setting.id] == nil)then
									gamemode_settings[setting.id] = setting.default

									steam_utils.TrySetLobbyData(code, "setting_"..setting.id, tostring(setting.default))
								end
							end

							for k, data in pairs(gamemodes[gamemode_index].default_data or {})do
								steam_utils.TrySetLobbyData(code, k, data)
							end

							print("Setting all lobby data.")

							steam_utils.TrySetLobbyData(code, "name", lobby_name)
							steam_utils.TrySetLobbyData(code, "gamemode", tostring(gamemodes[gamemode_index].id))
							steam_utils.TrySetLobbyData(code, "gamemode_version", tostring(gamemodes[gamemode_index].version))
							steam_utils.TrySetLobbyData(code, "game_version_hash", tostring(noita_version_hash))
							steam_utils.TrySetLobbyData(code, "game_version", tostring(noita_version))
							steam_utils.TrySetLobbyData(code, "gamemode_name", tostring(gamemodes[gamemode_index].name))
							steam_utils.TrySetLobbyData(code, "seed", lobby_seed)
							steam_utils.TrySetLobbyData(code, "version", tostring(MP_VERSION))
							steam_utils.TrySetLobbyData(code, "in_progress", "false")
							steam_utils.TrySetLobbyData(code, "allow_in_progress_joining", gamemodes[gamemode_index].allow_in_progress_joining ~= nil and tostring(gamemodes[gamemode_index].allow_in_progress_joining)  or "true")
							steam_utils.TrySetLobbyData(code, "max_players", tostring(lobby_max_players))

							edit_lobby_type = lobby_type -- steam.matchmaking.getLobbyData(code, "LobbyType")
							edit_lobby_max_players = lobby_max_players  --  steam.matchmaking.getLobbyMemberLimit(code)"MaxPlayers"
							edit_lobby_name = lobby_name -- steam.matchmaking.getLobbyData(code, "name")
							edit_lobby_seed = lobby_seed -- steam.matchmaking.getLobbyData(code, "seed")
			

							if(dev_mode)then
								steam_utils.TrySetLobbyData(code, "System", "NoitaOnlineDev")
							end

							steam.friends.setRichPresence( "status", "Noita Online || "..tostring(gamemodes[gamemode_index].name).." - Waiting for players" )
							steam.friends.setRichPresence( "steam_player_group", lobby_name )
							steam.friends.setRichPresence( "steam_player_group_size", "1" )
							--steam.friends.setRichPresence( "connect", "lobby:"..code )
							
							lobby_code = code

							local blacklisted_players = steam_utils.GetBlacklistedPlayers()
							for i, player in ipairs(blacklisted_players)do
								steam_utils.TrySetLobbyData(lobby_code, "banned_"..tostring(player), "true")
								banned_members[tostring(player)] = true
							end
						end)
					end
				else
					GuiText(menu_gui, 2, 0, GameTextGetTranslatedOrNot("$mp_no_gamemodes"))
				end

				--[[
				for i = 1, 40 do
					GuiText(menu_gui, 2, 0, " ")
				end
				]]

				GuiLayoutEnd(menu_gui)
			end, function() 
				gui_closed = true; 
				invite_menu_open = false
				selected_player = nil 
			end, "create_lobby_gui")

		end
	},
	{
		name = "JoinLobby",
		func = function()


			local window_width = 200
			local window_height = 180
		
			local window_text = GameTextGetTranslatedOrNot("$mp_join_lobby")

			lobby_code_input = lobby_code_input or ""



			DrawWindow(menu_gui, -6000, screen_width / 2, screen_height / 2, window_width, window_height, window_text, true, function()
				GuiLayoutBeginVertical(menu_gui, 0, 0, true, 0, 0)

				if(GuiButton(menu_gui, NewID("JoinLobby"), 0, 0, GameTextGetTranslatedOrNot("$mp_return_menu")))then
					if(lobby_code ~= nil)then
						steam_utils.Leave(lobby_code)
						lobby_code = nil
					end
					invite_menu_open = false
					lobby_code_input = ""
					menu_status = status.main_menu
					initial_refreshes = 10
					return
				end

				GuiText(menu_gui, 2, 0, "--------------------")
				

				if(GuiButton(menu_gui, NewID("JoinLobby"), 2, 0, GameTextGetTranslatedOrNot("$mp_paste_code")))then
					-- Check if code only contains capital letters and is 25 characters or less
					local code = steam.utils.getClipboard()

					-- toupper
					code = code:upper()

					if(code ~= nil and code:match("^[%u]+$") and #code <= 25)then
						lobby_code_input = code
					end

				end

				GuiLayoutBeginHorizontal(menu_gui, 0, 0, true, 0, 0)
				GuiText(menu_gui, 2, 1, GameTextGetTranslatedOrNot("$mp_lobby_code")..": ")

				local real_code = lobby_code_input

				local censored_code = ""

				if(ModSettingGet("evaisa.mp.hide_lobby_code"))then
		
					

					for i = 1, #real_code do
						censored_code = censored_code.."*"
					end
				else
					censored_code = real_code
				end

				lobby_code_input = GuiTextInput(menu_gui, NewID("JoinLobby"), 2, 1, censored_code, 120, 25, "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")

				if(ModSettingGet("evaisa.mp.hide_lobby_code"))then
					-- uncensor new input by merging it with the real code
					if(#lobby_code_input < #real_code)then
						lobby_code_input = real_code:sub(1, #lobby_code_input)
					elseif(#lobby_code_input > #real_code)then
						-- take new characters from lobby_code_input and merge them with real_code
						local extra = lobby_code_input:sub(#real_code + 1)
						lobby_code_input = real_code..extra
					else
						lobby_code_input = real_code
					end
				end

				-- touppercase the input
				lobby_code_input = lobby_code_input:upper()
				


				--[[if(lobby_code_input ~= lobby_code_value)then
					lobby_code_input = lobby_code_value
				end]]

				--[[
				lobby_code_box = lobby_code_box or text_input.create(chat_gui, 2, screen_height - 16, window_width + 2, "", 100, nil, ";", 0)

				lobby_code_input = lobby_code_input or ""
				
				lobby_code_box.text = lobby_code_input
				lobby_code_box:transform(2, screen_height - 16, window_width + 2)

				lobby_code_box:update()

				lobby_code_box:draw()
		
		
				lobby_code_input = lobby_code_box.text
				]]


				GuiLayoutEnd(menu_gui)
				

				GuiText(menu_gui, 2, 0, " ")

				if(GuiButton(menu_gui, NewID("JoinLobby"), 2, 0, GameTextGetTranslatedOrNot("$mp_join_lobby")))then
					if(lobby_code_input ~= "" and #lobby_code_input > 5)then
						lobby_code_decompressed = steam.utils.decompressSteamID(lobby_code_input)
						steam.matchmaking.joinLobby(lobby_code_decompressed, function(data)
							if(data.response == 2)then
								steam_utils.Leave(data.lobbyID)
								invite_menu_open = false
								selected_player = nil
								menu_status = status.joining_lobby
								show_lobby_code = false
								lobby_code = nil
							end
						end)
					end
					lobby_code_input = ""
				end
	
				--[[
				for i = 1, 40 do
					GuiText(menu_gui, 2, 0, " ")
				end
				]]

				GuiLayoutEnd(menu_gui)
			end, function() 
				gui_closed = true; 
				invite_menu_open = false 
				selected_player = nil
			end, "join_lobby_gui")

		end
	},
	{
		name = "Disconnected",
		func = function()
			local window_width = 200
			local window_height = 180
		
			local window_text = GameTextGetTranslatedOrNot("$mp_disconnected")

			lobby_code_input = lobby_code_input or ""



			DrawWindow(menu_gui, -6000, screen_width / 2, screen_height / 2, window_width, window_height, window_text, true, function()
				GuiLayoutBeginVertical(menu_gui, 0, 0, true, 0, 0)
				if(GuiButton(menu_gui, NewID("JoinLobby"), 0, 0, GameTextGetTranslatedOrNot("$mp_return_menu")))then
					if(lobby_code ~= nil)then
						steam_utils.Leave(lobby_code)
						lobby_code = nil
					end
					invite_menu_open = false
					selected_player = nil
					lobby_code_input = ""
					menu_status = status.main_menu
					initial_refreshes = 10
					return
				end

				GuiText(menu_gui, 2, 0, "--------------------")
				GuiText(menu_gui, 2, 0, " ")

				GuiText(menu_gui, 2, 0, GameTextGetTranslatedOrNot("$mp_disconnected"))
				GuiText(menu_gui, 2, 0, GameTextGetTranslatedOrNot("$mp_reason")..": "..disconnect_message)

				--[[
				for i = 1, 40 do
					GuiText(menu_gui, 2, 0, " ")
				end
				]]

				GuiLayoutEnd(menu_gui)
			end, function() 
				gui_closed = true; 
				invite_menu_open = false 
				selected_player = nil
			end, "disconnected_gui")
		end
	}
}

GuiZSetForNextWidget(menu_gui, 0)
if (GameGetIsGamepadConnected()) then
	GuiOptionsAddForNextWidget(menu_gui, GUI_OPTION.NonInteractive)
end

if (not IsPaused()) then
	if (not GameHasFlagRun("chat_input_hovered")) then
		if ((bindings:IsJustDown("lobby_menu_open_kb") or bindings:IsJustDown("lobby_menu_open_gp")) and not GameHasFlagRun("chat_bind_disabled")) then
			gui_closed = not gui_closed
			invite_menu_open = false
			selected_player = nil
			GamePlaySound("data/audio/Desktop/ui.bank", "ui/button_click", 0, 0)
		end
	end

	if(GuiImageButton(menu_gui, NewID("MenuButton"), screen_width - 20, screen_height - 20, "", "mods/evaisa.mp/files/gfx/ui/menu.png"))then
		gui_closed = not gui_closed
		invite_menu_open = false 
		selected_player = nil
		GamePlaySound("data/audio/Desktop/ui.bank", "ui/button_click", 0, 0)
	end

	if(not gui_closed)then
		local version_string = "Noita Online (build "..tostring(MP_VERSION).." "..GameTextGetTranslatedOrNot(VERSION_FLAVOR_TEXT)..")"
		if(lobby_code ~= nil)then
			local active_mode = FindGamemode(steam.matchmaking.getLobbyData(lobby_code, "gamemode"))
			if(active_mode ~= nil)then
				version_string = version_string.." - "..GameTextGetTranslatedOrNot(active_mode.name or "").." (build "..tostring(active_mode.version or "").." "..GameTextGetTranslatedOrNot(active_mode.version_flavor_text or "")..")"
				if(active_mode.version_display)then
					version_string = active_mode.version_display(version_string)
				end
			end
		end
		local text_width, text_height = GuiGetTextDimensions(menu_gui, version_string)
		GuiZSetForNextWidget(menu_gui, 100)
		GuiText(menu_gui, screen_width / 2 - text_width / 2, screen_height - text_height, version_string)
		--print(version_string)
		if windows[menu_status] then
			windows[menu_status].func()
		end
	end
end
