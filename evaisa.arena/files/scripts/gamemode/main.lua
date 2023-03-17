local steamutils = dofile_once("mods/evaisa.mp/lib/steamutils.lua")

local data_holder = dofile("mods/evaisa.arena/files/scripts/gamemode/data.lua")
local data = nil

message_handler = dofile("mods/evaisa.arena/files/scripts/gamemode/message_handler.lua")
gameplay_handler = dofile("mods/evaisa.arena/files/scripts/gamemode/gameplay.lua")

local playerinfo_menu = dofile("mods/evaisa.arena/files/scripts/utilities/playerinfo_menu.lua")

dofile_once( "data/scripts/perks/perk_list.lua" )

perk_sprites = {}
for k, perk in pairs(perk_list)do
    perk_sprites[perk.id] = perk.ui_icon
end

playermenu = nil

ArenaMode = {
    name = "Arena",
    version = 0.200,
    enter = function(lobby)
        local game_in_progress = steam.matchmaking.getLobbyData(lobby, "in_progress") == "true"
        if(game_in_progress)then
            ArenaMode.start(lobby)
        end
        steamutils.sendData({type = "handshake"}, steamutils.messageTypes.OtherPlayers, lobby)
    end,
    start = function(lobby)
        data = data_holder:New()
        data.state = "lobby"
        data:DefinePlayers(lobby)

        steamutils.sendData({type = "handshake"}, steamutils.messageTypes.OtherPlayers, lobby)

        gameplay_handler.LoadLobby(lobby, data, true, true)

        if(playermenu ~= nil)then
            playermenu:Destroy()
        end
                
        playermenu = playerinfo_menu:New()


        message_handler.send.Handshake(lobby)
    end,
    update = function(lobby)
        gameplay_handler.Update(lobby, data)
        playermenu:Update(data, lobby)
    end,
    late_update = function(lobby)
        gameplay_handler.LateUpdate(lobby, data)
    end,
    leave = function(lobby)

    end,
    message = function(lobby, message, user)
        message_handler.handle(lobby, message, user, data)
    end,
    on_projectile_fired = function(lobby, shooter_id, projectile_id, rng, position_x, position_y, target_x, target_y, send_message)
        gameplay_handler.OnProjectileFired(lobby, data, shooter_id, projectile_id, rng, position_x, position_y, target_x, target_y, send_message)
    end,
    on_projectile_fired_post = function(lobby, shooter_id, projectile_id, rng, position_x, position_y, target_x, target_y, send_message)
        gameplay_handler.OnProjectileFiredPost(lobby, data, shooter_id, projectile_id, rng, position_x, position_y, target_x, target_y, send_message)
    end
}

table.insert(gamemodes, ArenaMode)