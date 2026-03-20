dofile_once("data/scripts/lib/utilities.lua")

voice_hud_gui = voice_hud_gui or GuiCreate()

GuiStartFrame(voice_hud_gui)

if IsPaused() then return end

GuiOptionsAdd(voice_hud_gui, GUI_OPTION.NoPositionTween)

local screen_width, screen_height = GuiGetScreenDimensions(voice_hud_gui)

local smallfolk = dofile_once("mods/evaisa.mp/lib/smallfolk.lua")

local raw = GlobalsGetValue("evaisa.mp.speaking_players", "")
local speaking = (raw ~= "" and smallfolk.loads(raw)) or {}

local frame = GameGetFrameNum()

local entries = {}
for steam_id, data in pairs(speaking) do
    if frame - data.frame < 12 then
        table.insert(entries, { steam_id = steam_id, data = data })
    end
end

if #entries == 0 then return end

table.sort(entries, function(a, b) return a.data.name < b.data.name end)

local avatar_size  = 10
local entry_w      = 80
local entry_h      = avatar_size + 2
local pad          = 2
local gap          = 2
local border       = 2
local total_h      = #entries * (entry_h + gap) - gap
local x            = 4
local y            = screen_height - 4 - total_h

for i, e in ipairs(entries) do
    local level   = e.data.level or 0
    local max_lvl = 0.1
    local filled_w = math.max(0, math.floor(math.min(level / max_lvl, 1.0) * entry_w))
    local ey = y + (i - 1) * (entry_h + gap)
    local id_base = 7180000 + i * 10

    GuiZSetForNextWidget(voice_hud_gui, 20)
    GuiImageNinePiece(voice_hud_gui, id_base + 2, x, ey, entry_w, entry_h)

    if filled_w > 0 then
        local is_local = e.data.is_local
        GuiZSetForNextWidget(voice_hud_gui, 19)
        if is_local then
            GuiColorSetForNextWidget(voice_hud_gui, 0.3, 0.75, 0.35, 0.55)
        else
            GuiColorSetForNextWidget(voice_hud_gui, 0.25, 0.55, 0.85, 0.55)
        end
        GuiImage(voice_hud_gui, id_base + 1, x, ey, "mods/evaisa.mp/files/gfx/ui/1pixel.png", 1, filled_w, entry_h, 0)
    end

    local avatar_path = steam_utils.getUserAvatar(steam.extra.parseUint64(e.steam_id))
    GuiZSetForNextWidget(voice_hud_gui, 18)
    GuiImage(voice_hud_gui, id_base + 3, x + pad, ey + 1, avatar_path, 1, avatar_size / 32, avatar_size / 32, 0)

    GuiZSetForNextWidget(voice_hud_gui, 18)
    GuiColorSetForNextWidget(voice_hud_gui, 1, 1, 1, 0.95)
    GuiText(voice_hud_gui, x + pad + avatar_size + pad, ey + 2, e.data.name)
end
