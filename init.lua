--------- STATIC VARIABLES ---------

game_id = 881100

-- load version numbers
dofile("mods/evaisa.mp/version.lua")

noita_online_download = "https://github.com/EvaisaDev/noita-online/releases"
exceptions_in_logger = true
dev_mode = false
debugging = false
disable_print = false
trailer_mode = false
disable_error_catching = false

-----------------------------------

popup = dofile("mods/evaisa.mp/files/scripts/popup.lua")
try = dofile("mods/evaisa.mp/lib/try_catch.lua")
local ffi = require"ffi"

----- check if thingy is installed ------
local failed_to_load = false
try(function() 
	local _ = ffi.load("msvcp140.dll")
end).catch(function(ex)
	print("Failed to load msvcp140.dll")
	failed_to_load = true
end)


------ TRANSLATIONS -------

dofile("mods/evaisa.mp/lib/translations.lua")

register_localizations("mods/evaisa.mp/translations.csv", 2)

---------------------------

------ Path definitions -------
package.path = package.path .. ";./mods/evaisa.mp/lib/?.lua"
package.path = package.path .. ";./mods/evaisa.mp/lib/?/init.lua"
package.cpath = package.cpath .. ";./mods/evaisa.mp/bin/?.dll"
package.cpath = package.cpath .. ";./mods/evaisa.mp/bin/?.exe"

local function load(modulename)
	local errmsg = ""
	for path in string.gmatch(package.path, "([^;]+)") do
		local filename = string.gsub(path, "%?", modulename)
		local file = io.open(filename, "rb")
		if file then
			-- Compile and return the module
			return assert(loadstring(assert(file:read("*a")), filename))
		end
		errmsg = errmsg .. "\n\tno file '" .. filename .. "' (checked with custom loader)"
	end
	return errmsg
end

---------------------------



string.bytes = function(str)
	local bytes = 0
	for i = 1, #str do
		bytes = bytes + str:byte(i)
	end
	return bytes
end

get_content = ModTextFileGetContent
set_content = ModTextFileSetContent

dofile("mods/evaisa.mp/lib/ffi_extensions.lua")




-- do not apply any callbacks or anything because this is fucked up and evil
if(not failed_to_load)then

	----------------- Gui Option Jankery ----------------

	local gui_option_cache = {}

	local gui_option_add = GuiOptionsAdd
	local gui_option_remove = GuiOptionsRemove

	function GuiOptionsAdd(gui, option)
		gui_option_cache[gui] = gui_option_cache[gui] or {}
		gui_option_cache[gui][option] = true
		gui_option_add(gui, option)
	end

	function GuiOptionsRemove(gui, option)
		if(gui_option_cache[gui] and gui_option_cache[gui][option])then
			gui_option_remove(gui, option)
			gui_option_cache[gui][option] = nil
		end
	end

	-- epic new function truly
	function GuiOptionsHas(gui, option)
		return gui_option_cache[gui] and gui_option_cache[gui][option]
	end

	function GuiOptionsList(gui)
		local options = {}

		if(gui_option_cache[gui])then
			for k, v in pairs(gui_option_cache[gui])do
				table.insert(options, k)
			end
		end

		return options
	end

	local gamemode_path = nil

	-- Old function, doesn't work properly if multiple installs of mod exists and i do not know how to solve this.
	function GetGamemodeFilePath()

		if(gamemode_path)then
			return gamemode_path
		end

		debug_log:print("GetGamemodeFilePath")

		local save_folder = os.getenv('APPDATA'):gsub("\\Roaming", "") ..
			"\\LocalLow\\Nolla_Games_Noita\\save00\\mod_config.xml"

		local file_path = nil

		local file, err = io.open(save_folder, 'rb')
		if file then

			debug_log:print("Found mod_config.xml")
			
			local content = file:read("*all")

			local subscribed_items = steam.UGC.getSubscribedItems()
			local item_infos = {}

			for _, v in ipairs(subscribed_items) do

				local success, size, folder, timestamp = steam.UGC.getItemInstallInfo(v)
				if (success) then
					item_infos[tostring(v)] = {size = size, folder = folder, timestamp = timestamp}
				end

			end
			

			local parsedModData = nxml.parse(content)
			for elem in parsedModData:each_child() do
				if (elem.name == "Mod") then
					local modID = elem.attr.name
					local steamID = elem.attr.workshop_item_id

					local infoFile = "mods/" .. modID .. "/mod.xml"
					if (steamID ~= "0") then
						if(item_infos[steamID])then
							infoFile = item_infos[steamID].folder .. "/mod.xml"
						else
							debug_log:print("Failed to find item info for: " .. steamID)
							infoFile = nil
						end
					end

					if(infoFile)then

						local file2, err = io.open(infoFile, 'rb')
						if file2 then
							local content2 = file2:read("*all")
							if(content2 ~= nil and content2 ~= "")then
								local parsedModInfo = nxml.parse(content2)
								
								local is_game_mode = parsedModInfo.attr.is_game_mode == "1"

								if (ModIsEnabled(modID) and is_game_mode) then
									if steamID == "0" then
										file_path = "mods/" .. modID
									else
										file_path = item_infos[steamID].folder
									end
									break
								end
							end
						else
							debug_log:print("Failed to open mod.xml: " .. infoFile)
							debug_log:print("Error: " .. tostring(err))
						end
					end

				end
			end
			file:close()

			
		end
		debug_log:print("Gamemode path: " .. tostring(file_path))

		gamemode_path = file_path

		return file_path
	end

	function GetModFilePath(mod_id, steam_id)
		local file_path = nil

		if(not steam_id or steam_id == "" or steam_id == "0")then
			file_path = "mods/" .. mod_id
		else
			local subscribed_items = steam.UGC.getSubscribedItems()
			local item_infos = {}

			for _, v in ipairs(subscribed_items) do

				local success, size, folder, timestamp = steam.UGC.getItemInstallInfo(v)
				if (success) then
					item_infos[tostring(v)] = {size = size, folder = folder, timestamp = timestamp}
				end

			end

			if(item_infos[steam_id])then
				file_path = item_infos[steam_id].folder
			else
				file_path = "mods/" .. mod_id
			end
		end

		return file_path
	end


	if(trailer_mode)then
		ModMagicNumbersFileAdd("mods/evaisa.mp/magic_numbers_trailer.xml")
	end

	if(ModIsEnabled("NoitaDearImGui"))then
		imgui = load_imgui({mod="noita-online", version="1.20"})
		implot = imgui.implot
	end

	local inspect = dofile("mods/evaisa.mp/lib/inspect.lua")

	zstandard = require("zstd")
	zstd = zstandard:new()

	table.insert(package.loaders, 2, load)

	logger = require("logger")("noita_online_logs")
	mp_log = logger.init("noita-online.log")
	networking_log = logger.init("networking.log")
	debug_log = logger.init("debugging.log")
	exception_log = logger.init(os.date("%Y-%m-%d_%H-%M-%S")..".log", false, nil, "noita_online_logs/exceptions")
	debug_info = logger.init("debug_info.log", nil, true, nil, true)

	if(not debugging)then
		networking_log.enabled = false
	end

	--fontbuilder = dofile("mods/evaisa.mp/lib/fontbuilder.lua")

	game_config = dofile("mods/evaisa.mp/lib/game_config.lua")

	local function readWord(file)
		local byte1, byte2 = file:read(1), file:read(1)
		if not byte1 or not byte2 then
		return nil
		end
		return byte1:byte() + byte2:byte() * 256
	end

	local function readDword(file)
		local word1, word2 = readWord(file), readWord(file)
		if not word1 or not word2 then
		return nil
		end
		return word1 + word2 * 65536
	end

	local function checkLAA(filename)
		local file, err = io.open(filename, "rb")
		if not file then
		print("Error opening file: " .. err)
		return false
		end
	
		file:seek("set", 0x3C)
		local peOffset = readDword(file)
	
		file:seek("set", peOffset + 4) -- Go to IMAGE_FILE_HEADER
		local characteristicsOffset = peOffset + 22 -- Offset of "Characteristics" field
	
		file:seek("set", characteristicsOffset)
		local characteristics = readWord(file)
	
		file:close()
	
		return bit.band(characteristics, 0x20) == 0x20 -- Properly check the IMAGE_FILE_LARGE_ADDRESS_AWARE flag
	end

	lobby_data_last_frame = {}
	lobby_data_updated_this_frame = {}

	ModRegisterAudioEventMappings("mods/evaisa.mp/GUIDs.txt")

	dofile_once("mods/evaisa.mp/files/scripts/gui_utils.lua")

	dofile("data/scripts/lib/coroutines.lua")
	nxml = dofile("mods/evaisa.mp/lib/nxml.lua")

	try(function()
		require 'lua-utf8'
	end).catch(function(ex)
		exception_log:print(tostring(ex))
		if(exceptions_in_logger)then
			old_print(tostring(ex))
		end
	end)


	pngencoder = require("pngencoder")

	dofile_once("mods/evaisa.mp/bin/NoitaPatcher/load.lua")

	np = require("noitapatcher")

	bitser = require("bitser")
	smallfolk = require("smallfolk")
	binser = require("binser")
	--zstandard = require("zstd")
	--zstd = zstandard:new()
	delay = dofile("mods/evaisa.mp/lib/delay.lua")
	streaming = dofile("mods/evaisa.mp/lib/streaming.lua")

	local profiler_ui = dofile("mods/evaisa.mp/lib/profiler_ui.lua")


	debug_info:print("Build: " .. tostring(MP_VERSION))

	rng = dofile("mods/evaisa.mp/lib/rng.lua")
	rand = nil

	in_game = false
	Spawned = false
	Starting = nil

	cached_lobby_data = {}

	lobby_gamemode = nil



	debug_info:print("Dev mode: " .. tostring(dev_mode))

	local fs = require("fs")

	local sha1 = require "sha1"

	function GetNoitaVersionHash()
		local file = "_version_hash.txt"
		local f = io.open(file, "r")
		if f then
			local hash = f:read("*all")
			f:close()
			return hash
		end
		return nil
	end

	local function sleep(ms)
		-- loop for n ms
		local t0 = os.clock()
		while os.clock() - t0 <= ms / 1000 do
		end
	end



	noita_version = np.GetVersionString()

	if(GameIsBetaBuild())then
		noita_version = noita_version .. " (beta)"
	end

	function GetContentHash()
		local file = "data\\data.wak"

		-- try to run certutil
		local handle = io.popen("certutil -hashfile " .. file .. " SHA1")

		if not handle then
			return "Unknown"
		end

		local result = handle:read("*a")
		handle:close()

		local hash = string.match(result, "SHA1 hash of " .. file .. ":\n([%w]+)\n")

		if hash then
			return hash
		end

		-- try to run hasher.exe instead
		debug_log:print("Used hasher.exe to get the data.wak hash")

		local handle = io.popen("mods\\evaisa.mp\\bin\\hasher.exe \"" .. file .. "\"")

		if not handle then
			return "Unknown"
		end

		local result = handle:read("*a")
		handle:close()

		if not result then
			return "Unknown"
		end

		-- remove surrounding newlines
		result = result:gsub("^%s*(.-)%s*$", "%1")

		return result
	end
	
	

	noita_version_hash = GetContentHash()

	print("Noita version hash: " .. noita_version_hash)
	

	debug_info:print("Noita hash: " .. tostring(noita_version_hash))

	--[[last_noita_version = ModSettingGet("evaisa.mp.last_noita_version_hash") or ""
	laa_check_done = true
	if(noita_version_hash ~= nil)then
		mp_log:print("Noita version hash: " .. noita_version_hash)
		if(last_noita_version ~= noita_version_hash)then
			ModSettingSet("evaisa.mp.last_noita_version_hash", noita_version_hash)
			--laa_check_done = false
		else
			--laa_check_done = true
		end
	end]]
	base64 = require("base64")

	msg = require("msg")
	pretty = require("pretty_print")



	debug_info:print("Beta build: " .. tostring(GameIsBetaBuild()))
	debug_info:print("Using controller: " .. tostring(GameGetIsGamepadConnected()))

	function RepairDataFolder()
		local data_folder_name = os.getenv('APPDATA'):gsub("\\Roaming", "") ..
			"\\LocalLow\\Nolla_Games_Noita\\save00\\evaisa.mp_data"
		-- remove the folder
		os.execute('del /q "' .. data_folder_name .. '\\*.*"')
		print("Repaired data folder.")
		GamePrint("Repairing data folder")
	end

	local serialization_version = "3"
	if ((ModSettingGet("last_serialization_version") or "1") ~= serialization_version) then
		RepairDataFolder()
		ModSettingSet("last_serialization_version", serialization_version)
	end

	np.InstallShootProjectileFiredCallbacks()
	np.EnableGameSimulatePausing(false)
	np.InstallDamageDetailsPatch()
	np.SilenceLogs("Warning - streaming didn\'t find any chunks it could stream away...\n")
	--[[np.EnableExtendedLogging(true)
	np.EnableLogFiltering(true)

	function FilterLog(source, function_name, line, ...)
		debug_log:print(source .. " " .. function_name .. " " .. line .. " " .. table.concat({...}, " "))
		return false
	end]]

	np.EnableLogFiltering(true)

	function FilterLog(source, function_name, line, ...)
		debug_log:print(source .. " " .. function_name .. " " .. line .. " " .. table.concat({...}, " "))
		-- if contains "Lua error" or "Stack traceback"
		if (string.find(table.concat({...}, " "), "Lua error") or string.find(table.concat({...}, " "), "Stack traceback")) then
			exception_log:print(source .. " " .. function_name .. " " .. line .. " " .. table.concat({...}, " "))
			return true
		end
		return false
	end

	--GameSDK = require("game_sdk")

	steam = require("luasteam")


	--GameSDK = nil
	--discord_sdk = nil

	--require("physics")
	steamutils = dofile_once("mods/evaisa.mp/lib/steamutils.lua")
	clear_avatar_cache()
	json = dofile_once("mods/evaisa.mp/lib/json.lua")

	pretty = require("pretty_print")

	local is_invalid_version = (PhysicsBodyIDGetBodyAABB == nil)

	--GamePrint("Making api call")

	dofile("mods/evaisa.mp/files/scripts/debugging.lua")

	dofile("mods/evaisa.mp/lib/character_support.lua")

	local old_print = print
	print = function(...)
		if not disable_print then
			local content = ...
			local source = debug.getinfo(2).source
			local line = debug.getinfo(2).currentline

			old_print(table.concat({"[" .. source .. ":" .. tostring(line) .. "]", ... }, " "))
		end
	end


	function OnPausedChanged(paused, is_wand_pickup)
		local players = EntityGetWithTag("player_unit") or {}

		if(not is_wand_pickup)then
			if(imgui)then
				profiler_ui.apply_profiler_rate()
			end
		end

		if (players[1]) then
			np.RegisterPlayerEntityId(players[1])
			local inventory_gui = EntityGetFirstComponentIncludingDisabled(players[1], "InventoryGuiComponent")
			local controls_component = EntityGetFirstComponentIncludingDisabled(players[1], "ControlsComponent")
			if (paused) then
				--EntitySetComponentIsEnabled(players[1], inventory_gui, false)
				np.EnableInventoryGuiUpdate(false)
				np.EnablePlayerItemPickUpper(false)
				ComponentSetValue2(controls_component, "enabled", false)
			else
				--EntitySetComponentIsEnabled(players[1], inventory_gui, true)
				np.EnableInventoryGuiUpdate(true)
				np.EnablePlayerItemPickUpper(true)
				ComponentSetValue2(controls_component, "enabled", true)
			end
		end

		if (paused) then
			GameAddFlagRun("game_paused")
			--GamePrint("paused")
		else
			GameRemoveFlagRun("game_paused")
			--GamePrint("unpaused")
		end
	end

	function IsPaused()
		return steam_overlay_open or GameHasFlagRun("game_paused")
	end

	if type(Steam) == 'boolean' then Steam = nil end

	activity = activity or nil


	game_in_progress = false

	gamemode_settings = gamemode_settings or {}

	dofile("mods/evaisa.mp/files/scripts/lobby_handler.lua")
	dofile_once("mods/evaisa.mp/files/scripts/utils.lua")
	dofile_once("data/scripts/lib/utilities.lua")
	input = nil 
	bindings = nil

	bytes_sent = 0
	last_bytes_sent = 0
	bytes_received = 0
	last_bytes_received = 0

	bytes_sent_per_type = {}
	bytes_received_per_type = {}

	active_members = {}
	member_message_frames = {}
	gamemode_index = 1

	gamemodes = {}

	function FindGamemode(id)
		for k, v in pairs(gamemodes) do
			if (v.id == id) then
				return v, k
			end
		end
		return nil
	end

	function TryHandleMessage(lobby_code, event, message, user, ignore)
		try(function()
			if (lobby_gamemode ~= nil) then
				local owner = steam.matchmaking.getLobbyOwner(lobby_code)
		
				local from_owner = user == owner
		
				if (from_owner and event == "start" or event == "restart") then

					print("Starting game")
					
					if(lobby_gamemode.apply_start_data)then
						lobby_gamemode.apply_start_data(lobby_code, message)
					end

					if(event == "restart")then
						StopGame()
					end

					if(owner == steam_utils.getSteamID())then
						Starting = 5
					else
						Starting = 30
					end
				elseif (from_owner and event == "refresh") then

					print("Refreshing lobby data")
		
					if handleVersionCheck() and handleModCheck() then
						if handleGamemodeVersionCheck(lobby_code) then
							if (lobby_gamemode) then
								--game_in_progress = false
								--print("Refreshing lobby data in 30 frames")
								delay.new(30, function()
									for k, setting in ipairs(lobby_gamemode.settings or {}) do
										gamemode_settings[setting.id] = steam.matchmaking.getLobbyData(lobby_code, "setting_" ..
											setting.id)
									end
				
									if (lobby_gamemode.refresh) then
										lobby_gamemode.refresh(lobby_code)
									end
								end, function(frames) end)
		
		
							else
								disconnect({
									lobbyID = lobby_code,
									message = string.format(GameTextGetTranslatedOrNot("$mp_gamemode_missing"), tostring(lobby_gamemode.id))--"Gamemode missing: " .. tostring(lobby_gamemode.id)
								})
							end
						end
					end
				elseif (owner == steam_utils.getSteamID() and event == "spectate") then
					print("Toggling spectator for " .. tostring(steamutils.getTranslatedPersonaName(user)))
					local spectating = steamutils.IsSpectator(lobby_code, user)
					steam_utils.TrySetLobbyData(lobby_code, tostring(user) .. "_spectator", spectating and "false" or "true")
				end

				--print("ignore? "..tostring(ignore))

				if (lobby_gamemode.received and not ignore) then
					lobby_gamemode.received(lobby_code, event, message, user)
				end
			end
		end).catch(function(ex)
			exception_log:print(tostring(ex))
			if(exceptions_in_logger)then
				old_print(tostring(ex))
			end
		end)
	end

	function HandleMessage(v, ignore)
			
		if(is_awaiting_spectate)then
			return
		end

		local data = steamutils.parseData(v.data)

		bytes_received = bytes_received + v.msg_size

		if (lobby_gamemode == nil) then
			return
		end

		-- old api
		if (lobby_gamemode.message and not ignore) then
			lobby_gamemode.message(lobby_code, data, v.user)
		end
		
		if (data[1] and type(data[1]) == "string") then
			if(bytes_received_per_type[data[1]] == nil)then
				bytes_received_per_type[data[1]] = 0
			end
			bytes_received_per_type[data[1]] = bytes_received_per_type[data[1]] + v.msg_size
			local event = data[1]
			local message = data[2]
			local frame = data[3]

			if (data[3]) then
				if (not member_message_frames[tostring(v.user)] or member_message_frames[tostring(v.user)] <= frame) then
					member_message_frames[tostring(v.user)] = frame
					TryHandleMessage(lobby_code, event, message, v.user, ignore)
				end
			else
				TryHandleMessage(lobby_code, event, message, v.user, ignore)
			end
		else
			print("Invalid message: "..tostring(data))
			print(inspect(data))
		end
	end

	local function ReceiveMessages(ignore)
		-- 10 available channels should be enough
		--for i = 0, 10 do
			--print("Polling messages on channel " .. tostring(i))
			if(is_awaiting_spectate)then
				return
			end
			local messages = steam.networking.pollMessages(0) or {}
			if(#messages > 0)then
				--print("Received " .. tostring(#messages) .. " messages")
				for k, v in ipairs(messages) do
					HandleMessage(v, ignore)
				end
			end
		--end
	end

	----- debugging spell stuff ------


	--ModTextFileSetContent("mods/gun_flag.lua", [[
	--for i, action in ipairs(actions)do
	--	if(i > 4)then
	--		action.spawn_requires_flag = action.id
	--	end
	--end
	--]])

	--ModLuaFileAppend("data/scripts/gun/gun_actions.lua", "mods/gun_flag.lua")

	----------------------------------

	local spawned_popup = false
	local init_cleanup = false
	local connection_popup_open = false
	local connection_popup_was_open_timer = 0
	local laa_check_busy = false
	local invalid_version_popup_open = false

	function OnWorldPreUpdate()
		try(function()
			if(GameHasFlagRun("mp_blocked_load"))then
				return
			end

			-- this code handles unpausing the mod after closing steam overlay
			--[[if(steam_overlay_closed and GameGetFrameNum() > steam_overlay_closed_frame + 60)then
				steam_overlay_closed = false
				steam_overlay_open = false
			end]]

			if(imgui)then
				profiler_ui.pre_update()
			else
				if (input ~= nil and input:WasKeyPressed("f8")) then
					GamePrint("Cannot use profiler without dear imgui installed.")
				end
			end
			--input:Update()

			wake_up_waiting_threads(1)
			--math.randomseed( os.time() )

			if (not IsPaused()) then
				popup.update()
			end


			if (not failed_to_load) and steam and GameGetFrameNum() >= 60 then


				--[[if(not laa_check_done)then
					laa_enabled = checkLAA("noita.exe")
					print("LAA: " .. tostring(laa_enabled))

					
					if(not laa_enabled)then
						laa_check_busy = true
						popup.create("laa_message", GameTextGetTranslatedOrNot("$mp_laa_message"), {
							GameTextGetTranslatedOrNot("$mp_laa_description"),
							{
								text = GameTextGetTranslatedOrNot("$mp_laa_warning"),
								color = {217 / 255,52 / 255,52 / 255, 1}
							}
						}, {
							{
								text = GameTextGetTranslatedOrNot("$mp_laa_patch"),
								callback = function()
									LAAPatch("noita.exe", "noita")
									laa_check_busy = false
								end
							},
							{
								text = GameTextGetTranslatedOrNot("$mp_close_popup"),
								callback = function()
									laa_check_busy = false
								end
							},
						}, -6000)
					end
					laa_check_done = true
				end]]

				if(is_invalid_version)then
					
					if(not invalid_version_popup_open)then
						invalid_version_popup_open = true
						popup.create("invalid_version_message", GameTextGetTranslatedOrNot("$mp_invalid_version"),
						GameTextGetTranslatedOrNot("$mp_invalid_version_description"), {
							{
								text = GameTextGetTranslatedOrNot("$mp_close_popup"),
								callback = function()
									invalid_version_popup_open = false
								end
							}
						}, -6000)

					end
					return
				end
				
				if(not laa_check_busy)then
					if(not steam.user.loggedOn())then
						if(GameGetFrameNum() % (300) == 0)then
							GamePrint("Failed to connect to steam servers, are you logged into steam friends list?")
						end
						
						if(connection_popup_was_open_timer > 0)then
							connection_popup_was_open_timer = connection_popup_was_open_timer - 1
						end



						if(not connection_popup_open and connection_popup_was_open_timer <= 0)then
							connection_popup_open = true
							connection_popup_was_open_timer = 60 * 60 * 2
							popup.create("connection_message", GameTextGetTranslatedOrNot("$mp_steam_connection_failed_title"),
							GameTextGetTranslatedOrNot("$mp_steam_connection_failed_description"), {
								{
									text = GameTextGetTranslatedOrNot("$mp_close_popup"),
									callback = function()
										if(lobby_code ~= nil)then
											connection_popup_open = false
										end
									end
								}
							}, -6000)
						end
					end

					--[[if(GameSDK ~= nil and discord_sdk ~= nil)then
						GameSDK.runCallbacks(discord_sdk.corePtr)
					end]]


					if(input == nil)then
						input = dofile_once("mods/evaisa.mp/lib/input.lua")
					end

					if(bindings == nil)then
						bindings = dofile_once("mods/evaisa.mp/lib/keybinds.lua")

						-- keyboards bindings
						bindings:RegisterBinding("chat_submit", "Noita Online [keyboard]", "Chat Send", "Key_RETURN", "key", false, true, false, false)
						bindings:RegisterBinding("chat_submit2", "Noita Online [keyboard]", "Chat Send Alt", "Key_KP_ENTER", "key", false, true, false, false)
						bindings:RegisterBinding("chat_open_kb", "Noita Online [keyboard]", "Open Chat", "", "key", false, true, false, false)
						bindings:RegisterBinding("lobby_menu_open_kb", "Noita Online [keyboard]", "Open Lobby Menu", "", "key", false, true, false, false)
					
						-- gamepad bindings
						bindings:RegisterBinding("chat_submit_gp", "Noita Online [gamepad]", "Chat Send", "", "button", false, false, true, false, true)
						bindings:RegisterBinding("chat_open_gp", "Noita Online [gamepad]", "Open Chat", "", "button", false, false, true, false, true)
						bindings:RegisterBinding("lobby_menu_open_gp", "Noita Online [gamepad]", "Open Lobby Menu", "", "button", false, false, true, false, true)
						
						-- loop through gamemodes
						for k, v in ipairs(gamemodes) do
							if(v.binding_register ~= nil)then
								v.binding_register(bindings)
							end
						end
					end

					if(init_cleanup == false)then
						local lastCode = ModSettingGet("last_lobby_code")
						--print("Code: "..tostring(lastCode))
						if (steam) then
							if (lastCode ~= nil and lastCode ~= "") then
								local lobCode = steam.extra.parseUint64(lastCode)
								if (tostring(lobCode) ~= "0") then
									if (steam.extra.isSteamIDValid(lobCode)) then
										gamemode_settings = {}
										
										steam_utils.Leave(lobCode)
									end
								end
								ModSettingRemove("last_lobby_code")
								lobby_code = nil
							end
						end
						init_cleanup = true
					end

					--pretty.table(steam.networking)
					lobby_code = lobby_code or nil
					
					ResetIDs()
					ResetWindowStack()

					--print(fs.cd())
					
					dofile("mods/evaisa.mp/files/scripts/lobby_ui.lua")
					dofile("mods/evaisa.mp/files/scripts/chat_ui.lua")
			
					if (GameGetFrameNum() % (600) == 0) then
						steamutils.CheckLocalLobbyData()
					end

					if (lobby_code ~= nil) then

						if (lobby_gamemode == nil) then
							return
						end

						delay.update()

						if(Starting ~= nil)then
							Starting = Starting - 1
							if(Starting < 0)then
								Starting = 0
							end
						end

						if(Starting == 0)then
							StartGame()
							Starting = nil
						end

						--game_in_progress = steam.matchmaking.getLobbyData(lobby_code, "in_progress") == "true"

						--print("a")


						--print("b")

						if (GameGetFrameNum() % Random(59,61) == 0) then

							steam_utils.updateCacheSpectators(lobby_code)
							
							last_bytes_sent = bytes_sent
							last_bytes_received = bytes_received
							bytes_sent = 0
							bytes_received = 0

							local function format_bytes(bytes)
								return bytes < 1024 and tostring(bytes) .. " B/s" or tostring(math.floor(bytes / 1024)) .. " KB/s"
							end

							local output_string = last_bytes_sent < 1024 and tostring(last_bytes_sent) .. " B/s" or tostring(math.floor(last_bytes_sent / 1024)) .. " KB/s"

							local input_string = last_bytes_received < 1024 and tostring(last_bytes_received) .. " B/s" or tostring(math.floor(last_bytes_received / 1024)) .. " KB/s"

							local network_string = "Data throughput: ".."in: " .. input_string .. " | out: " .. output_string

							for k, v in pairs(bytes_sent_per_type) do
								if(bytes_received_per_type[k] == nil)then
									bytes_received_per_type[k] = 0
								end
								local sent = v
								local received = bytes_received_per_type[k]
								network_string = network_string .. "\n["..k.."]: out: "..format_bytes(sent).." | in: "..format_bytes(received)
							end

							bytes_sent_per_type = {}
							bytes_received_per_type = {}

							networking_log:print(network_string.."\n")
						end
						--[[
						local players = get_players()
						
						if(players[1] ~= nil)then
							local player = players[1]
							
							GetUpdatedEntityID = function()
								return player
							end
							dofile("mods/evaisa.mp/files/scripts/player_update.lua")
						end
						]]
						--print("c")

						byte_rate_gui = byte_rate_gui or GuiCreate()
						GuiStartFrame(byte_rate_gui)

						local screen_width, screen_height = GuiGetScreenDimensions(byte_rate_gui)

						local output_string = last_bytes_sent < 1024 and tostring(last_bytes_sent) .. " B/s" or
							tostring(math.floor(last_bytes_sent / 1024)) .. " KB/s"

						local input_string = last_bytes_received < 1024 and tostring(last_bytes_received) .. " B/s" or
							tostring(math.floor(last_bytes_received / 1024)) .. " KB/s"

						local text_width, text_height = GuiGetTextDimensions(byte_rate_gui,
							"in: " .. input_string .. " | out: " .. output_string)

						if(not IsPaused() and debugging)then
							GuiText(byte_rate_gui, screen_width - text_width - 50, 1, "in: " .. input_string .. " | out: " ..
								output_string)
						end
						--print("d")

						--print("Game in progress: "..tostring(game_in_progress))

						if (game_in_progress) then
							--print("the hell??")

							if (lobby_gamemode.update) then
								lobby_gamemode.update(lobby_code)
							end
		
						
						end

						if(lobby_gamemode.lobby_update ~= nil)then
							lobby_gamemode.lobby_update(lobby_code)
						end

						ReceiveMessages(not game_in_progress)
					end
				end
			end
		end).catch(function(ex)
			exception_log:print(tostring(ex))
			if(exceptions_in_logger)then
				old_print(tostring(ex))
			end
		end)
	end

	function OnProjectileFired(shooter_id, projectile_id, rng, position_x, position_y, target_x, target_y, send_message,
							unknown1, multicast_index, unknown3)
		try(function()
			if steam then
				--pretty.table(steam.networking)
				lobby_code = lobby_code or nil

				if (lobby_code ~= nil) then

					if (lobby_gamemode ~= nil and game_in_progress) then
						if (lobby_gamemode.on_projectile_fired) then
							lobby_gamemode.on_projectile_fired(lobby_code, shooter_id, projectile_id, rng, position_x, position_y,
								target_x, target_y, send_message, unknown1, multicast_index, unknown3)
						end
					end
				end
			end
		end).catch(function(ex)
			exception_log:print(tostring(ex))
			if(exceptions_in_logger)then
				old_print(tostring(ex))
			end
		end)
	end

	function OnProjectileFiredPost(shooter_id, projectile_id, rng, position_x, position_y, target_x, target_y, send_message,
								unknown1, multicast_index, unknown3)
		try(function()
			if steam then
				--pretty.table(steam.networking)
				lobby_code = lobby_code or nil

				if (lobby_code ~= nil) then

					if (lobby_gamemode ~= nil and game_in_progress) then
						if (lobby_gamemode.on_projectile_fired_post) then
							lobby_gamemode.on_projectile_fired_post(lobby_code, shooter_id, projectile_id, rng, position_x,
								position_y, target_x, target_y, send_message, unknown1, multicast_index, unknown3)
						end
					end
				end
			end
		end).catch(function(ex)
			exception_log:print(tostring(ex))
			if(exceptions_in_logger)then
				old_print(tostring(ex))
			end
		end)
	end



	function OnWorldPostUpdate()
		try(function()
			if steam then
				--pretty.table(steam.networking)
				lobby_code = lobby_code or nil

				if (lobby_code ~= nil) then

					if (lobby_gamemode ~= nil and game_in_progress) then
						if (lobby_gamemode.late_update) then
							lobby_gamemode.late_update(lobby_code)
						end

						--[[
						local messages = steam.networking.pollMessages() or {}
						for k, v in ipairs(messages)do
							bytes_received = bytes_received + v.msg_size
							if(lobby_gamemode.message)then
								lobby_gamemode.message(lobby_code, steamutils.parseData(v.data), v.user)
							end
						end
						]]
						--ReceiveMessages(lobby_gamemode)
					end
				end
			end
			GameRemoveFlagRun("chat_bind_disabled")
			lobby_data_updated_this_frame = {}
			if(bindings ~= nil and not IsPaused())then
				bindings:Update()
			end


			if(imgui)then
				profiler_ui.post_update()
			end

		end).catch(function(ex)
			exception_log:print(tostring(ex))
			if(exceptions_in_logger)then
				old_print(tostring(ex))
			end
		end)
	end



	function steam.matchmaking.onLobbyEnter(data)
		try(function()

			print(tostring(data.response))


			clear_avatar_cache()
			for k, v in pairs(active_members) do
				active_members[k] = nil
				member_message_frames[k] = nil
				lobby_members = {}
				lobby_members_ids = {}
				steam.networking.closeSession(v)
				mp_log:print("Closed session with " .. steamutils.getTranslatedPersonaName(v))
			end
			input:Clear()
			Starting = nil
			in_game = false
			game_in_progress = false

			local user = steam_utils.getSteamID()

			steamutils.getUserAvatar(user)


			if (data.response == 1) then
				lobby_code = data.lobbyID
				mp_log:print("Code set to: " .. tostring(lobby_code) .. "[" .. type(lobby_code) .. "]")
				ModSettingSet("last_lobby_code", tostring(lobby_code))
				lobby_gamemode = FindGamemode(steam.matchmaking.getLobbyData(lobby_code, "gamemode"))

				local lobby_data_count = steam.matchmaking.getLobbyDataCount(lobby_code)
				for i = 1, lobby_data_count do
					local data = steam.matchmaking.getLobbyDataByIndex(lobby_code, i -1 )
					
					if(cached_lobby_data[data.key] ~= data.value)then
						cached_lobby_data[data.key] = data.value
					end
					print("Lobby Data: ["..tostring(data.key).."] = "..tostring(data.value))
				end

				
				if handleVersionCheck() and handleModCheck() then
					if handleGamemodeVersionCheck(lobby_code) then
						if (lobby_gamemode) then
							steam.matchmaking.setLobbyMemberData(lobby_code, "in_game", "false")


							defineLobbyUserData(lobby_code)
							
							delay.new(30, function()
								for k, setting in ipairs(lobby_gamemode.settings or {}) do
									gamemode_settings[setting.id] = steam.matchmaking.getLobbyData(lobby_code, "setting_" ..
										setting.id)
								end
			
								if (lobby_gamemode.refresh) then
									lobby_gamemode.refresh(lobby_code)
								end
							end, function(frames) end)

							--[[game_in_progress = steam.matchmaking.getLobbyData(lobby_code, "in_progress") == "true"
							if(game_in_progress)then
								gui_closed = true
							end]]

							if (lobby_gamemode ~= nil) then
								local lobby_name = steam.matchmaking.getLobbyData(lobby_code, "name")
								steam.friends.setRichPresence( "status", "Noita Online || "..GameTextGetTranslatedOrNot(tostring(lobby_gamemode.name)))
								steam.friends.setRichPresence( "steam_player_group", lobby_name )
								
								local member_count = steam.matchmaking.getNumLobbyMembers(lobby_code)
					
								steam.friends.setRichPresence( "steam_player_group_size", tostring(member_count) )
								active_mode = lobby_gamemode
								get_preset_folder_name()
								generate_lobby_menus_list()
								lobby_gamemode.enter(lobby_code)
							end

							
							
							
						end
					end
				end	
			else

				--[[
					k_EChatRoomEnterResponseSuccess	1	Success.
					k_EChatRoomEnterResponseDoesntExist	2	Chat doesn't exist (probably closed).
					k_EChatRoomEnterResponseNotAllowed	3	General Denied - You don't have the permissions needed to join the chat.
					k_EChatRoomEnterResponseFull	4	Chat room has reached its maximum size.
					k_EChatRoomEnterResponseError	5	Unexpected Error.
					k_EChatRoomEnterResponseBanned	6	You are banned from this chat room and may not join.
					k_EChatRoomEnterResponseLimited	7	Joining this chat is not allowed because you are a limited user (no value on account).
					k_EChatRoomEnterResponseClanDisabled	8	Attempt to join a clan chat when the clan is locked or disabled.
					k_EChatRoomEnterResponseCommunityBan	9	Attempt to join a chat when the user has a community lock on their account.
					k_EChatRoomEnterResponseMemberBlockedYou	10	Join failed - a user that is in the chat has blocked you from joining.
					k_EChatRoomEnterResponseYouBlockedMember	11	Join failed - you have blocked a user that is already in the chat.
					k_EChatRoomEnterResponseRatelimitExceeded	15	Join failed - too many join attempts in a very short period of time.
				]]

				local responses = {
					[2] = 	"$lobby_error_doesnt_exist", 		-- Lobby code doesn't exist
					[3] = 	"$lobby_error_no_permissions", 		-- You don't have permission to join the lobby
					[4] = 	"$lobby_error_full", 				-- Lobby is full
					[5] = 	"$lobby_error_unexpected", 			-- Unexpected error
					[6] = 	"$lobby_error_banned", 				-- You are banned from this lobby
					[7] = 	"$lobby_error_limited", 			-- Joining this lobby is not allowed because you are a limited user
					[8] = 	"$lobby_error_clan_disabled", 		-- Attempt to join a clan lobby when the clan is locked or disabled
					[9] = 	"$lobby_error_community_ban", 		-- Attempt to join a lobby when the user has a community lock on their account
					[10] = 	"$lobby_error_member_blocked_you", 	-- Join failed - a user that is in the lobby has blocked you from joining
					[11] = 	"$lobby_error_you_blocked_member", 	-- Join failed - you have blocked a user that is already in the lobby
					[15] = 	"$lobby_error_ratelimit_exceeded", 	-- Join failed - too many join attempts in a very short period of time
				}

				msg.log(GameTextGetTranslatedOrNot(responses[data.response] or "$lobby_error_unexpected"))
			end
		end).catch(function(ex)
			exception_log:print(tostring(ex))
			if(exceptions_in_logger)then
				old_print(tostring(ex))
			end
		end)
	end

	lobby_owner = nil

	local last_user_in_game_states = {}

	function steam.matchmaking.onLobbyDataUpdate(update_data)
		print("Lobby data updated")
		try(function()
			if(lobby_code ~= nil)then
				local current_lobby_data = {}
				local any_updated = false


				if(update_data.userID ~= update_data.lobbyID)then
					local in_game_state = steam.matchmaking.getLobbyMemberData(lobby_code, update_data.userID, "in_game")
					if(last_user_in_game_states[update_data.userID] ~= in_game_state)then
						print("User in game state changed")
						last_user_in_game_states[update_data.userID] = in_game_state
						steamutils.getLobbyMembers(lobby_code, true, true)
					end
				end

				local lobby_data_count = steam.matchmaking.getLobbyDataCount(lobby_code)
				for i = 1, lobby_data_count do
					local data = steam.matchmaking.getLobbyDataByIndex(lobby_code, i -1 )
					current_lobby_data[data.key] = data.value

					-- if data.key ends with _spectator, then we need to update the spectator list
					if(string.sub(data.key, -10) == "_spectator")then
						steamutils.getLobbyMembers(lobby_code, true, true)
					end
					
					if(cached_lobby_data[data.key] ~= data.value)then
						cached_lobby_data[data.key] = data.value
					end

					--print("Lobby data: " .. data.key .. " = " .. data.value)
					if(not lobby_data_last_frame[data.key] or lobby_data_last_frame[data.key] ~= data.value)then
						lobby_data_updated_this_frame[data.key] = true
						print("Updated lobby data: " .. data.key .. " to " .. data.value)

						-- handle special case update
						--edit_lobby_type = lobby_type -- steam.matchmaking.getLobbyData(code, "LobbyType")
						--edit_lobby_max_players = lobby_max_players  --  steam.matchmaking.getLobbyMemberLimit(code)"MaxPlayers"
						--edit_lobby_name = lobby_name -- steam.matchmaking.getLobbyData(code, "name")
						--edit_lobby_seed = lobby_seed -- steam.matchmaking.getLobbyData(code, "seed")

						if(data.key == "LobbyType")then
							edit_lobby_type = data.value
						elseif(data.key == "max_players")then
							edit_lobby_max_players = data.value
						elseif(data.key == "name")then
							edit_lobby_name = data.value
						elseif(data.key == "seed")then
							edit_lobby_seed = data.value
						end

						any_updated = true
					end
				end
				lobby_data_last_frame = current_lobby_data

				if(not any_updated)then
					-- try to update lobby owner
					lobby_owner = steam.matchmaking.getLobbyOwner(lobby_code)
				end
			else
				lobby_data_last_frame = {}
				lobby_data_updated_this_frame = {}
			end
		end).catch(function(ex)
			exception_log:print(tostring(ex))
			if(exceptions_in_logger)then
				old_print(tostring(ex))
			end
		end)
	end


	ChatMemberStateChangeEnum = {
		k_EChatMemberStateChangeEntered = 1,
		k_EChatMemberStateChangeLeft = 2,
		k_EChatMemberStateChangeDisconnected = 4,
		k_EChatMemberStateChangeKicked = 8,
		k_EChatMemberStateChangeBanned = 10,
	}

	total_lobby_members = 0

	function steam.matchmaking.onLobbyChatUpdate(data)
		try(function()

			if handleBanCheck(data.userChanged) then
				return
			end
			if handleInProgressCheck(data.userChanged) then
				return
			end

			lobby_owner = steam.matchmaking.getLobbyOwner(lobby_code)
			total_lobby_members = steam.matchmaking.getNumLobbyMembers(lobby_code)
			
			if(lobby_code ~= nil)then
				steam_utils.getLobbyMembers(lobby_code, true, true)

				if (lobby_gamemode ~= nil) then
					local lobby_name = steam.matchmaking.getLobbyData(lobby_code, "name")
					steam.friends.setRichPresence( "status", "Noita Online || "..GameTextGetTranslatedOrNot(tostring(lobby_gamemode.name)))
					steam.friends.setRichPresence( "steam_player_group", lobby_name )
					
					local member_count = steam.matchmaking.getNumLobbyMembers(lobby_code)

					steam.friends.setRichPresence( "steam_player_group_size", tostring(member_count) )

				end


				if(data.chatMemberStateChange == ChatMemberStateChangeEnum.k_EChatMemberStateChangeEntered)then

					if (lobby_gamemode == nil) then
						return
					end

					print("A player joined!")

					local h = data.userChanged

					steamutils.getUserAvatar(h)

					getLobbyUserData(lobby_code, h, true)

					if (not active_members[tostring(h)]) then
						active_members[tostring(h)] = h
					end
					
					--print("Clearing frames for " .. tostring(h))
					member_message_frames[tostring(h)] = nil
				
					local name = steamutils.getTranslatedPersonaName(h)

					GamePrint(string.format(GameTextGetTranslatedOrNot("$mp_player_joined") ,tostring(name)))
					


					if(lobby_gamemode.player_join)then
						lobby_gamemode.player_join(lobby_code, h)
					end
				else
					local h = data.userChanged

					if(h == nil or tonumber(tostring(h)) == nil or tonumber(tostring(h)) == 0)then
						GamePrint("A player has left but their steamid was invalid: "..tostring(h))
						print("A player has left but their steamid was invalid: "..tostring(h))
					else
						GamePrint(string.format(GameTextGetTranslatedOrNot("$mp_player_left"), steamutils.getTranslatedPersonaName(h)))
					end

					active_members[tostring(h)] = nil

					--print("Clearing frames for " .. tostring(h))
					member_message_frames[tostring(h)] = nil
					steam.networking.closeSession(h)
					mp_log:print("Closed session with " .. steamutils.getTranslatedPersonaName(h))

					-- run gamemode on_leave
					if (lobby_gamemode and lobby_gamemode.disconnected ~= nil) then
						lobby_gamemode.disconnected(lobby_code, h)
					end
				end
			end
		end).catch(function(ex)
			exception_log:print(tostring(ex))
			if(exceptions_in_logger)then
				old_print(tostring(ex))
			end
		end)
	end

	function steam.matchmaking.onGameLobbyJoinRequested(data)
		---pretty.table(data)
		if (steam.extra.isSteamIDValid(data.lobbyID)) then
			gamemode_settings = {}
			steam_utils.Leave(data.lobbyID)
			steam.matchmaking.joinLobby(data.lobbyID, function(e)
				if (e.response == 2) then
					cached_lobby_data = {}
					cached_lobby_user_data = {}
					steam_utils.Leave(e.lobbyID)
					invite_menu_open = false
					menu_status = status.main_menu
					initial_refreshes = 10
					show_lobby_code = false
					lobby_code = nil
				end
			end)
		else
			-- force refresh
			refreshLobbies()
		end
	end

	function steam.matchmaking.onLobbyChatMsgReceived(data)
		try(function()
			--pretty.table(data)
			--[[
				example data:

				{
					lobbyID = 9223372036854775807,
					userID = 76361198523269435,
					type = 1,
					chatID = 1,
					fromOwner = true,
					message = "disconnect;76561198983269435;You were kicked from the lobby."
				}
			]]
			mp_log:print(tostring(data.message))

			handleDisconnect(data)
			handleChatMessage(data)

		end).catch(function(ex)
			exception_log:print(tostring(ex))
			if(exceptions_in_logger)then
				old_print(tostring(ex))
			end
		end)
	end

	--[[
	function steam.networking.onP2PSessionRequest(data)
		pretty.table(data)
		--steam.networking.acceptP2PSessionWithUser(data.userID)
	end

	function steam.networking.onP2PSessionConnectFail(data)
		pretty.table(data)
	end
	]]
	function steam.networking.onSessionRequest(steamID)
		mp_log:print("Session request from [" .. tostring(steamutils.getTranslatedPersonaName(steamID)) .. "]")
		if (lobby_code ~= nil and steamutils.isInLobby(lobby_code, steamID)) then
			local success = steam.networking.acceptSession(steamID)
			mp_log:print("Session accepted: " .. tostring(success))
		end
	end

	function steam.networking.onSessionFailed(steamID, endReason, endDebug, connectionDescription)
		if (lobby_code ~= nil and steamutils.isInLobby(lobby_code, steamID)) then
			mp_log:print("Session failed with [" ..
				tostring(steamutils.getTranslatedPersonaName(steamID)) .. "]: " .. tostring(endReason))
			mp_log:print("Debug: " .. tostring(endDebug))
			mp_log:print("Connection description: " .. tostring(connectionDescription))
		end
	end

	steam_overlay_open = false

	function steam.friends.onGameOverlayActivated(data)

		-- print data
		--print(inspect(data))


		if (not data.active) then
			--print("Overlay closed")
			steam_overlay_open = false
		else
			--print("Overlay opened")
			steam_overlay_open = true
		end
	end

	function OnMagicNumbersAndWorldSeedInitialized()
		if(failed_to_load)then
			return
		end

		--print(json.stringify(char_ranges))
		-- write to file
		-- ModTextFileGetContent("data/translations/common.csv")
		-- using io library to write to "noita_online_logs/translations.csv"
		local file = io.open("noita_online_logs/translations.csv", "w")
		local translations_content = ModTextFileGetContent("data/translations/common.csv")
		file:write(translations_content)
		file:close()
		
		--print(translations_content)
		steam.init()

		__loaded["mods/evaisa.mp/data/gamemodes.lua"] = nil
		gamemodes = dofile("mods/evaisa.mp/data/gamemodes.lua")


		steam.friends.setRichPresence("status", "Noita Online - Menu")

		--[[if(GameSDK == nil)then
			GameSDK = require("game_sdk")

			discord_sdk = GameSDK.initialize(discord_app_id)
		end]]

		


		mod_data = ModData()

		debug_info:print("Gamemodes: [")

		-- get installed modes
		for k, v in ipairs(gamemodes)do
			debug_info:print("  "..tostring(v.id).."@"..tostring(v.version))
		end

		debug_info:print("]")

		debug_info:print("Installed mods: [")
		-- get installed mods

		for k, v in ipairs(ModGetActiveModIDs())do
			debug_info:print("  "..tostring(v))
		end

		debug_info:print("]")
		

		--[[
		http_get("http://evaisa.dev/noita-online-checksum.txt", function (data)
			
			Checksum_passed = data == Version_string

			if(Checksum_passed)then
				mp_log:print("Checksum passed: "..tostring(data))
			end
		end)]]
	end

	function OnWorldInitialized()
		--pretty.table(physics)
		ModTextFileGetContent = get_content
		ModTextFileSetContent = set_content
	end

	local fix_falsely_enabled_gamemodes = function()
		print("Fixing falsely enabled gamemodes")

		local save_folder = os.getenv('APPDATA'):gsub("\\Roaming", "") ..
			"\\LocalLow\\Nolla_Games_Noita\\save00\\mod_config.xml"

		local subscribed_items = steam.UGC.getSubscribedItems()
		local item_infos = {}

		for _, v in ipairs(subscribed_items) do

			local success, size, folder, timestamp = steam.UGC.getItemInstallInfo(v)
			if (success) then
				item_infos[tostring(v)] = {size = size, folder = folder, timestamp = timestamp}
			end

		end

		local file, err = io.open(save_folder, 'rb')
		if file then
			
			local content = file:read("*all")

			local parsedModData = nxml.parse(content)
			for elem in parsedModData:each_child() do
				if (elem.name == "Mod") then
					local modID = elem.attr.name
					local steamID = elem.attr.workshop_item_id

					if (ModIsEnabled(modID)) then
						local infoFile = "mods/" .. modID .. "/mod.xml"
						if (steamID ~= "0") then
							if(item_infos[steamID])then
								infoFile = item_infos[steamID].folder .. "/mod.xml"
							else
								debug_log:print("Failed to find item info for: " .. steamID)
								infoFile = nil
							end
						end

						if (infoFile ~= nil) then
							local file2, err = io.open(infoFile, 'rb')
							if file2 then
								local content2 = file2:read("*all")
								if(content2 ~= nil and content2 ~= "")then
									local parsedModInfo = nxml.parse(content2)

									local download_link = parsedModInfo.attr.download_link
									local is_game_mode = parsedModInfo.attr.is_game_mode == "1"

									if (elem.attr.enabled == "1" and is_game_mode) then
										elem.attr.enabled = "0"
										print("Disabling " .. modID)
									end
								end
							end
						end
					end
				end
			end
			file:close()


			local new_content = tostring(parsedModData)
			
			local file, err = io.open(save_folder, 'wb')
			if file then
				file:write(new_content)
				file:close()
			end
			
		end
	end

	function OnPlayerSpawned(player)

		-- make popup
		local streaming, streaming_app = streaming.IsStreaming()
		if(ModSettingGet("evaisa.mp.streamer_mode_detection") and streaming and not ModSettingGet("evaisa.mp.streamer_mode"))then
			popup.create("streaming_message", GameTextGetTranslatedOrNot("$mp_streamer_mode_popup"),{ 
				{
					text = string.format(GameTextGetTranslatedOrNot("$mp_streamer_mode_popup_detected"), streaming_app),
					color = {217 / 255, 52 / 255, 52 / 255, 1}
				},
				GameTextGetTranslatedOrNot("$mp_streamer_mode_popup_desc"),
				GameTextGetTranslatedOrNot("$mp_streamer_mode_popup_desc2")
			}, {
				{
					text = GameTextGetTranslatedOrNot("$mp_streamer_mode_popup_enable"),
					callback = function()
						ModSettingSet("evaisa.mp.streamer_mode", true)
					end
				},
				{
					text = GameTextGetTranslatedOrNot("$mp_close_popup"),
					callback = function()
					end
				}
			}, -6000)
			
		end

		fix_falsely_enabled_gamemodes()
		ModSettingRemove("lobby_data_store")
		GameRemoveFlagRun("game_paused")
		rand = rng.new(os.time()+GameGetFrameNum())
		delay.reset()
		is_awaiting_spectate = false
		--ModSettingRemove("lobby_data_store")
		--print(pretty.table(bitser))

		-- replace contents of "mods/evaisa.forcerestart/filechange.txt" with a random number between 0 and 10000000
		--local file = io.open("mods/evaisa.forcerestart/filechange.txt", "w")
		--file:write(math.random(0, 10000000))
		--file:close()

		--mp_log:print(bitser.loads(""))

		Spawned = true
	end

else
	function OnPlayerSpawned(player)
		popup.create("msvcp140_missing", GameTextGetTranslatedOrNot("$mp_msvcp140_missing"), {
			{
				text = GameTextGetTranslatedOrNot("$mp_msvcp140_missing_description"),
				color = {217 / 255,52 / 255,52 / 255, 1}
			},
			{
				text = GameTextGetTranslatedOrNot("$mp_msvcp140_missing_description_2"),
				color = {217 / 255,52 / 255,52 / 255, 1}
			},
		}, {
			{
				text = GameTextGetTranslatedOrNot("$mp_msvcp140_install"),
				callback = function()
					os.execute("start explorer \"https://aka.ms/vs/17/release/vc_redist.x86.exe\"")
				end
			}
		}, -6000)
	end

	function OnWorldPreUpdate()
		popup.update()
	end

end
