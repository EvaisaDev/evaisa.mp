local vc_test = {}

local STATE_IDLE      = "idle"
local STATE_RECORDING = "recording"
local STATE_STOPPED   = "stopped"

local INSTANT_DELAY_FRAMES = 2 * 60
local MIC_TEST_DELAY_FRAMES = 30

local state          = STATE_IDLE
local window_open    = false
local instant_mode   = false
local mic_test_mode  = false
local recorded_audio = nil
local instant_queue  = {}
local mic_test_queue = {}
local gui_id_base    = 9700
local noita_gui      = nil

local function loopback_receive(chunk)
    if voicechat == nil then return end
    if voicechat.is_recording() then
        voicechat.record_chunk(chunk)
    end
    if instant_mode then
        table.insert(instant_queue, { data = chunk, frame = GameGetFrameNum() + INSTANT_DELAY_FRAMES })
    end
    if mic_test_mode then
        table.insert(mic_test_queue, { data = chunk, frame = GameGetFrameNum() + MIC_TEST_DELAY_FRAMES })
    end
end

vc_test.toggle_window = function()
    window_open = not window_open
end

vc_test.is_open = function()
    return window_open
end

vc_test.is_mic_testing = function()
    return mic_test_mode
end

vc_test.toggle_mic_test = function()
    mic_test_mode = not mic_test_mode
    mic_test_queue = {}
end

vc_test.loopback_receive = loopback_receive

local function start_recording()
    if voicechat == nil then return end
    state = STATE_RECORDING
    recorded_audio = nil
    instant_queue = {}
    voicechat.start_recording()
end

local function stop_recording()
    if voicechat == nil then return end
    recorded_audio = voicechat.stop_recording()
    state = STATE_STOPPED
end

local function play_recorded()
    if voicechat == nil or recorded_audio == nil or recorded_audio == "" then return end
    voicechat.play_direct(recorded_audio)
end

vc_test.update = function()
    if not window_open and not mic_test_mode then return end

    if mic_test_mode and #mic_test_queue > 0 then
        local frame = GameGetFrameNum()
        local i = 1
        while i <= #mic_test_queue do
            local entry = mic_test_queue[i]
            if frame >= entry.frame then
                if voicechat ~= nil then
                    voicechat.play_direct(entry.data)
                end
                table.remove(mic_test_queue, i)
            else
                i = i + 1
            end
        end
    end

    if not window_open then return end

    if instant_mode and #instant_queue > 0 then
        local frame = GameGetFrameNum()
        local i = 1
        while i <= #instant_queue do
            local entry = instant_queue[i]
            if frame >= entry.frame then
                if voicechat ~= nil then
                    voicechat.play_voice(entry.data, 0, 0)
                end
                table.remove(instant_queue, i)
            else
                i = i + 1
            end
        end
    end

    if imgui ~= nil then
        vc_test.draw_imgui()
    else
        vc_test.draw_gui()
    end
end

vc_test.draw_imgui = function()
    if imgui.Begin("Voice Chat Test  [Ctrl+Shift+V]") then
        imgui.Text("Loopback test: audio is captured, sent through")
        imgui.Text("the network message system to yourself, then recorded.")
        imgui.Separator()

        local _, new_instant = imgui.Checkbox("Instant Playback (2s delay)", instant_mode)
        if new_instant ~= instant_mode then
            instant_mode = new_instant
            instant_queue = {}
        end

        imgui.Separator()

        if state == STATE_IDLE then
            if imgui.Button("Start Recording") then
                start_recording()
            end
        elseif state == STATE_RECORDING then
            imgui.TextColored(1, 0.2, 0.2, 1, "* Recording...")
            if imgui.Button("Stop Recording") then
                stop_recording()
            end
        elseif state == STATE_STOPPED then
            local audio_len = recorded_audio and #recorded_audio or 0
            local seconds = audio_len / (8000 * 2)
            imgui.Text(string.format("Recorded: %.2f seconds (%d bytes)", seconds, audio_len))

            if imgui.Button("Play") then
                play_recorded()
            end
            imgui.SameLine()
            if imgui.Button("Record Again") then
                start_recording()
            end
            imgui.SameLine()
            if imgui.Button("Clear") then
                state = STATE_IDLE
                recorded_audio = nil
            end
        end

        imgui.Separator()
        local status_str = "Status: " .. state
        if instant_mode and #instant_queue > 0 then
            status_str = status_str .. " | queued: " .. #instant_queue
        end
        imgui.Text(status_str)
    end
    imgui.End()
end

local function get_gui()
    if noita_gui == nil then
        noita_gui = GuiCreate()
    end
    return noita_gui
end

vc_test.draw_gui = function()
    local gui = get_gui()
    GuiStartFrame(gui)

    local win_x = 10
    local win_y = 80
    local im_id = gui_id_base

    local function next_id()
        im_id = im_id + 1
        return im_id
    end

    GuiText(gui, win_x, win_y, "[ Voice Chat Test ] (Ctrl+Shift+V to close)")

    local instant_label = instant_mode and "[x] Instant Playback (5s delay)" or "[ ] Instant Playback (5s delay)"
    local instant_clicked = GuiButton(gui, next_id(), win_x, win_y + 12, instant_label)
    if instant_clicked then
        instant_mode = not instant_mode
        instant_queue = {}
    end

    if state == STATE_IDLE then
        local clicked = GuiButton(gui, next_id(), win_x, win_y + 26, "Start Recording")
        if clicked then
            start_recording()
        end
    elseif state == STATE_RECORDING then
        GuiText(gui, win_x, win_y + 26, "* Recording  (Ctrl+Shift+V toggles window)")
        local clicked = GuiButton(gui, next_id(), win_x, win_y + 38, "Stop Recording")
        if clicked then
            stop_recording()
        end
    elseif state == STATE_STOPPED then
        local audio_len = recorded_audio and #recorded_audio or 0
        local seconds = audio_len / (8000 * 2)
        GuiText(gui, win_x, win_y + 26, string.format("Recorded: %.1fs (%d bytes)", seconds, audio_len))

        local play_clicked = GuiButton(gui, next_id(), win_x, win_y + 38, "Play")
        if play_clicked then
            play_recorded()
        end
        local again_clicked = GuiButton(gui, next_id(), win_x + 32, win_y + 38, "Record Again")
        if again_clicked then
            start_recording()
        end
        local clear_clicked = GuiButton(gui, next_id(), win_x, win_y + 50, "Clear")
        if clear_clicked then
            state = STATE_IDLE
            recorded_audio = nil
        end
    end

    if instant_mode and #instant_queue > 0 then
        GuiText(gui, win_x, win_y + 64, "Queued chunks: " .. #instant_queue)
    end
end

return vc_test
