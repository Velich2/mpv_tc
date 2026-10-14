-- smpte_timecode.lua
--
-- Shows SMPTE timecode (HH:MM:SS:FF, drop-frame HH:MM:SS;FF) on the mpv OSD.
--
-- The start timecode is taken from (in order of priority):
--   1. the "set-start" script message
--   2. the start_tc option
--   3. the container metadata exposed by mpv (e.g. MXF)
--   4. ffprobe stream/format tags (e.g. the tmcd track in MOV/MP4)
--   5. 00:00:00:00
--
-- The current timecode is also published as the property
-- user-data/smpte_timecode, so it can be used in --osd-msg1,
-- --term-status-msg etc.: ${user-data/smpte_timecode}
--
-- Options: script-opts/smpte_timecode.conf or --script-opts=smpte_timecode-<name>=<value>
-- Key binding name: smpte_timecode/toggle
-- The overlay state is remembered in ~~/smpte_timecode.state (option remember)
-- and published as user-data/smpte_timecode-overlay.

local mp = require 'mp'
local options = require 'mp.options'
local utils = require 'mp.utils'

-- Another copy of this script is already loaded (e.g. from another config
-- folder); that one is in charge.
if mp.get_script_name() ~= "smpte_timecode" then
    mp.msg.verbose("Another smpte_timecode.lua is loaded, not doing anything.")
    return
end

local opts = {
    enabled = true,          -- initial state; with remember, the last toggle wins
    remember = true,         -- remember the overlay state across restarts
    -- top-left, top-center, top-right, bottom-left, bottom-center, bottom-right
    position = "top-right",
    font = "monospace",
    font_size = 36,          -- relative to a 720 px high OSD
    margin = 20,
    color = "FFFFFF",        -- RRGGBB
    border_color = "000000", -- RRGGBB
    border_size = 2,
    show_info = false,       -- second line: fps, DF/NDF, start timecode source
    start_tc = "",           -- override start timecode, e.g. 01:00:00:00 or 01:00:00;00
    drop_frame = "auto",     -- auto (from the start timecode separator), yes, no
    fps = 0,                 -- override frame rate, 0 = auto
    use_ffprobe = true,
    ffprobe_path = "ffprobe",
    ffprobe_network = false, -- also run ffprobe for network URLs
    key_toggle = "ctrl+t",
}

local ALIGN = {
    ["top-left"]      = { an = 7, x = 0,   y = 0 },
    ["top-center"]    = { an = 8, x = 0.5, y = 0 },
    ["top-right"]     = { an = 9, x = 1,   y = 0 },
    ["bottom-left"]   = { an = 1, x = 0,   y = 1 },
    ["bottom-center"] = { an = 2, x = 0.5, y = 1 },
    ["bottom-right"]  = { an = 3, x = 1,   y = 1 },
}

local overlay = mp.create_osd_overlay("ass-events")

local state = {
    gen = 0,           -- incremented per file, invalidates stale ffprobe results
    detected = nil,    -- start timecode found in the file
    source = nil,      -- where `detected` came from
    runtime_start = nil, -- set via the "set-start" script message
    tc = nil,          -- current timecode string
    info = nil,        -- current info line
    rendered = nil,    -- last overlay data
}

-- Timecode math ------------------------------------------------------------

-- "HH:MM:SS:FF" -> table; ';', '.' or ',' before the frames means drop-frame.
local function parse_tc(str)
    if type(str) ~= "string" then
        return nil
    end
    local h, m, s, sep, f =
        str:match("^%s*(%d+)[:;.,](%d%d)[:;.,](%d%d)([:;.,])(%d+)%s*$")
    if not h then
        return nil
    end
    return {
        h = tonumber(h), m = tonumber(m), s = tonumber(s), f = tonumber(f),
        df = sep ~= ":",
    }
end

-- Snaps the frame rate to an exact integer or NTSC (N*1000/1001) rate.
local function rate_info(fps)
    local nominal = math.floor(fps + 0.5)
    if nominal < 1 then
        return nil
    end
    local ntsc = nominal * 1000 / 1001
    if math.abs(fps - ntsc) < math.abs(fps - nominal) and math.abs(fps - ntsc) < 0.01 then
        return { fps = ntsc, nominal = nominal, ntsc = true }
    end
    if math.abs(fps - nominal) < 0.001 then
        fps = nominal
    end
    return { fps = fps, nominal = nominal, ntsc = false }
end

-- Drop-frame is defined only for NTSC multiples of 30 (29.97, 59.94, ...).
local function can_drop_frame(rate)
    return rate.ntsc and rate.nominal % 30 == 0
end

local function tc_to_frames(tc, nominal, df)
    local minutes = tc.h * 60 + tc.m
    local frames = (minutes * 60 + tc.s) * nominal + tc.f
    if df then
        local drop = nominal / 15
        frames = frames - drop * (minutes - math.floor(minutes / 10))
    end
    return frames
end

local function frames_to_tc(frames, nominal, df)
    if df then
        -- Frame numbers ;00 and ;01 (;00-;03 at 59.94) are skipped at the start
        -- of every minute except every tenth one.
        local drop = nominal / 15
        local per_10min = nominal * 600 - drop * 9
        local per_min = nominal * 60 - drop
        frames = frames % (per_10min * 144)
        local tens = math.floor(frames / per_10min)
        local rem = frames % per_10min
        frames = frames + drop * 9 * tens
        if rem >= drop then
            frames = frames + drop * math.floor((rem - drop) / per_min)
        end
    else
        frames = frames % (nominal * 86400)
    end
    local secs = math.floor(frames / nominal)
    return string.format("%02d:%02d:%02d%s%02d",
        math.floor(secs / 3600), math.floor(secs / 60) % 60, secs % 60,
        df and ";" or ":", frames % nominal)
end

-- Start timecode detection -------------------------------------------------

local function find_tc(tags)
    if type(tags) ~= "table" then
        return nil
    end
    for k, v in pairs(tags) do
        if type(k) == "string" and k:lower() == "timecode" then
            local tc = parse_tc(v)
            if tc then
                return tc
            end
        end
    end
    return nil
end

-- Prefers the video stream, then any other stream (tmcd), then the container.
local function pick_ffprobe_tc(data)
    if type(data) ~= "table" then
        return nil
    end
    local fallback
    for _, s in ipairs(data.streams or {}) do
        local tc = find_tc(s.tags)
        if tc then
            if s.codec_type == "video" then
                return tc
            end
            fallback = fallback or tc
        end
    end
    return fallback or find_tc(data.format and data.format.tags)
end

local function is_network(path)
    local proto = path:match("^(%a[%w+.-]*)://")
    return proto ~= nil and proto:lower() ~= "file"
end

local update

local function probe_with_ffprobe(path)
    local gen = state.gen
    mp.command_native_async({
        name = "subprocess",
        args = {
            opts.ffprobe_path, "-v", "error",
            "-show_entries", "format_tags=timecode:stream=codec_type:stream_tags=timecode",
            "-of", "json", "-i", path,
        },
        capture_stdout = true,
        capture_stderr = true,
    }, function(success, result)
        if gen ~= state.gen or state.detected then
            return
        end
        if not success or not result or result.status ~= 0 then
            mp.msg.verbose("ffprobe failed: " .. tostring(result and result.stderr or result))
            return
        end
        local tc = pick_ffprobe_tc(utils.parse_json(result.stdout or ""))
        if tc then
            state.detected, state.source = tc, "ffprobe"
            update()
        end
    end)
end

local function detect_start()
    state.gen = state.gen + 1
    state.detected, state.source = nil, nil

    local tc = find_tc(mp.get_property_native("metadata"))
    if tc then
        state.detected, state.source = tc, "metadata"
        return
    end

    local path = mp.get_property("path")
    if opts.use_ffprobe and path and (opts.ffprobe_network or not is_network(path)) then
        probe_with_ffprobe(path)
    end
end

local function active_start()
    if state.runtime_start then
        return state.runtime_start, "message"
    end
    local tc = parse_tc(opts.start_tc)
    if tc then
        return tc, "option"
    end
    if state.detected then
        return state.detected, state.source
    end
    return nil, "none"
end

-- Rendering ----------------------------------------------------------------

local function ass_color(rgb)
    rgb = tostring(rgb):gsub("^#", "")
    if not rgb:match("^%x%x%x%x%x%x$") then
        rgb = "FFFFFF"
    end
    return rgb:sub(5, 6) .. rgb:sub(3, 4) .. rgb:sub(1, 2)
end

local function render()
    if not opts.enabled or not state.tc then
        if state.rendered then
            overlay:remove()
            state.rendered = nil
        end
        return
    end

    local w, h = mp.get_osd_size()
    if not w or w <= 0 or h <= 0 then
        return
    end
    local res_y = 720
    local res_x = math.floor(res_y * w / h + 0.5)
    local align = ALIGN[opts.position] or ALIGN["top-right"]
    local x = opts.margin + (res_x - 2 * opts.margin) * align.x
    local y = opts.margin + (res_y - 2 * opts.margin) * align.y

    local text = state.tc
    if opts.show_info and state.info then
        text = string.format("%s\\N{\\fs%d}%s", text, math.floor(opts.font_size * 0.5 + 0.5), state.info)
    end
    local data = string.format(
        "{\\an%d\\pos(%d,%d)\\fn%s\\fs%d\\bord%s\\shad0\\1c&H%s&\\3c&H%s&}%s",
        align.an, x, y, opts.font, opts.font_size, opts.border_size,
        ass_color(opts.color), ass_color(opts.border_color), text)

    if data ~= state.rendered or overlay.res_x ~= res_x then
        overlay.res_x, overlay.res_y = res_x, res_y
        overlay.data = data
        overlay:update()
        state.rendered = data
    end
end

local function get_fps()
    if opts.fps > 0 then
        return opts.fps
    end
    local fps = mp.get_property_number("container-fps")
    if not fps or fps <= 0 then
        fps = mp.get_property_number("estimated-vf-fps")
    end
    if not fps or fps <= 0 then
        return nil
    end
    return fps
end

local function format_fps(fps)
    return (string.format("%.3f", fps):gsub("0+$", ""):gsub("%.$", ""))
end

update = function()
    local t = mp.get_property_number("time-pos")
    local fps = get_fps()
    local rate = fps and rate_info(fps)
    local tc

    if t and rate then
        local start, source = active_start()
        local df
        if not can_drop_frame(rate) or opts.drop_frame == "no" then
            df = false
        elseif opts.drop_frame == "yes" then
            df = true
        else
            df = start ~= nil and start.df
        end
        local start_frames = start and tc_to_frames(start, rate.nominal, df) or 0
        local frame = math.floor(t * rate.fps + 0.5)
        tc = frames_to_tc(start_frames + frame, rate.nominal, df)
        state.info = string.format("%s %s | %s", format_fps(rate.fps), df and "DF" or "NDF", source)
    end

    if tc ~= state.tc then
        state.tc = tc
        mp.set_property("user-data/smpte_timecode", tc or "")
    end
    render()
end

-- Events and bindings ------------------------------------------------------

local STATE_FILE = "~~/smpte_timecode.state"

local function state_path()
    if not opts.remember or not mp.get_property_bool("config") then
        return nil
    end
    return mp.command_native({"expand-path", STATE_FILE})
end

local function load_enabled()
    local path = state_path()
    local file = path and io.open(path)
    if not file then
        return
    end
    local saved = file:read("*l")
    file:close()
    if saved == "on" or saved == "off" then
        opts.enabled = saved == "on"
    end
end

local function save_enabled()
    local path = state_path()
    if not path then
        return
    end
    local file = io.open(path, "w")
    if not file then
        mp.msg.warn("Could not save the overlay state to " .. path)
        return
    end
    file:write(opts.enabled and "on" or "off", "\n")
    file:close()
end

local function publish_enabled()
    mp.set_property_native("user-data/smpte_timecode-overlay", opts.enabled)
end

options.read_options(opts, "smpte_timecode", function()
    state.rendered = nil
    publish_enabled()
    update()
end)
load_enabled()
publish_enabled()

mp.register_event("file-loaded", function()
    state.runtime_start = nil
    detect_start()
    update()
end)

mp.register_event("end-file", function()
    state.gen = state.gen + 1
    state.tc = nil
    mp.set_property("user-data/smpte_timecode", "")
    render()
end)

mp.observe_property("time-pos", "number", update)
mp.observe_property("container-fps", "number", update)
mp.observe_property("osd-dimensions", "native", function()
    state.rendered = nil
    render()
end)

mp.add_key_binding(opts.key_toggle ~= "" and opts.key_toggle or nil, "toggle", function()
    opts.enabled = not opts.enabled
    publish_enabled()
    save_enabled()
    render()
    mp.osd_message("SMPTE timecode: " .. (opts.enabled and "on" or "off"))
end)

-- script-message-to smpte_timecode set-start 01:00:00:00
-- Without an argument, reverts to the detected start timecode.
mp.register_script_message("set-start", function(str)
    local tc = parse_tc(str)
    if str and str ~= "" and not tc then
        mp.osd_message("SMPTE timecode: invalid start " .. str)
        return
    end
    state.runtime_start = tc
    update()
end)
