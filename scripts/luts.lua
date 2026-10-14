-- luts.lua
--
-- Applies a 3D/1D LUT (.cube, .3dl, .dat, .m3d, .csp) to the video, chosen
-- from a menu. LUTs are read from the "luts" folders of the mpv config
-- directories (the user's, and the one shipped next to mpv.exe or inside
-- mpv.app); each subfolder is a submenu.
--
-- LUT input is RGB with video levels mapped to 0-1 (as in DaVinci Resolve);
-- the output is treated as Rec.709 / BT.1886.
--
-- With --vo=gpu-next, .cube LUTs are applied on the GPU (--lut). While the
-- DeckLink output is on, or for other LUT formats, the LUT is applied as a
-- video filter on the CPU instead, so that the DeckLink output gets it too.
--
-- Menu: script-binding luts/select (also in the mpv menu of the mpv_tc build)
-- The chosen LUT is remembered in ~~/luts.state (option remember) and
-- published as user-data/lut ("" when off).
--
-- Options: script-opts/luts.conf or --script-opts=luts-<name>=<value>

local mp = require 'mp'
local options = require 'mp.options'
local utils = require 'mp.utils'
local input = require 'mp.input'

-- Another copy of this script is already loaded (e.g. from another config
-- folder): mpv names the second one luts2. The first one is in charge.
if mp.get_script_name():match("^luts%d+$") then
    mp.msg.info("Another luts.lua is already loaded, this copy is not used.")
    return
end

-- This file, to find the luts folder shipped next to it.
local script_path = debug.getinfo(1, "S").source:match("^@(.*)$")

local opts = {
    dir = "",         -- LUT folder; empty: "luts" in every mpv config folder
    remember = true,
    mode = "auto",    -- auto, gpu (--lut), cpu (video filter)
    key_menu = "",    -- e.g. ctrl+l
}
options.read_options(opts, "luts")

local EXTENSIONS = { cube = true, ["3dl"] = true, dat = true, m3d = true, csp = true }
local LABELS = { "mpvtc-lut-in", "mpvtc-lut", "mpvtc-lut-out" }
local STATE_FILE = "~~/luts.state"

local current = nil    -- LUT path relative to the LUT folders
local applied = nil    -- how it is applied: "gpu" or "cpu"
local temp_file = nil  -- cleaned-up copy of the LUT for the CPU path

-- The user's own --lut (e.g. a display calibration), restored when a camera
-- LUT is turned off.
local user_lut = mp.get_property("lut", "")
local user_lut_type = mp.get_property("lut-type", "auto")
local warned_user_lut = false

local function is_absolute(path)
    return path:match("^/") or path:match("^%a:[/\\]") or path:match("^[/\\][/\\]")
end

-- LUT folders, most preferred first.
local function roots()
    local candidates = opts.dir ~= "" and { opts.dir } or
        { "~~home/luts", "~~osxbundle/luts", "~~exe_dir/luts" }
    if opts.dir == "" and script_path then
        -- <folder>/scripts/luts.lua -> <folder>/luts, also when the folders
        -- above are disabled (portable_config, --config-dir, MPV_HOME).
        local dir = script_path:match("^(.*)[/\\][^/\\]+[/\\][^/\\]+$")
        if dir then
            candidates[#candidates + 1] = utils.join_path(dir, "luts")
        end
    end
    local list, seen = {}, {}
    for _, dir in ipairs(candidates) do
        local path = mp.command_native({"expand-path", dir})
        local info = path and is_absolute(path) and utils.file_info(path)
        if info and info.is_dir and not seen[path] then
            seen[path] = true
            list[#list + 1] = path
        end
    end
    return list
end

local function find_lut(rel)
    for _, root in ipairs(roots()) do
        local path = utils.join_path(root, rel)
        local info = utils.file_info(path)
        if info and info.is_file then
            return path
        end
    end
end

local function display_name(rel)
    local name = rel:gsub("%.[^./\\]+$", "")
    return (name:gsub("[/\\]", " / "))
end

local function is_lut(name)
    local ext = name:match("%.([^.]+)$")
    return ext and EXTENSIONS[ext:lower()]
end

-- Reads a .cube file. Returns nil and an error if it is not usable, else
-- { dim = 1 or 3, clean = <text FFmpeg accepts, or nil if the file is fine> }.
-- FFmpeg's parser rejects keywords it does not know (LUT_3D_INPUT_RANGE from
-- Resolve and others), which libplacebo accepts.
local function read_cube(path)
    local file = io.open(path, "rb")
    if not file then
        return nil, "cannot open the file"
    end
    local text = file:read("*a")
    file:close()

    local header, size, dim, values, changed = {}, nil, nil, 0, false
    for line in text:gmatch("[^\r\n]+") do
        local word = line:match("^%s*(%S+)")
        if not word or word:sub(1, 1) == "#" then
            -- empty line or comment
        elseif word:match("^[%d.+-]") then
            values = values + 1
        elseif word == "LUT_3D_SIZE" or word == "LUT_1D_SIZE" then
            if size then
                return nil, "more than one LUT size"
            end
            size = tonumber(line:match("SIZE%s+(%d+)"))
            dim = word == "LUT_3D_SIZE" and 3 or 1
            header[#header + 1] = line
        elseif word == "TITLE" or word == "DOMAIN_MIN" or word == "DOMAIN_MAX" then
            header[#header + 1] = line
        elseif word == "LUT_3D_INPUT_RANGE" or word == "LUT_1D_INPUT_RANGE" then
            local lo, hi = line:match("RANGE%s+(%S+)%s+(%S+)")
            if not tonumber(lo) or not tonumber(hi) then
                return nil, "invalid " .. word
            end
            header[#header + 1] = string.format("DOMAIN_MIN %s %s %s", lo, lo, lo)
            header[#header + 1] = string.format("DOMAIN_MAX %s %s %s", hi, hi, hi)
            changed = true
        else
            changed = true  -- unknown keyword, dropped
        end
    end
    if not size or size < 2 then
        return nil, "no LUT_3D_SIZE or LUT_1D_SIZE"
    end
    local expected = dim == 3 and size ^ 3 or size
    if values ~= expected then
        return nil, string.format("%d entries instead of %d", values, expected)
    end
    local clean
    if changed then
        local lines = header
        for line in text:gmatch("[^\r\n]+") do
            if line:match("^%s*[%d.+-]") then
                lines[#lines + 1] = line
            end
        end
        clean = table.concat(lines, "\n") .. "\n"
    end
    return { dim = dim, clean = clean }
end

local function temp_dir()
    return os.getenv("TMPDIR") or os.getenv("TEMP") or os.getenv("TMP") or "/tmp"
end

local function remove_temp_file()
    if temp_file then
        os.remove(temp_file)
        temp_file = nil
    end
end

-- mpv option quoting that survives any path: %<bytes>%<string>
local function quote(str)
    return "%" .. #str .. "%" .. str
end

local function use_gpu(path)
    if opts.mode == "cpu" or not path:lower():match("%.cube$") then
        return false
    end
    if opts.mode == "gpu" then
        return true
    end
    -- The DeckLink output takes the frames before the VO renders them.
    if mp.get_property("decklink-mirror", "") ~= "" then
        return false
    end
    -- The VO in use, or before it exists, the first one configured.
    local current_vo = mp.get_property("current-vo")
    if current_vo then
        return current_vo == "gpu-next"
    end
    local vo = mp.get_property_native("options/vo") or {}
    local name = vo[1] and vo[1].name or "gpu-next"
    return name == "gpu-next"
end

local function remove_lut()
    remove_temp_file()
    local ours = {}
    for _, label in ipairs(LABELS) do
        ours[label] = true
    end
    for _, filter in ipairs(mp.get_property_native("vf", {})) do
        if filter.label and ours[filter.label] then
            mp.commandv("vf", "remove", "@" .. filter.label)
        end
    end
    if applied == "gpu" then
        mp.set_property("lut", user_lut)
        mp.set_property("lut-type", user_lut_type)
    end
    applied = nil
end

-- Treat the LUT output as Rec.709 / BT.1886, whatever the file is tagged as.
local OUTPUT_TAGS = "format=primaries=bt.709:gamma=bt.1886"

-- Returns true, or false and an error message.
local function add_lut(path)
    local cube
    if path:lower():match("%.cube$") then
        local err
        cube, err = read_cube(path)
        if not cube then
            return false, err
        end
    end

    if use_gpu(path) then
        if user_lut ~= "" and not warned_user_lut then
            mp.msg.warn("Your --lut is replaced while a LUT from the menu is on.")
            warned_user_lut = true
        end
        mp.set_property("lut-type", "native")
        mp.set_property("lut", path)
        if mp.commandv("vf", "add", "@" .. LABELS[3] .. ":" .. OUTPUT_TAGS) then
            applied = "gpu"
            return true
        end
        mp.set_property("lut", user_lut)
        mp.set_property("lut-type", user_lut_type)
        return false, "could not add the video filter"
    end

    if cube and cube.clean then
        temp_file = utils.join_path(temp_dir(), string.format("mpv-luts-%d.cube",
                                    mp.get_property_number("pid", 0)))
        local file = io.open(temp_file, "wb")
        if not file then
            temp_file = nil
            return false, "cannot write a temporary file"
        end
        file:write(cube.clean)
        file:close()
        path = temp_file
    end

    local filter = cube and cube.dim == 1 and "lut1d" or "lut3d"
    local chain = string.format("@%s:format=fmt=gbrp16,@%s:%s=file=%s:interp=%s,@%s:%s",
        LABELS[1], LABELS[2], filter, quote(path),
        filter == "lut3d" and "tetrahedral" or "cubic", LABELS[3], OUTPUT_TAGS)
    if mp.commandv("vf", "add", chain) then
        applied = "cpu"
        return true
    end
    remove_temp_file()
    return false, "could not add the video filter"
end

local function publish()
    mp.set_property("user-data/lut", current and display_name(current) or "")
end

local function save()
    if not opts.remember or not mp.get_property_bool("config") then
        return
    end
    local path = mp.command_native({"expand-path", STATE_FILE})
    local file = io.open(path, "w")
    if not file then
        mp.msg.warn("Could not save the LUT choice to " .. path)
        return
    end
    file:write(current or "", "\n")
    file:close()
end

local function apply(rel, quiet)
    remove_lut()
    current = nil
    if rel then
        local path = find_lut(rel)
        local ok, err = false, "file not found"
        if path then
            ok, err = add_lut(path)
        end
        if not ok then
            remove_lut()
            mp.msg.error("Could not load " .. (path or rel) .. ": " .. err)
            mp.osd_message("LUT: could not load " .. display_name(rel) .. " (" .. err .. ")", 5)
            publish()
            return false
        end
        current = rel
        mp.msg.verbose("Applied " .. path .. " (" .. applied .. ")")
    end
    publish()
    if not quiet then
        mp.osd_message("LUT: " .. (current and display_name(current) or "off"))
    end
    return true
end

-- Merged listing of a folder in all LUT folders.
local function list_dir(rel)
    local dirs, files, seen = {}, {}, {}
    for _, root in ipairs(roots()) do
        local abs = rel == "" and root or utils.join_path(root, rel)
        for _, name in ipairs(utils.readdir(abs, "dirs") or {}) do
            if not seen["d" .. name] then
                seen["d" .. name] = true
                dirs[#dirs + 1] = name
            end
        end
        for _, name in ipairs(utils.readdir(abs, "files") or {}) do
            if is_lut(name) and not seen["f" .. name] then
                seen["f" .. name] = true
                files[#files + 1] = name
            end
        end
    end
    local function by_name(a, b) return a:lower() < b:lower() end
    table.sort(dirs, by_name)
    table.sort(files, by_name)
    return dirs, files
end

local function show_dir(rel)
    local dirs, files = list_dir(rel)

    local items, actions = {}, {}
    local default_item
    local function add(label, action)
        items[#items + 1] = label
        actions[#actions + 1] = action
    end

    if rel == "" then
        add("Off", { lut = false })
        if not current then
            default_item = 1
        end
    else
        add("◂ Back", { dir = rel:match("^(.*)/[^/]+$") or "" })
    end
    for _, name in ipairs(dirs) do
        local sub = rel == "" and name or rel .. "/" .. name
        add(name .. " ▸", { dir = sub })
        if current and current:sub(1, #sub + 1) == sub .. "/" then
            default_item = #items
        end
    end
    for _, name in ipairs(files) do
        local file = rel == "" and name or rel .. "/" .. name
        add((name:gsub("%.[^.]+$", "")), { lut = file })
        if current == file then
            default_item = #items
        end
    end

    if not default_item and rel ~= "" and #items > 1 then
        default_item = 2
    end

    if #items == 1 and rel == "" then
        mp.osd_message("No LUTs found. Put them into the luts folder of the mpv config folder.", 5)
    end

    input.select({
        prompt = rel == "" and "LUT:" or "LUT / " .. display_name(rel) .. ":",
        items = items,
        default_item = default_item,
        keep_open = true,
        submit = function(id)
            local action = actions[id]
            if action.dir then
                show_dir(action.dir)
                return
            end
            input.terminate()
            if apply(action.lut or nil) then
                save()
            end
        end,
    })
end

mp.add_key_binding(opts.key_menu ~= "" and opts.key_menu or nil, "select", function()
    show_dir("")
end)

-- script-message-to luts set "Sony/S-Log3 S-Gamut3.Cine to Rec709.cube"
-- Without an argument, turns the LUT off.
mp.register_script_message("set", function(rel)
    if apply(rel ~= "" and rel or nil) then
        save()
    end
end)

-- Switch between GPU and CPU when the DeckLink output is turned on or off, or
-- the VO turns out not to be gpu-next.
local function check_mode()
    if current then
        local path = find_lut(current)
        local want = path and use_gpu(path) and "gpu" or "cpu"
        if want ~= applied then
            apply(current, true)
        end
    end
end
mp.observe_property("decklink-mirror", "string", check_mode)
mp.observe_property("current-vo", "string", check_mode)

-- Resuming from watch-later restores the vf list saved with it (including an
-- old LUT chain); make it match the current choice again.
mp.add_hook("on_preloaded", 50, function()
    local ours = false
    for _, filter in ipairs(mp.get_property_native("vf", {})) do
        if filter.label and filter.label:match("^mpvtc%-lut") then
            ours = true
        end
    end
    if ours or current then
        apply(current, true)
    end
end)

mp.register_event("shutdown", remove_temp_file)

-- Restore the last LUT.
if opts.remember and mp.get_property_bool("config") then
    local file = io.open(mp.command_native({"expand-path", STATE_FILE}))
    if file then
        local rel = file:read("*l")
        file:close()
        if rel and rel ~= "" then
            if find_lut(rel) then
                apply(rel, true)
            else
                mp.msg.warn("Saved LUT not found: " .. rel)
            end
        end
    end
end
publish()
