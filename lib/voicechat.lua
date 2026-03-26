local ffi = require("ffi")
local bit = require("bit")

local smallfolk = dofile_once("mods/evaisa.mp/lib/smallfolk.lua")

pcall(ffi.cdef, [[
typedef uint32_t SDL_AudioDeviceID;
typedef uint16_t SDL_AudioFormat_vc;
typedef void (*SDL_AudioCallback_vc)(void *userdata, uint8_t *stream, int len);
typedef struct SDL_AudioSpec_vc {
    int freq;
    SDL_AudioFormat_vc format;
    uint8_t channels;
    uint8_t silence;
    uint16_t samples;
    uint16_t padding;
    uint32_t size;
    SDL_AudioCallback_vc callback;
    void *userdata;
} SDL_AudioSpec_vc;
int SDL_InitSubSystem(uint32_t flags);
int SDL_GetNumAudioDevices(int iscapture);
const char *SDL_GetAudioDeviceName(int index, int iscapture);
SDL_AudioDeviceID SDL_OpenAudioDevice(const char *device, int iscapture,
    const SDL_AudioSpec_vc *desired, SDL_AudioSpec_vc *obtained, int allowed_changes);
void SDL_PauseAudioDevice(SDL_AudioDeviceID dev, int pause_on);
uint32_t SDL_DequeueAudio(SDL_AudioDeviceID dev, void *data, uint32_t len);
uint32_t SDL_GetQueuedAudioSize(SDL_AudioDeviceID dev);
void SDL_ClearQueuedAudio(SDL_AudioDeviceID dev);
void SDL_CloseAudioDevice(SDL_AudioDeviceID dev);
const char *SDL_GetError(void);
]])

pcall(ffi.cdef, [[
typedef int FMOD_RESULT;
typedef struct FMOD_SYSTEM FMOD_SYSTEM;
typedef struct FMOD_SOUND FMOD_SOUND;
typedef struct FMOD_CHANNEL FMOD_CHANNEL;
typedef struct FMOD_CHANNELGROUP FMOD_CHANNELGROUP;
typedef struct FMOD_VECTOR {
    float x; float y; float z;
} FMOD_VECTOR;
typedef struct FMOD_EXINFO_VOICE {
    int cbsize;
    unsigned int length;
    unsigned int fileoffset;
    int numchannels;
    int defaultfrequency;
    int format;
} FMOD_EXINFO_VOICE;
static const int FMOD_OK_VC = 0;
static const unsigned int FMOD_DEFAULT_VC      = 0x00000000;
static const unsigned int FMOD_LOOP_OFF_VC     = 0x00000001;
static const unsigned int FMOD_3D_VC           = 0x00000010;
static const unsigned int FMOD_OPENMEMORY_VC   = 0x00000800;
static const unsigned int FMOD_OPENRAW_VC      = 0x00001000;
static const unsigned int FMOD_INIT_NORMAL_VC  = 0x00000000;
FMOD_RESULT FMOD_System_Create(FMOD_SYSTEM **system);
FMOD_RESULT FMOD_System_Init(FMOD_SYSTEM *system, int maxchannels, unsigned int flags, void *extradriverdata);
FMOD_RESULT FMOD_System_CreateSound(FMOD_SYSTEM *system, const char *name_or_data, unsigned int mode, FMOD_EXINFO_VOICE *exinfo, FMOD_SOUND **sound);
FMOD_RESULT FMOD_System_PlaySound(FMOD_SYSTEM *system, FMOD_SOUND *sound, FMOD_CHANNELGROUP *channelgroup, int paused, FMOD_CHANNEL **channel);
FMOD_RESULT FMOD_System_Set3DListenerAttributes(FMOD_SYSTEM *system, int listener, const FMOD_VECTOR *pos, const FMOD_VECTOR *vel, const FMOD_VECTOR *forward, const FMOD_VECTOR *up);
FMOD_RESULT FMOD_System_Update(FMOD_SYSTEM *system);
FMOD_RESULT FMOD_System_Close(FMOD_SYSTEM *system);
FMOD_RESULT FMOD_System_Release(FMOD_SYSTEM *system);
FMOD_RESULT FMOD_Sound_Release(FMOD_SOUND *sound);
FMOD_RESULT FMOD_Channel_Set3DAttributes(FMOD_CHANNEL *channel, const FMOD_VECTOR *pos, const FMOD_VECTOR *vel);
FMOD_RESULT FMOD_Channel_SetPaused(FMOD_CHANNEL *channel, int paused);
FMOD_RESULT FMOD_Channel_Stop(FMOD_CHANNEL *channel);
FMOD_RESULT FMOD_Channel_Set3DMinMaxDistance(FMOD_CHANNEL *channel, float min, float max);
FMOD_RESULT FMOD_Channel_SetVolume(FMOD_CHANNEL *channel, float volume);
FMOD_RESULT FMOD_Channel_IsPlaying(FMOD_CHANNEL *channel, int *isplaying);
typedef struct FMOD_DSP FMOD_DSP;
FMOD_RESULT FMOD_System_CreateDSPByType(FMOD_SYSTEM *system, int type, FMOD_DSP **dsp);
FMOD_RESULT FMOD_Channel_AddDSP(FMOD_CHANNEL *channel, int index, FMOD_DSP *dsp);
FMOD_RESULT FMOD_DSP_SetParameterFloat(FMOD_DSP *dsp, int index, float value);
FMOD_RESULT FMOD_DSP_Release(FMOD_DSP *dsp);
]])

local sdl = ffi.load("SDL2")
local fmod = ffi.load("fmod")

local SDL_INIT_AUDIO = 0x00000010
local FMOD_SOUND_FORMAT_PCM16 = 2

local SAMPLE_RATE = 48000
local CHANNELS = 1
local BYTES_PER_SAMPLE = 2
local CHUNK_FRAMES = 9
local CHUNK_BYTES = SAMPLE_RATE * CHANNELS * BYTES_PER_SAMPLE * CHUNK_FRAMES / 60

local M = {}

local capture_dev = 0
local playback_dev = 0
local pcm_accum = {}
local pcm_accum_bytes = 0

local listener_x = 0
local listener_y = 0

local VOICE_MIN_DIST = 50.0
local VOICE_MAX_DIST = 3000.0

local fmod_system = nil
local playing_voices = {}
local pending_voices = {}
local update_tick = 0

local function resample_pcm(pcm_data, target_rate)
    if target_rate == SAMPLE_RATE then return pcm_data end
    local factor = SAMPLE_RATE / target_rate
    local n_in = #pcm_data / 2
    local n_out = math.max(1, math.floor(n_in / factor))
    local in_buf = ffi.new("int16_t[?]", n_in)
    ffi.copy(in_buf, pcm_data, #pcm_data)
    local out_buf = ffi.new("int16_t[?]", n_out)
    for i = 0, n_out - 1 do
        out_buf[i] = in_buf[math.floor(i * factor)]
    end
    return ffi.string(out_buf, n_out * 2)
end

local last_mic_level = 0.0
local gate_gain = 0.0
local GATE_RAMP_RATE = 1.0 / 480

M.get_mic_level = function()
    return last_mic_level
end

local function init_sdl_audio()
    sdl.SDL_InitSubSystem(SDL_INIT_AUDIO)
end

local function init_fmod_voice_system()
    if fmod_system ~= nil then return true end
    local sys_ptr = ffi.new("FMOD_SYSTEM*[1]")
    if fmod.FMOD_System_Create(sys_ptr) ~= 0 then return false end
    fmod_system = sys_ptr[0]
    if fmod.FMOD_System_Init(fmod_system, 32, fmod.FMOD_INIT_NORMAL_VC, nil) ~= 0 then
        fmod_system = nil
        return false
    end
    local pos = ffi.new("FMOD_VECTOR", { x = 0, y = 0, z = 0 })
    local vel = ffi.new("FMOD_VECTOR", { x = 0, y = 0, z = 0 })
    local fwd = ffi.new("FMOD_VECTOR", { x = 0, y = 0, z = 1 })
    local up  = ffi.new("FMOD_VECTOR", { x = 0, y = 1, z = 0 })
    fmod.FMOD_System_Set3DListenerAttributes(fmod_system, 0, pos, vel, fwd, up)
    return true
end

local function open_playback()
    if playback_dev ~= 0 then return true end
    init_sdl_audio()
    local desired = ffi.new("SDL_AudioSpec_vc")
    desired.freq = SAMPLE_RATE
    desired.format = 0x8010
    desired.channels = CHANNELS
    desired.samples = 1024
    desired.callback = nil
    local obtained = ffi.new("SDL_AudioSpec_vc")
    local dev = sdl.SDL_OpenAudioDevice(nil, 0, desired, obtained, 0)
    if dev == 0 then
        print("[voicechat] SDL playback open failed: " .. ffi.string(sdl.SDL_GetError()))
        return false
    end
    playback_dev = dev
    sdl.SDL_PauseAudioDevice(playback_dev, 0)
    return true
end

local function queue_pcm_with_gain(pcm_data, gain)
    if not open_playback() then return end
    local pcm_len = #pcm_data
    local n = pcm_len / 2
    local buf = ffi.new("int16_t[?]", n)
    ffi.copy(buf, pcm_data, pcm_len)
    if gain < 0.999 then
        for i = 0, n - 1 do
            local s = buf[i] * gain
            if s > 32767 then s = 32767 elseif s < -32768 then s = -32768 end
            buf[i] = s
        end
    end
    sdl.SDL_QueueAudio(playback_dev, buf, pcm_len)
end

local cached_devices = nil

M.enumerate_devices = function()
    init_sdl_audio()
    local count = sdl.SDL_GetNumAudioDevices(1)
    local devices = {}
    for i = 0, count - 1 do
        local name = ffi.string(sdl.SDL_GetAudioDeviceName(i, 1))
        table.insert(devices, name)
    end
    cached_devices = devices
    pcall(GlobalsSetValue, "evaisa.mp.audio_devices", smallfolk.dumps(devices))
    return devices
end

M.get_devices = function()
    if cached_devices ~= nil then return cached_devices end
    local ok, raw = pcall(GlobalsGetValue, "evaisa.mp.audio_devices", "")
    if not ok or raw == "" then return {} end
    return smallfolk.loads(raw)
end

M.open_capture = function(device_name)
    if capture_dev ~= 0 then
        sdl.SDL_CloseAudioDevice(capture_dev)
        capture_dev = 0
    end

    init_sdl_audio()

    local desired = ffi.new("SDL_AudioSpec_vc")
    desired.freq = SAMPLE_RATE
    desired.format = 0x8010
    desired.channels = CHANNELS
    desired.samples = 512
    desired.callback = nil

    local obtained = ffi.new("SDL_AudioSpec_vc")

    local dev_name_ptr = nil
    if device_name and device_name ~= "" then
        dev_name_ptr = device_name
    end

    local dev = sdl.SDL_OpenAudioDevice(dev_name_ptr, 1, desired, obtained, 0)
    if dev == 0 then
        return false
    end

    capture_dev = dev
    sdl.SDL_PauseAudioDevice(capture_dev, 0)
    return true
end

M.close_capture = function()
    if capture_dev ~= 0 then
        sdl.SDL_CloseAudioDevice(capture_dev)
        capture_dev = 0
    end
end

M.capture_tick = function(ptt_held)
    if capture_dev == 0 then return nil end

    local buf_size = 4096
    local buf = ffi.new("uint8_t[?]", buf_size)
    local got = sdl.SDL_DequeueAudio(capture_dev, buf, buf_size)

    local target_gain = ptt_held and 1.0 or 0.0

    if got > 0 then
        local n_samples = got / 2
        local samples = ffi.cast("int16_t*", buf)
        local sum_sq = 0.0
        for i = 0, n_samples - 1 do
            local s = samples[i] / 32768.0
            sum_sq = sum_sq + s * s
        end
        last_mic_level = math.sqrt(sum_sq / n_samples) * (tonumber(ModSettingGet("evaisa.mp.voicechat_mic_volume")) or 1.0)
    else
        last_mic_level = last_mic_level * 0.85
    end

    if target_gain == 0.0 and gate_gain == 0.0 then
        sdl.SDL_ClearQueuedAudio(capture_dev)
        pcm_accum = {}
        pcm_accum_bytes = 0
        return nil
    end

    if got == 0 then
        if target_gain == 0.0 then
            gate_gain = 0.0
            sdl.SDL_ClearQueuedAudio(capture_dev)
            pcm_accum = {}
            pcm_accum_bytes = 0
        end
        return nil
    end

    local n_samples = got / 2
    local samples = ffi.cast("int16_t*", buf)
    local mic_vol = tonumber(ModSettingGet("evaisa.mp.voicechat_mic_volume")) or 1.0
    for i = 0, n_samples - 1 do
        if target_gain > gate_gain then
            gate_gain = math.min(1.0, gate_gain + GATE_RAMP_RATE)
        elseif target_gain < gate_gain then
            gate_gain = math.max(0.0, gate_gain - GATE_RAMP_RATE)
        end
        local s = samples[i] * gate_gain * mic_vol
        if s > 32767 then s = 32767 elseif s < -32768 then s = -32768 end
        samples[i] = s
    end

    if gate_gain == 0.0 then
        pcm_accum = {}
        pcm_accum_bytes = 0
        return nil
    end

    table.insert(pcm_accum, ffi.string(buf, got))
    pcm_accum_bytes = pcm_accum_bytes + got

    if pcm_accum_bytes >= CHUNK_BYTES then
        local chunk = table.concat(pcm_accum)
        pcm_accum = {}
        pcm_accum_bytes = 0
        return chunk
    end

    return nil
end

M.update_listener = function(x, y)
    listener_x = x
    listener_y = y
    if not init_fmod_voice_system() then return end
    local pos = ffi.new("FMOD_VECTOR", { x = x, y = y, z = 0 })
    local vel = ffi.new("FMOD_VECTOR", { x = 0, y = 0, z = 0 })
    local fwd = ffi.new("FMOD_VECTOR", { x = 0, y = 0, z = 1 })
    local up  = ffi.new("FMOD_VECTOR", { x = 0, y = 1, z = 0 })
    fmod.FMOD_System_Set3DListenerAttributes(fmod_system, 0, pos, vel, fwd, up)
end

M.play_voice = function(pcm_data, x, y, global_vol, player_vol, opts)
    opts = opts or {}
    local delay = opts.delay_frames or 0
    if delay > 0 then
        table.insert(pending_voices, {
            pcm = pcm_data, x = x, y = y,
            global_vol = global_vol, player_vol = player_vol,
            opts = opts,
            play_at = update_tick + delay
        })
        return
    end

    if not init_fmod_voice_system() then return end

    local sample_rate = opts.sample_rate or SAMPLE_RATE
    local actual_pcm = (sample_rate ~= SAMPLE_RATE) and resample_pcm(pcm_data, sample_rate) or pcm_data
    local data_len = #actual_pcm
    local c_buf = ffi.new("uint8_t[?]", data_len)
    ffi.copy(c_buf, actual_pcm, data_len)

    local exinfo = ffi.new("FMOD_EXINFO_VOICE")
    exinfo.cbsize = ffi.sizeof("FMOD_EXINFO_VOICE")
    exinfo.length = data_len
    exinfo.fileoffset = 0
    exinfo.numchannels = CHANNELS
    exinfo.defaultfrequency = sample_rate
    exinfo.format = FMOD_SOUND_FORMAT_PCM16

    local mode = bit.bor(fmod.FMOD_LOOP_OFF_VC, fmod.FMOD_OPENMEMORY_VC, fmod.FMOD_OPENRAW_VC, fmod.FMOD_3D_VC)

    local sound_ptr = ffi.new("FMOD_SOUND*[1]")
    if fmod.FMOD_System_CreateSound(fmod_system, c_buf, mode, exinfo, sound_ptr) ~= 0 then return end

    local ch_ptr = ffi.new("FMOD_CHANNEL*[1]")
    if fmod.FMOD_System_PlaySound(fmod_system, sound_ptr[0], nil, 1, ch_ptr) ~= 0 then
        fmod.FMOD_Sound_Release(sound_ptr[0])
        return
    end

    local ch = ch_ptr[0]
    local spos = ffi.new("FMOD_VECTOR", { x = x, y = y, z = 0 })
    local vel = ffi.new("FMOD_VECTOR", { x = 0, y = 0, z = 0 })
    fmod.FMOD_Channel_Set3DAttributes(ch, spos, vel)
    fmod.FMOD_Channel_Set3DMinMaxDistance(ch, VOICE_MIN_DIST, VOICE_MAX_DIST)
    fmod.FMOD_Channel_SetVolume(ch, (global_vol or 1.0) * (player_vol or 1.0))

    local entry = { sound = sound_ptr[0], channel = ch }

    if opts.reverb then
        local dsp_ptr = ffi.new("FMOD_DSP*[1]")
        if fmod.FMOD_System_CreateDSPByType(fmod_system, 18, dsp_ptr) == 0 then
            local dsp = dsp_ptr[0]
            fmod.FMOD_DSP_SetParameterFloat(dsp, 0,  opts.reverb_decay  or 1200.0)
            fmod.FMOD_DSP_SetParameterFloat(dsp, 1,  opts.reverb_early  or 15.0)
            fmod.FMOD_DSP_SetParameterFloat(dsp, 2,  opts.reverb_late   or 30.0)
            fmod.FMOD_DSP_SetParameterFloat(dsp, 9,  opts.reverb_hicut  or 4000.0)
            fmod.FMOD_DSP_SetParameterFloat(dsp, 11, opts.reverb_wet    or -3.0)
            fmod.FMOD_DSP_SetParameterFloat(dsp, 12, opts.reverb_dry    or 0.0)
            fmod.FMOD_Channel_AddDSP(ch, 0, dsp)
            entry.dsp = dsp
        end
    end

    fmod.FMOD_Channel_SetPaused(ch, 0)
    table.insert(playing_voices, entry)
end

M.update = function()
    if fmod_system == nil then return end

    update_tick = update_tick + 1

    local pi = 1
    while pi <= #pending_voices do
        local pv = pending_voices[pi]
        if update_tick >= pv.play_at then
            local fire_opts = {}
            for k, v in pairs(pv.opts) do fire_opts[k] = v end
            fire_opts.delay_frames = 0
            M.play_voice(pv.pcm, pv.x, pv.y, pv.global_vol, pv.player_vol, fire_opts)
            table.remove(pending_voices, pi)
        else
            pi = pi + 1
        end
    end

    local i = 1
    while i <= #playing_voices do
        local v = playing_voices[i]
        local is_playing = ffi.new("int[1]")
        fmod.FMOD_Channel_IsPlaying(v.channel, is_playing)
        if is_playing[0] == 0 then
            if v.dsp then fmod.FMOD_DSP_Release(v.dsp) end
            fmod.FMOD_Sound_Release(v.sound)
            table.remove(playing_voices, i)
        else
            i = i + 1
        end
    end

    fmod.FMOD_System_Update(fmod_system)
end

local recording_buffer = nil

M.start_recording = function()
    recording_buffer = {}
end

M.stop_recording = function()
    if recording_buffer == nil then return nil end
    local result = table.concat(recording_buffer)
    recording_buffer = nil
    return result
end

M.record_chunk = function(pcm_chunk)
    if recording_buffer ~= nil then
        table.insert(recording_buffer, pcm_chunk)
    end
end

M.is_recording = function()
    return recording_buffer ~= nil
end

M.play_direct = function(pcm_data)
    queue_pcm_with_gain(pcm_data, 1.0)
end

M.cleanup = function()
    M.close_capture()
    pending_voices = {}
    for _, v in ipairs(playing_voices) do
        fmod.FMOD_Channel_Stop(v.channel)
        if v.dsp then fmod.FMOD_DSP_Release(v.dsp) end
        fmod.FMOD_Sound_Release(v.sound)
    end
    playing_voices = {}
    if fmod_system ~= nil then
        fmod.FMOD_System_Close(fmod_system)
        fmod.FMOD_System_Release(fmod_system)
        fmod_system = nil
    end
    if playback_dev ~= 0 then
        sdl.SDL_CloseAudioDevice(playback_dev)
        playback_dev = 0
    end
end

return M
