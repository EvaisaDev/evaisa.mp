local profile = dofile("mods/evaisa.mp/lib/profile.lua")

local profile_next = false
local profile_next_no_ui = false
local get_profiler_rate = function()
    return math.floor(tonumber(ModSettingGet("evaisa.mp.profiler_rate")) or 1)
end

local profiler_rate = get_profiler_rate()

local profiler_folder_name = "noita_online_logs/profiler"

-- create profiler folder
if not os.rename(profiler_folder_name, profiler_folder_name) then
	os.execute("mkdir \"" .. profiler_folder_name .. "\"")
end

local profiler_result_file = nil
local profiler_result_content = ""

local profiler_ui = {}

local did_frame = false
local profiler_paused = false
local profiler_frames = {}
local profiler_data = {}
local profiler_steps = 0

local generate_profiler_data = function() 
    profiler_data = {}
    local label_indices = {}
    local curr_frame = profiler_steps - #profiler_frames

    -- Precompute sums and organize data
    for i = 1, #(profiler_frames) do
        local v = profiler_frames[i]
        for j = 1, #v do
            local data = v[j]
            local label = data[1]

            if label_indices[label] == nil then
                label_indices[label] = {index = #profiler_data + 1, sum_calls = 0, sum_times = 0}
                profiler_data[label_indices[label].index] = {label, {{}, {}, {}}}
            end

            local entry = profiler_data[label_indices[label].index][2]
            table.insert(entry[1], curr_frame + i)
            table.insert(entry[2], data[2])
            table.insert(entry[3], data[3])

            -- Precompute sums
            label_indices[label].sum_times = label_indices[label].sum_times + data[2]
            label_indices[label].sum_calls = label_indices[label].sum_calls + data[3]
        end
    end

    -- Choose the index for sorting based on use_calls flag
    local sort_index = use_calls and "sum_calls" or "sum_times"

    -- Sort profiler_data based on precomputed sums
    table.sort(profiler_data, function(a, b)
        return label_indices[a[1]][sort_index] > label_indices[b[1]][sort_index]
    end)

    -- remove all but top 50
    if(#profiler_data > 50)then
        for i = 51, #profiler_data do
            profiler_data[i] = nil
        end
    end
end

profiler_ui.apply_profiler_rate = function()
    profiler_rate = get_profiler_rate()
end

profiler_ui.pre_update = function()

    if(not profiler_paused and (profile_next or profile_next_no_ui) and GameGetFrameNum() % profiler_rate == 0)then
        did_frame = true
        profile.start()
        --print("Profiling frame: "..GameGetFrameNum())
    else
        did_frame = false
    end


    if (input ~= nil and input:WasKeyPressed("f8")) then
        profile_next_no_ui = false
        profile_next = not profile_next
        if(profile_next)then
            profile.clear()
            profiler_result_file = io.open(profiler_folder_name.."/"..os.date("%Y-%m-%d_%H-%M-%S")..".csv", "w+")
            profiler_result_content = "Snapshot,Rank,Function,Calls,Time,Avg. Time,Code\n"

            profiler_frames = {}
            profiler_data = {}
            profiler_steps = 0
            print("Starting profiler")
        else
            profile.clear()
            if(profiler_result_file ~= nil)then
                profiler_result_file:write(profiler_result_content)
                profiler_result_file:close()
                profiler_result_file = nil
            end
            print("Stopping profiler")
        end
    end 

    if (input ~= nil and input:WasKeyPressed("f7")) then
        profile_next = false
        profile_next_no_ui = not profile_next_no_ui
        if(profile_next_no_ui)then
            profile.clear()
            profiler_result_file = io.open(profiler_folder_name.."/"..os.date("%Y-%m-%d_%H-%M-%S")..".csv", "w+")
            profiler_result_content = "Snapshot,Rank,Function,Calls,Time,Avg. Time,Code\n"

            profiler_frames = {}
            profiler_data = {}
            profiler_steps = 0
            print("Starting profiler without UI")
        else
            profile.clear()
            if(profiler_result_file ~= nil)then
                profiler_result_file:write(profiler_result_content)
                profiler_result_file:close()
                profiler_result_file = nil
            end
            print("Stopping profiler without UI")
        end

    end
end

profiler_ui.end_profile = function()
    profile.stop()

    --local profiler_data = profile.csv(150)

    local frame = {}

    local report = profile.query(500)

    for i, row in ipairs(report) do
        local rank = row[1]
        local func = row[2]
        local calls = row[3]
        local time = row[4]
        local avg_time = row[5]
        local code = row[6]

        local untruncated_func = func
        local untruncated_code = code

        -- truncate func after first space
        func = string.match(func, "^[^ ]+")
        code = string.match(code, "^[^ ]+")

        local label = table.concat({code, " - ", func, "##", untruncated_func, untruncated_code}, "")


        -- add to profiler frames
        

        table.insert(frame, {label, time, calls})

    end

    table.insert(profiler_frames, frame)

    profiler_steps = profiler_steps + 1

    -- if profiler frames over 1000 then remove the first one
    if(#profiler_frames > 1000)then
        table.remove(profiler_frames, 1)
    end


    if(profiler_steps % 10 == 0)then
        generate_profiler_data()
    end



    profile.reset()
end

profiler_ui.draw = function()
    if imgui.Begin("Profiler") then
        -- add checkbox for auto scrolling
        -- add button for clearing data

        if imgui.Button("Clear data") then
            profile.clear()
            profiler_data = {}
            profiler_frames = {}
            profiler_steps = 0
        end

        imgui.SameLine()
        
        if(auto_scroll_profiler == nil)then
            auto_scroll_profiler = true
        end

        if(use_calls == nil)then
            use_calls = false
        end

        -- checkbox
        local _
        _, auto_scroll_profiler = imgui.Checkbox("Auto scroll", auto_scroll_profiler)

        imgui.SameLine()
        local old_use_calls = use_calls
        _, use_calls = imgui.Checkbox("Use calls", use_calls)

        if(old_use_calls ~= use_calls)then
            generate_profiler_data()
        end


        imgui.SameLine()

        if imgui.Button(profiler_paused and "Unpause" or "Pause") then
            profiler_paused = not profiler_paused
        end


        if implot.BeginPlot("Profiler") then

            local label_y = "time"

            if(use_calls)then
                label_y = "calls"
            end

            implot.SetupAxes("frame", label_y, auto_scroll_profiler and implot.PlotAxisFlags.Lock or implot.PlotAxisFlags.None, (auto_scroll_profiler and implot.PlotAxisFlags.AutoFit or implot.PlotAxisFlags.None));
            
            

            if(auto_scroll_profiler)then
                implot.SetupAxisLimits(implot.Axis.X1, math.max(profiler_steps - 100, 0), math.max(profiler_steps, 100), implot.PlotCond.Always)
            else
                implot.SetupAxisLimits(implot.Axis.X1, 0, 100)
            end

            implot.SetupLegend(implot.PlotLocation.East, implot.PlotLegendFlags.Outside)

            -- we need to defined them in time order
            local ind = 2

            if(use_calls)then
                ind = 3
            end

            for i = 1, #profiler_data do
                local p = profiler_data[i]
                local label = p[1]
                local data = p[2]

                implot.SetNextMarkerStyle(implot.PlotMarker.Circle, 1);
                implot.PlotLine(label, data[1], data[ind])

            end
            
            implot.EndPlot()
        end

        imgui.End()
    end
end

profiler_ui.post_update = function()
    if(did_frame)then
        profiler_ui.end_profile()
    end

    if(imgui ~= nil and profile_next)then
        profiler_ui.draw()
    end
end

return profiler_ui