dofile("data/scripts/lib/mod_settings.lua")



local mod_id = "evaisa.mp" -- This should match the name of your mod's folder.
mod_settings_version = 1   -- This is a magic global that can be used to migrate settings to new mod versions. call mod_settings_get_version() before mod_settings_update() to get the old value.
mod_settings =
{

	--[[{
		id = "artificial_lag",
		ui_name = "Artificial Lag",
		ui_description = "Adds a delay to all network traffic. Useful for testing network code.",
		value_default = 1,
		value_min = 1,
		value_max = 60,
		value_display_multiplier = 1,
		value_display_formatting = " $0",
		scope = MOD_SETTING_SCOPE_RUNTIME,
	},]]
	{
		id = "hide_lobby_code",
		ui_name = "Hide Lobby Code",
		ui_description = "Censor lobby code in join lobby menu.",
		value_default = false,
		scope = MOD_SETTING_SCOPE_RUNTIME,
	},
	{
		id = "presets_as_json",
		ui_name = "Presets as JSON",
		ui_description = "Save presets as plain text JSON files.\nThis allows you to edit presets outside of the game. \nIssues caused by doing so will not be supported.",
		value_default = false,
		scope = MOD_SETTING_SCOPE_RUNTIME,
	},
	{
		id = "streamer_mode",
		ui_name = "Streamer Mode",
		ui_description = "Disable avatars and other stuff.",
		value_default = false,
		scope = MOD_SETTING_SCOPE_RUNTIME,
	},
	{
		id = "streamer_mode_detection",
		ui_name = "Streaming App Detection",
		ui_description = "Show popup asking if you want to enable streamer mode if a streaming app is detected, and streamer mode is disabled.",
		value_default = true,
		scope = MOD_SETTING_SCOPE_RUNTIME,
	},
	{
		id = "flip_chat_direction",
		ui_name = "Flip chat direction",
		ui_description = "Make new messages appear on the top of the chat box.",
		value_default = false,
		scope = MOD_SETTING_SCOPE_RUNTIME,
	},
	{
		id = "profiler_rate",
		ui_name = "Profiler Rate",
		ui_description = "The rate at which the debugging profiler runs, in frames.",
		value_default = 1,
		value_min = 1,
		value_max = 300,
		value_display_multiplier = 1,
		value_display_formatting = " $0",
		scope = MOD_SETTING_SCOPE_RUNTIME,
	},
	{
		category_id = "keybinds",
		ui_name = "Keybindings",
		ui_description = "You can edit keybinds here.",
		foldable = true,
		_folded = true,
		settings = {
		}
	},
	{
		category_id = "voicechat",
		ui_name = "Voice Chat",
		ui_description = "Configure voice chat settings.",
		foldable = true,
		_folded = true,
		settings = {
			{
				id = "voicechat_enabled",
				ui_name = "Enable Voice Chat",
				ui_description = "Enable proximity voice chat.",
				value_default = true,
				scope = MOD_SETTING_SCOPE_RUNTIME,
			},
			{
				id = "voicechat_volume",
				ui_name = "Voice Chat Volume",
				ui_description = "Global volume multiplier for received voice chat.",
				value_default = 1.0,
				value_min = 0.0,
				value_max = 2.0,
				value_display_multiplier = 100,
				value_display_formatting = " $0%",
				scope = MOD_SETTING_SCOPE_RUNTIME,
			},
			{
				id = "voicechat_mic_volume",
				ui_name = "Microphone Volume",
				ui_description = "Amplify or reduce your microphone output volume.",
				value_default = 1.0,
				value_min = 0.0,
				value_max = 2.0,
				value_display_multiplier = 100,
				value_display_formatting = " $0%",
				scope = MOD_SETTING_SCOPE_RUNTIME,
			},
			{
				id = "voicechat_vad_mode",
				ui_name = "Voice Activation",
				ui_description = "Use voice activation instead of push-to-talk.\nWhen enabled, your mic activates automatically when you speak.",
				value_default = false,
				scope = MOD_SETTING_SCOPE_RUNTIME,
			},
			{
				id = "voicechat_vad_threshold",
				ui_name = "Activation Threshold",
				ui_description = "How loud you need to speak to trigger voice activation.\nLower = more sensitive.",
				value_default = 0.01,
				value_min = 0,
				value_max = 0.1,
				value_display_multiplier = 1000,
				value_display_formatting = " $0%",
				scope = MOD_SETTING_SCOPE_RUNTIME,
			},
		}
	}

}

local bindings = nil

function ModSettingsUpdate(init_scope)
	local old_version = mod_settings_get_version(mod_id)
	mod_settings_update(mod_id, mod_settings, init_scope)


end


function settings_count( mod_id, settings )
	local result = 0

	for i,setting in ipairs(settings) do
		if setting.category_id ~= nil then
			local visible = not setting._folded
			if visible then
				result = result + settings_count( mod_id, setting.settings )
			end
		else
			local visible = not setting.hidden or setting.hidden == nil
			if visible then
				result = result + 1
			end
		end
	end

	return result
end

function ModSettingsGuiCount()
	local count = settings_count(mod_id, mod_settings)
	--print("settings count: " .. count)
	return count
end


function mod_setting_button( mod_id, gui, in_main_menu, im_id, setting )
	local value = setting.handler_callback( mod_id, setting )

	if(value == "[Unbound]")then
		GuiColorSetForNextWidget( gui, 0.5, 0.5, 0.5, 1 )
	end

	local text = setting.ui_name .. ": " .. value

	local clicked,right_clicked = GuiButton( gui, im_id, mod_setting_group_x_offset, 0, text )
	if clicked then
		setting.clicked_callback( mod_id, setting, value )
	end
	if right_clicked then
		setting.right_clicked_callback( mod_id, setting, value )
	end

	mod_setting_tooltip( mod_id, gui, in_main_menu, setting )
end


local function ToID (str)
	str = str:gsub("[^%w]", "_")
	-- lowercase
	str = str:lower()
	return str
end

local old_mod_setting_title = mod_setting_title
mod_setting_title = function ( mod_id, gui, in_main_menu, im_id, setting )
	if(setting.color)then
		GuiColorSetForNextWidget( gui, setting.color[1], setting.color[2], setting.color[3], setting.color[4] )
	end
	old_mod_setting_title(mod_id, gui, in_main_menu, im_id, setting)
end

mod_setting_number = function( mod_id, gui, in_main_menu, im_id, setting )
	local value = ModSettingGetNextValue( mod_setting_get_id(mod_id,setting) )
	if type(value) ~= "number" then value = setting.value_default or 0.0 end

	local value_new = GuiSlider( gui, im_id, mod_setting_group_x_offset, 0, setting.ui_name, value, setting.value_min, setting.value_max, setting.value_default, setting.value_display_multiplier or 1, setting.value_display_formatting or "", 160 )
	if value ~= value_new then
		ModSettingSetNextValue( mod_setting_get_id(mod_id,setting), value_new, false )
		mod_setting_handle_change_callback( mod_id, gui, in_main_menu, setting, value, value_new )
	end

	mod_setting_tooltip( mod_id, gui, in_main_menu, setting )
end

local function GenerateDisplayName(id)
	-- if id starts with "Key_", remove it
	if(id:sub(1, 4) == "Key_")then
		id = id:sub(5)
	end

	-- if starts with "JOY_BUTTON", replace with "Gamepad"
	if(id:sub(1, 11) == "JOY_BUTTON_")then
		id = "Gamepad " .. id:sub(12)
	end

	-- replace underscores with spaces
	id = id:gsub("_", " ")
	-- lowercase, then capitalize first letter
	id = id:sub(1, 1):upper() .. id:sub(2):lower()

	-- trim
	id = id:match("^%s*(.-)%s*$")

	if(id == "")then
		id = "Unbound"
	end

	return id
end

function ImageClip(gui, id,  x, y, width, height, fn, ...)
	GuiAnimateBegin(gui)
	GuiAnimateAlphaFadeIn(gui, id * 620, 0, 0, true)
	GuiBeginAutoBox(gui)

	GuiZSetForNextWidget(gui, 1000)
	GuiBeginScrollContainer(gui, id * 630, x, y, width, height, false, 0, 0)
	GuiEndAutoBoxNinePiece(gui)
	GuiAnimateEnd(gui)
	fn(gui, width, height, ...)
	GuiEndScrollContainer(gui)
end

function ModSettingsGui(gui, in_main_menu)
	last_gui_frame = last_gui_frame or GameGetFrameNum()

	if(last_gui_frame ~= GameGetFrameNum() - 1)then
		bindings = nil
	end

	last_gui_frame = GameGetFrameNum()
	
	if(bindings == nil and not in_main_menu)then
		bindings = dofile_once("mods/evaisa.mp/lib/keybinds.lua")
		bindings:Load()

		local settings_cat = nil
		local all_bindings = {}
		-- sort bindings by category
		for _, id in pairs(bindings._binding_order)do
			if(bindings._bindings[id])then
				local bindy = bindings._bindings[id]
				bindy.id = id
				table.insert(all_bindings, bindy)
			end
		end

		table.sort(all_bindings, function(a, b)
			return a.category < b.category
		end)

		for k, v in ipairs(mod_settings)do
			if(v.category_id == "keybinds")then
				settings_cat = v
				break
			end
		end
		local last_cat = nil
		for _, bind in pairs(all_bindings)do
			if(bind.category ~= last_cat)then
				last_cat = bind.category
				local cat = {
					id = "cat_" .. ToID(bind.category),
					ui_name = bind.category,
					ui_description = "Edit your keybinds here.",
					offset_x = -4,
					color = {219 / 255, 156 / 255, 79 / 255, 1},
					not_setting = true,
				}
				table.insert(settings_cat.settings, cat)
			end

			local id = bind.id
			local setting = {
				id = id,
				ui_name = bind.name,
				ui_description = "",
				value_default = bind.default,
				ui_fn = mod_setting_button,
				clicked_callback = function(mod_id, setting, value)
					bindings._bindings[setting.id].being_set = true
				end,
				right_clicked_callback = function(mod_id, setting, value)
					ModSettingSet("keybind."..bindings._bindings[setting.id].category .. "." .. setting.id, bindings._bindings[setting.id].default)
					ModSettingSet("keybind."..bindings._bindings[setting.id].category .. "." .. setting.id .. ".type", bindings._bindings[setting.id].default_type)
					bindings._bindings[setting.id].value = bindings._bindings[setting.id].default
					bindings._bindings[setting.id].type = bindings._bindings[setting.id].default_type
					
					bindings._bindings[setting.id].being_set = false
				end,
				handler_callback = function(mod_id, setting)

					if(bindings._bindings == nil)then
						print("bindings._bindings is nil")
						return "[Error]"
					end

					if(bindings._bindings[setting.id] == nil)then
						print("bindings._bindings[setting.id] is nil")
						return "[Error]"
					end

					if(bindings._bindings[setting.id].being_set)then
						return "[...]"
					end
					return "["..GenerateDisplayName(bindings._bindings[setting.id].value).."]"
				end
			}

			print("Adding keybind: " .. id)

			table.insert(settings_cat.settings, setting)
		end
	end

	local vc_cat = nil
	for k, v in ipairs(mod_settings) do
		if v.category_id == "voicechat" then
			vc_cat = v
			break
		end
	end

	if vc_cat ~= nil and not in_main_menu then
		local raw_devices = GlobalsGetValue("evaisa.mp.audio_devices", "")
		local smallfolk = dofile_once("mods/evaisa.mp/lib/smallfolk.lua")
		local devices = (raw_devices ~= "" and smallfolk.loads(raw_devices)) or {}

		local saved_name = ModSettingGet("evaisa.mp.mic_device_name") or ""
		local display_name = saved_name ~= "" and saved_name or "Default"

		local mic_device_exists = false
		local mic_level_exists = false
		local mic_test_exists = false
		for _, s in ipairs(vc_cat.settings) do
			if s.id == "mic_device" then mic_device_exists = true end
			if s.id == "mic_level_display" then mic_level_exists = true end
			if s.id == "mic_test_button" then mic_test_exists = true end
		end

		if not mic_device_exists then
			table.insert(vc_cat.settings, {
				id = "mic_device",
				ui_name = "Microphone",
				ui_description = "Select the microphone to use for voice chat.",
				ui_fn = mod_setting_button,
				clicked_callback = function(mod_id, setting, value)
					local raw = GlobalsGetValue("evaisa.mp.audio_devices", "")
					local sf = dofile_once("mods/evaisa.mp/lib/smallfolk.lua")
					local devs = (raw ~= "" and sf.loads(raw)) or {}
					local cur_name = ModSettingGet("evaisa.mp.mic_device_name") or ""
					local cur_idx = 0
					for i, name in ipairs(devs) do
						if name == cur_name then
							cur_idx = i
							break
						end
					end
					local next_idx = cur_idx + 1
					if next_idx > #devs then
						next_idx = 0
					end
					if next_idx == 0 then
						ModSettingSet("evaisa.mp.mic_device_name", "")
						GlobalsSetValue("evaisa.mp.mic_device_changed", "1")
					else
						ModSettingSet("evaisa.mp.mic_device_name", devs[next_idx])
						GlobalsSetValue("evaisa.mp.mic_device_changed", "1")
					end
				end,
				right_clicked_callback = function(mod_id, setting, value)
					ModSettingSet("evaisa.mp.mic_device_name", "")
					GlobalsSetValue("evaisa.mp.mic_device_changed", "1")
				end,
				handler_callback = function(mod_id, setting)
					local name = ModSettingGet("evaisa.mp.mic_device_name") or ""
					return "[" .. (name ~= "" and name or "Default") .. "]"
				end,
			})
		end

		if not mic_level_exists then
			table.insert(vc_cat.settings, {
				id = "mic_level_display",
				ui_name = "Mic Level",
				ui_description = "Live microphone input level. Use this to tune the activation threshold.",
				not_setting = true,
				ui_fn = function(mod_id, gui, in_main_menu, im_id, setting)
					local level = tonumber(GlobalsGetValue("evaisa.mp.mic_level", "0")) or 0
					local threshold = tonumber(ModSettingGet("evaisa.mp.voicechat_vad_threshold")) or 0.04
					local max_level = 0.1
					local bar_w = 120
					local bar_h = 6
					local ox = mod_setting_group_x_offset
					local above = level >= threshold

					local filled_w = math.max(1, math.floor(math.min(level / max_level, 1.0) * bar_w))
					local empty_w = bar_w - filled_w
					local threshold_x = math.min(math.floor(math.min(threshold / max_level, 1.0) * bar_w), bar_w - 1)

					local pre_filled  = math.min(filled_w, threshold_x)
					local pre_empty   = math.max(0, threshold_x - filled_w)
					local post_filled = math.max(0, filled_w - threshold_x - 1)
					local post_empty  = bar_w - threshold_x - 1 - post_filled

					ImageClip(gui, 32512396, 0, 0, bar_w, bar_h, function(gui, width, height)
					GuiLayoutBeginHorizontal(gui, ox, 0, true, 0, 0)

						if pre_filled > 0 then
							if above then
								GuiColorSetForNextWidget(gui, 0.3, 0.9, 0.4, 1)
							else
								GuiColorSetForNextWidget(gui, 0.5, 0.7, 0.9, 1)
							end
							GuiImage(gui, 3185122, 0, 0, "mods/evaisa.mp/files/gfx/ui/1pixel.png", 1, pre_filled, bar_h, 0)
						end
						if pre_empty > 0 then
							GuiColorSetForNextWidget(gui, 0.15, 0.15, 0.15, 1)
							GuiImage(gui, 3185123, 0, 0, "mods/evaisa.mp/files/gfx/ui/1pixel.png", 1, pre_empty, bar_h, 0)
						end

						GuiColorSetForNextWidget(gui, 1, 0.2, 0.2, 1)
						GuiImage(gui, 3185124, 0, 0, "mods/evaisa.mp/files/gfx/ui/1pixel.png", 1, 1, bar_h, 0)

						if post_filled > 0 then
							if above then
								GuiColorSetForNextWidget(gui, 0.3, 0.9, 0.4, 1)
							else
								GuiColorSetForNextWidget(gui, 0.5, 0.7, 0.9, 1)
							end
							GuiImage(gui, 3185125, 0, 0, "mods/evaisa.mp/files/gfx/ui/1pixel.png", 1, post_filled, bar_h, 0)
						end
						if post_empty > 0 then
							GuiColorSetForNextWidget(gui, 0.15, 0.15, 0.15, 1)
							GuiImage(gui, 3185126, 0, 0, "mods/evaisa.mp/files/gfx/ui/1pixel.png", 1, post_empty, bar_h, 0)
						end

					GuiLayoutEnd(gui)
					end)
				end,
			})
		end

		if not mic_test_exists then
			table.insert(vc_cat.settings, {
				id = "mic_test_button",
				ui_name = "Test Microphone",
				ui_description = "Toggle microphone loopback test. You will hear yourself with a short delay.",
				ui_fn = mod_setting_button,
				clicked_callback = function(mod_id, setting, value)
					GlobalsSetValue("evaisa.mp.request_mic_test_toggle", "1")
				end,
				right_clicked_callback = function(mod_id, setting, value)
					GlobalsSetValue("evaisa.mp.request_mic_test_toggle", "1")
				end,
				handler_callback = function(mod_id, setting)
					return GlobalsGetValue("evaisa.mp.mic_test_active", "0") == "1" and "[Active]" or "[Off]"
				end,
			})
		end
	end

	mod_settings_gui(mod_id, mod_settings, gui, in_main_menu)

	if(bindings ~= nil)then
		bindings:Update()
	end
end
