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
-- folder); that one is in charge.
if mp.get_script_name() ~= "luts" then
    mp.msg.verbose("Another luts.lua is loaded, not doing anything.")
    return
end

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

local function is_absolute(path)
    return path:match("^/") or path:match("^%a:[/\\]") or path:match("^[/\\][/\\]")
end

-- LUT folders, most preferred first.
local function roots()
    local candidates = opts.dir ~= "" and { opts.dir } or
        { "~~home/luts", "~~osxbundle/luts", "~~exe_dir/luts" }
    local list, seen = {}, {}
    for _, dir in ipairs(candidates) do
        local path = mp.command_native({"expand-path", dir})
        if path and is_absolute(path) and not seen[path] and
           utils.file_info(path) and utils.file_info(path).is_dir
        then
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

local function is_1d_cube(path)
    local file = io.open(path)
    if not file then
        return false
    end
    local result = false
    for _ = 1, 50 do
        local line = file:read("*l")
        if not line then
            break
        end
        if line:match("^%s*LUT_1D_SIZE") then
            result = true
            break
        elseif line:match("^%s*LUT_3D_SIZE") or line:match("^%s*[%d.-]") then
            break
        end
    end
    file:close()
    return result
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
    local vo = mp.get_property_native("options/vo") or {}
    local name = vo[1] and vo[1].name or "gpu-next"
    return name == "gpu-next"
end

local function remove_lut()
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
        mp.set_property("lut", "")
    end
    applied = nil
end

-- Treat the LUT output as Rec.709 / BT.1886, whatever the file is tagged as.
local OUTPUT_TAGS = "format=primaries=bt.709:gamma=bt.1886"

local function add_lut(path)
    if use_gpu(path) then
        mp.set_property("lut-type", "native")
        mp.set_property("lut", path)
        if mp.commandv("vf", "add", "@" .. LABELS[3] .. ":" .. OUTPUT_TAGS) then
            applied = "gpu"
            return true
        end
        mp.set_property("lut", "")
        return false
    end

    local filter = is_1d_cube(path) and "lut1d" or "lut3d"
    local chain = string.format("@%s:format=fmt=gbrp16,@%s:%s=file=%s:interp=%s,@%s:%s",
        LABELS[1], LABELS[2], filter, quote(path),
        filter == "lut3d" and "tetrahedral" or "cubic", LABELS[3], OUTPUT_TAGS)
    if mp.commandv("vf", "add", chain) then
        applied = "cpu"
        return true
    end
    return false
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
        if not path or not add_lut(path) then
            remove_lut()
            mp.osd_message("LUT: could not load " .. display_name(rel))
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

-- Switch between GPU and CPU when the DeckLink output is turned on or off.
mp.observe_property("decklink-mirror", "string", function()
    if current then
        local path = find_lut(current)
        local want = path and use_gpu(path) and "gpu" or "cpu"
        if want ~= applied then
            apply(current, true)
        end
    end
end)

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
