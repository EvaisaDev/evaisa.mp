lobby_count = lobby_count or 0
lobbies = lobbies or { friend = {}, public = {} }

distance = {
	close = "Close",
	default = "Default",
	far = "Far",
	worldwide = "Worldwide"
}

disconnect_message = disconnect_message or ""
banned_members = banned_members or {}

local function SplitMessage(message, characters)
	-- split string at first space after X characters
	-- concatenate with \n\t
	local split = {}
	local i = 1
	while i <= #message do
		local j = i + characters
		if j > #message then
			j = #message
		end
		local k = string.find(message, " ", j)
		if k == nil then
			k = #message
		end
		table.insert(split, string.sub(message, i, k))
		i = k + 1
	end
	return table.concat(split, "\n")
end

function handleDisconnect(data)
	local message = data.message
	local split_data = {}
	for token in string.gmatch(message, "[^;]+") do
		table.insert(split_data, token)
	end

	if (#split_data >= 3) then
		if (split_data[1] == "disconnect") then
			if (split_data[2] == tostring(steam_utils.getSteamID())) then
				msg.log("You were disconnected from the lobby.")
				steam_utils.Leave(data.lobbyID)
				invite_menu_open = false
				menu_status = status.disconnected
				disconnect_message = SplitMessage(split_data[3], 30)
				show_lobby_code = false
				lobby_code = nil
				banned_members = {}
			end
		end
	end
end

function disconnect(data)
	msg.log("You were disconnected from the lobby.")
	steam_utils.Leave(data.lobbyID)
	menu_status = status.disconnected
	disconnect_message = SplitMessage(data.message, 30)
end

function handleBanCheck(user)
	if(lobby_code == nil)then
		return false
	end
	if (banned_members[tostring(user)] ~= nil or steam_utils.IsPlayerBlacklisted(user)) then
		mp_log:print("Disconnected member: " .. tostring(user))
		banned_members[tostring(user)] = true
		steam.matchmaking.kickUserFromLobby(lobby_code, user, GameTextGetTranslatedOrNot("$mp_banned_warning"))
		return true
	end
	return false
end

function handleInProgressCheck(user)
	if(lobby_code == nil)then
		return false
	end
	local is_in_progress = steam.matchmaking.getLobbyData(lobby_code, "in_progress") or "false"
	local allow_in_progress_joining = steam.matchmaking.getLobbyData(lobby_code, "allow_in_progress_joining") or "true"
	--print(is_in_progress)
	--print(allow_in_progress_joining)
	if(is_in_progress == "true" and allow_in_progress_joining == "false")then
		mp_log:print("Disconnected member: " .. tostring(user))
		steam.matchmaking.kickUserFromLobby(lobby_code, user, GameTextGetTranslatedOrNot("$mp_in_progress_warning"))
		return true
	end
	return false
end

function handleVersionCheck()
	local version = steam.matchmaking.getLobbyData(lobby_code, "version")
	if (version > tostring(MP_VERSION)) then
		disconnect({
			lobbyID = lobby_code,
			message = GameTextGetTranslatedOrNot("$mp_client_outdated")
		})
		return false
	elseif (version < tostring(MP_VERSION)) then
		disconnect({
			lobbyID = lobby_code,
			message = GameTextGetTranslatedOrNot("$mp_host_outdated")
		})
		return false
	end
	return true
end

function handleGamemodeVersionCheck(lobbycode)
	local gamemode_version = steam.matchmaking.getLobbyData(lobbycode, "gamemode_version")
	local game_version_hash = steam.matchmaking.getLobbyData(lobbycode, "game_version_hash")
	local active_mode = FindGamemode(steam.matchmaking.getLobbyData(lobbycode, "gamemode"))
	--local gamemode = steam.matchmaking.getLobbyData(lobbycode, "gamemode")
	mp_log:print("Gamemode: " .. tostring(active_mode.id))
	mp_log:print("Version: " .. tostring(gamemode_version))
	mp_log:print("Game version hash: " .. tostring(game_version_hash))
	if (active_mode ~= nil and gamemode_version ~= nil) then
		if (active_mode ~= nil) then
			if (active_mode.version > tonumber(gamemode_version)) then
				disconnect({
					lobbyID = lobbycode,
					message = string.format(GameTextGetTranslatedOrNot("$mp_host_gamemode_outdated"), GameTextGetTranslatedOrNot(active_mode.name))
				})
				return false
			elseif (active_mode.version < tonumber(gamemode_version)) then
				disconnect({
					lobbyID = lobbycode,
					message = string.format(GameTextGetTranslatedOrNot("$mp_client_gamemode_outdated"), GameTextGetTranslatedOrNot(active_mode.name))
				})
				return false
			elseif (game_version_hash ~= tostring(noita_version_hash))then
				disconnect({
					lobbyID = lobbycode,
					message = GameTextGetTranslatedOrNot("$mp_game_version_mismatch")
				})
				return false
			end
		else
			disconnect({
				lobbyID = lobbycode,
				message = string.format(GameTextGetTranslatedOrNot("$mp_gamemode_missing"), GameTextGetTranslatedOrNot(active_mode.name))
			})
			return false
		end
	end
	return true
end

function HasRequiredMods(lobby)
	local required_mod_string = steam.matchmaking.getLobbyData(lobby, "required_mods") or ""

	--print(required_mod_string)

	local required_mods = required_mod_string ~= "" and bitser.loads(required_mod_string) or {}

	local player_mods = ModData()

	--print(json.stringify(required_mods))

	
	for i = #required_mods, 1, -1 do
		local v = required_mods[i]
		for k2, v2 in pairs(player_mods) do
			if (v2.id == v[1]) then
				table.remove(required_mods, i)
			end
		end
	end

	if (#required_mods > 0) then
		return false
	end
	
	return true
end

local cached_correct_lobbies = {}
function IsCorrectVersion(lobby)
	if (cached_correct_lobbies[lobby] ~= nil) then
		return cached_correct_lobbies[lobby]
	end
	local version = steam.matchmaking.getLobbyData(lobby, "version")
	local gamemode_version = steam.matchmaking.getLobbyData(lobby, "gamemode_version")
	local game_version_hash = steam.matchmaking.getLobbyData(lobby, "game_version_hash")
	--local gamemode = steam.matchmaking.getLobbyData(lobby, "gamemode")
	local active_mode = FindGamemode(steam.matchmaking.getLobbyData(lobby, "gamemode"))
	if (version ~= tostring(MP_VERSION)) then
		cached_correct_lobbies[lobby] = false
		return false
	end
	if (game_version_hash ~= tostring(noita_version_hash))then
		cached_correct_lobbies[lobby] = false
		return false
	end
	if (active_mode ~= nil and gamemode_version ~= nil) then

		if (active_mode.version ~= tonumber(gamemode_version)) then
			cached_correct_lobbies[lobby] = false
			return false
		end
	else
		cached_correct_lobbies[lobby] = false
		return false
	end

	cached_correct_lobbies[lobby] = true
	return true
end

function VersionInfo(lobby)
	-- return version info
	local info = {
		mp_version_same = true,
		mp_version_string = GameTextGetTranslatedOrNot("$mp_lobby_info_same_version"),
		mp_version_string_user = "",
		gamemode_version_same = true,
		gamemode_missing = false,
		gamemode_version_string = "",
		gamemode_version_string_user = "",
		game_version_same = true,
		game_version_string = GameTextGetTranslatedOrNot("$mp_lobby_info_game_same_version"),
		game_version_string_user = ""
	}

	local version = steam.matchmaking.getLobbyData(lobby, "version")
	local gamemode_version = steam.matchmaking.getLobbyData(lobby, "gamemode_version")
	local game_version_hash = steam.matchmaking.getLobbyData(lobby, "game_version_hash") or "missing"
	local game_version = steam.matchmaking.getLobbyData(lobby, "game_version") or "missing"

	if(version < tostring(MP_VERSION))then
		info.mp_version_same = false
		info.mp_version_string = string.format(GameTextGetTranslatedOrNot("$mp_lobby_info_host_older"), version)
		info.mp_version_string_user = string.format(GameTextGetTranslatedOrNot("$mp_lobby_info_you_using"), MP_VERSION)
	elseif(version > tostring(MP_VERSION))then
		info.mp_version_same = false
		info.mp_version_string = string.format(GameTextGetTranslatedOrNot("$mp_lobby_info_host_newer"), version)
		info.mp_version_string_user = string.format(GameTextGetTranslatedOrNot("$mp_lobby_info_you_using"), MP_VERSION)
	end

	if(game_version_hash ~= tostring(noita_version_hash))then
		info.game_version_same = false
		info.game_version_string = string.format(GameTextGetTranslatedOrNot("$mp_lobby_info_game_host_diff"), game_version)
		info.game_version_string_user = string.format(GameTextGetTranslatedOrNot("$mp_lobby_info_you_using"), noita_version)
	end

	local active_mode = FindGamemode(steam.matchmaking.getLobbyData(lobby, "gamemode"))

	if(active_mode == nil)then
		info.gamemode_missing = true
		info.gamemode_version_same = false
		info.gamemode_version_string = string.format(GameTextGetTranslatedOrNot("$mp_lobby_info_gm_missing"), steam.matchmaking.getLobbyData(lobby, "gamemode"), gamemode_version)
	else
		if(active_mode.version > tonumber(gamemode_version))then
			info.gamemode_version_same = false
			info.gamemode_version_string = string.format(GameTextGetTranslatedOrNot("$mp_lobby_info_gm_host_older"), GameTextGetTranslatedOrNot(active_mode.name), gamemode_version)
			info.gamemode_version_string_user = string.format(GameTextGetTranslatedOrNot("$mp_lobby_info_you_using"), active_mode.version)
		elseif(active_mode.version < tonumber(gamemode_version))then
			info.gamemode_version_same = false
			info.gamemode_version_string = string.format(GameTextGetTranslatedOrNot("$mp_lobby_info_gm_host_newer"), GameTextGetTranslatedOrNot(active_mode.name), gamemode_version)
			info.gamemode_version_string_user = string.format(GameTextGetTranslatedOrNot("$mp_lobby_info_you_using"), active_mode.version)
		else
			info.gamemode_version_same = true
			info.gamemode_version_string = string.format(GameTextGetTranslatedOrNot("$mp_lobby_info_gm_same_version"), GameTextGetTranslatedOrNot(active_mode.name))
			info.gamemode_version_string_user = ""
		end
	end


	return info
	
end

function ModInfo(lobby)
	local info = {
		missing_mods = {},
		missing_mods_string = ""
	}

	local required_mods = (steam.matchmaking.getLobbyData(lobby, "required_mods") ~= nil and steam.matchmaking.getLobbyData(lobby, "required_mods") ~= "") and bitser.loads(steam.matchmaking.getLobbyData(lobby, "required_mods")) or {}

	local player_mods = ModData()

	--print(json.stringify(required_mods))

	
	for i = #required_mods, 1, -1 do
		local v = required_mods[i]
		for k2, v2 in pairs(player_mods) do
			if (v2.id == v[1]) then
				table.remove(required_mods, i)
			end
		end
	end

	if (#required_mods > 0) then
		for i, v in ipairs(required_mods) do
			table.insert(info.missing_mods, v[2])
		end
		info.missing_mods_string = string.format(GameTextGetTranslatedOrNot("$mp_lobby_info_missing_mods_list"), table.concat(info.missing_mods, ", "))
	end

	-- remove trailing comma
	if (string.sub(info.missing_mods_string, -2) == ", ") then
		info.missing_mods_string = string.sub(info.missing_mods_string, 1, -3)
	end

	return info

end

local inspect = dofile("mods/evaisa.mp/lib/inspect.lua")

function string_split(str, sep)
    local ret = {}

    local value_start = 1

    while true do
        local skip_start, skip_end = utf8.find(str, sep, value_start, true)
        skip_start = skip_start or #str + 1
        skip_end = skip_end or #str + 1

        if value_start <= skip_start then
            local value = utf8.sub(str, value_start, skip_start - 1)
            value_start = skip_end + 1
            ret[#ret + 1] = value
        else
            return ret
        end
    end
end


function SerializeModData(data)
	local serialized = ""
	--print(inspect(data))
	for i, v in ipairs(data) do
		local name = (v.name or ""):gsub("\x01", "")
		local description = (v.description or ""):gsub("\x01", "")
		local download_link = (v.download_link or ""):gsub("\x01", "")
		serialized = serialized .. (v.workshop_item_id or "0") .. "\x01" .. (v.id or "") .. "\x01" .. name .. "\x01" .. description .. "\x01" .. download_link
		if (i < #data) then
			serialized = serialized .. "\x01"
		end
	end
	--print(serialized)
	return serialized
end

function DeserializeModData(data)
	local split_data = string_split(data, "\x01")
	local mod_data = {}
	for i = 1, #split_data, 5 do
		table.insert(mod_data, {
			workshop_item_id = split_data[i],
			id = split_data[i + 1],
			name = split_data[i + 2],
			description = split_data[i + 3],
			download_link = split_data[i + 4]
		})
	end
	--print(inspect(mod_data))
	return mod_data
end



function ModData()
	local nxml = dofile("mods/evaisa.mp/lib/nxml.lua")
	local save_folder = os.getenv('APPDATA'):gsub("\\Roaming", "") ..
		"\\LocalLow\\Nolla_Games_Noita\\save00\\mod_config.xml"

	local file, err = io.open(save_folder, 'rb')
	if file then

		mp_log:print("Reading mod config file")

		local content = file:read("*all")

		local data = {
		}

		local subscribed_items = steam.UGC.getSubscribedItems()
		local item_infos = {}
	
		for _, v in ipairs(subscribed_items) do
	
			local success, size, folder, timestamp = steam.UGC.getItemInstallInfo(v)
			if (success) then
				item_infos[tostring(v)] = {size = size, folder = folder, timestamp = timestamp}
			end
	
		end

		if (StreamingGetIsConnected()) then
			table.insert(data,
				{
					workshop_item_id = "0",
					name = GameTextGetTranslatedOrNot("$mp_mod_twitch_integration_name"),
					description = GameTextGetTranslatedOrNot("$mp_mod_twitch_integration_description"),
				})
		end

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

					if(infoFile)then
						local file2, err = io.open(infoFile, 'rb')
						if file2 then
							local content2 = file2:read("*all")
							if(content2 ~= nil and content2 ~= "")then
								local parsedModInfo = nxml.parse(content2)

								local download_link = parsedModInfo.attr.download_link

								if (elem.attr.enabled == "1") then
									table.insert(data,
										{
											workshop_item_id = steamID,
											id = modID,
											name = parsedModInfo.attr.name,
											description = parsedModInfo.attr.description,
											download_link = download_link,
										})
								end
							end
						end
					end
				end
			end
		end

		file:close()

		--mp_log:print("Mod data: "..json.stringify(data))

		return data
	end
	return nil
end

function defineLobbyUserData(lobby)
	local mod_data = ModData()
	if (mod_data ~= nil) then
		steam.matchmaking.setLobbyMemberData(lobby, "mod_data", SerializeModData(mod_data))
	end
end

function handleModCheck()
	local required_mods = (steam.matchmaking.getLobbyData(lobby_code, "required_mods") ~= nil and steam.matchmaking.getLobbyData(lobby_code, "required_mods") ~= "") and bitser.loads(steam.matchmaking.getLobbyData(lobby_code, "required_mods")) or {}

	local player_mods = ModData()

	--print(json.stringify(required_mods))

	
	for i = #required_mods, 1, -1 do
		local v = required_mods[i]
		for k2, v2 in pairs(player_mods) do
			if (v2.id == v[1]) then
				table.remove(required_mods, i)
			end
		end
	end

	if (#required_mods > 0) then

		local mods_string = ""
		for i, v in ipairs(required_mods) do
			if(i == #required_mods) then
				mods_string = mods_string .. v[2] .. " ("..v[1]..")"
			else
				mods_string = mods_string .. v[2] .. " ("..v[1].."), "
			end
		end

		disconnect({
			lobbyID = lobby_code,
			message = string.format(GameTextGetTranslatedOrNot("$mp_client_missing_mods"), mods_string)
		})
		return false
	end
	
	return true
end



cached_lobby_user_data = cached_lobby_user_data or {}

function getLobbyUserData(lobby, userid, force)
	if(cached_lobby_user_data[userid] ~= nil and force ~= true)then
		return cached_lobby_user_data[userid]
	end
	if(lobby == nil) then
		return nil
	end
	if(userid == nil)then
		return nil
	end 
	local player_mod_data = steam.matchmaking.getLobbyMemberData(lobby, userid, "mod_data")
	if (player_mod_data ~= nil and player_mod_data ~= "") then
		local data_received = DeserializeModData(player_mod_data)
		cached_lobby_user_data[userid] = data_received
		return data_received
	end
	return nil
end


function getFriendLobbies()
	local friend_lobbies = {}

	local friends = steamutils.getSteamFriends();

	for k, v in pairs(friends) do
		local game_info = steam.friends.getFriendGamePlayed(v.id)

		if (game_info and game_info.gameID == game_id and tostring(game_info.lobbyID) ~= "0" and game_info.lobbyID ~= nil) then
			table.insert(friend_lobbies, game_info.lobbyID)
		end
	end

	return friend_lobbies
end

function refreshLobbies()
	lobbies = { friend = {}, public = {} }
	local indexed_lobby = {}

	--steam.matchmaking.addRequestLobbyListStringFilter("LobbyType", "Public", "Equal")
	steam.matchmaking.addRequestLobbyListDistanceFilter(distance[lobby_filter_distance] or distance.worldwide)

	local activeSystem = "NoitaOnline"

	if (dev_mode) then
		activeSystem = "NoitaOnlineDev"
	end

	steam.matchmaking.addRequestLobbyListStringFilter("System", activeSystem, "Equal")
	

	for _, lobby in ipairs(getFriendLobbies()) do
		if (lobby ~= nil) then
			if (indexed_lobby[lobby] == nil) then
				if (steam.matchmaking.requestLobbyData(lobby)) then
					local lobby_type = steam.matchmaking.getLobbyData(lobby, "LobbyType")

					if (steam.matchmaking.getLobbyData(lobby, "System") ~= nil and steam.matchmaking.getLobbyData(lobby, "System") == activeSystem) then
						local banned = steam.matchmaking.getLobbyData(lobby, "banned_" ..tostring(steam_utils.getSteamID()))
						if ((lobby_type == "Public" or lobby_type == "FriendsOnly") and banned ~= "true") then
							table.insert(lobbies.friend, lobby)
							indexed_lobby[lobby] = true
						end
					end
				end
			end
		end
	end

	steam.matchmaking.requestLobbyList(function(data)
		lobby_count = data.count
		if (lobby_count > 0) then
			for i = 0, lobby_count - 1 do
				local lobby = steam.matchmaking.getLobbyByIndex(i)
				if (lobby.lobbyID ~= nil) then
					local lobby_type = steam.matchmaking.getLobbyData(lobby.lobbyID, "LobbyType")

					if (steam.matchmaking.getLobbyData(lobby.lobbyID, "System") ~= nil and steam.matchmaking.getLobbyData(lobby.lobbyID, "System") == activeSystem) then
						local banned = steam.matchmaking.getLobbyData(lobby.lobbyID,
							"banned_" .. tostring(steam_utils.getSteamID()))
						if ((lobby_type == "Public" or lobby_type == "FriendsOnly") and banned ~= "true") then
							if (indexed_lobby[lobby.lobbyID] == nil) then
								--indexed_lobby[lobby.lobbyID] = true
								table.insert(lobbies.public, lobby.lobbyID)
							end
						end
					end
				end
			end
		end
	end)


	return lobbies
end

function StartGame()
	local lobby_gamemode = FindGamemode(steam.matchmaking.getLobbyData(lobby_code, "gamemode"))

	if handleVersionCheck() and handleModCheck() then
		if handleGamemodeVersionCheck(lobby_code) then
			if (lobby_gamemode) then

				spectating = steamutils.IsSpectator(lobby_code)

				--print("Are we spectating? " .. tostring(spectating))

				if (spectating) then
					if (lobby_gamemode.spectate ~= nil) then
						lobby_gamemode.spectate(lobby_code)
					elseif (lobby_gamemode.start ~= nil) then
						lobby_gamemode.start(lobby_code)
					end
				else
					if (lobby_gamemode.start ~= nil) then
						lobby_gamemode.start(lobby_code)
					end
				end

				steam.matchmaking.setLobbyMemberData(lobby_code, "in_game", "true")

				in_game = true
				game_in_progress = true

				gui_closed = true
			else
				disconnect({
					lobbyID = lobby_code,
					message = string.format(GameTextGetTranslatedOrNot("$mp_gamemode_missing"), tostring(steam.matchmaking.getLobbyData(lobby_code, "gamemode")))
				})
			end
		end
	end
end

function StopGame()
	local lobby_gamemode = FindGamemode(steam.matchmaking.getLobbyData(lobby_code, "gamemode"))

	if handleVersionCheck() and handleModCheck() then
		if handleGamemodeVersionCheck(lobby_code) then
			if (lobby_gamemode) then
				if (lobby_gamemode.stop ~= nil) then
					lobby_gamemode.stop(lobby_code)
				end

				if(steamutils.IsOwner())then
					steam_utils.TrySetLobbyData(lobby_code, "in_progress", "false")
				end

				in_game = false
				game_in_progress = false

				gui_closed = false
			else
				disconnect({
					lobbyID = lobby_code,
					message = string.format(GameTextGetTranslatedOrNot("$mp_gamemode_missing"), tostring(steam.matchmaking.getLobbyData(lobby_code, "gamemode")))
				})
			end
		end
	end
end