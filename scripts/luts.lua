-- luts.lua
--
-- Applies a 3D/1D LUT (.cube, .3dl, .dat, .m3d, .csp) to the video, chosen
-- from a menu. LUTs are read from the "luts" folder in the mpv config
-- directory; each subfolder is a submenu.
--
-- The LUT is applied as a video filter, so it also affects screenshots and the
-- DeckLink output. LUT input is RGB with video levels mapped to 0-1 (as in
-- DaVinci Resolve); the output is treated as Rec.709 / BT.1886.
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

local opts = {
    dir = "~~/luts",
    remember = true,
    key_menu = "",   -- e.g. ctrl+l
}
options.read_options(opts, "luts")

local EXTENSIONS = { cube = true, ["3dl"] = true, dat = true, m3d = true, csp = true }
local LABELS = { "mpvtc-lut-in", "mpvtc-lut", "mpvtc-lut-out" }
local STATE_FILE = "~~/luts.state"

local current = nil  -- path relative to opts.dir

local function root_dir()
    return mp.command_native({"expand-path", opts.dir})
end

local function display_name(rel)
    local name = rel:gsub("%.[^./\\]+$", "")
    return (name:gsub("[/\\]", " / "))
end

local function is_lut(name)
    local ext = name:match("%.([^.]+)$")
    return ext and EXTENSIONS[ext:lower()]
end

local function sorted(list)
    list = list or {}
    table.sort(list, function(a, b) return a:lower() < b:lower() end)
    return list
end

local function is_1d_cube(path)
    if not path:lower():match("%.cube$") then
        return false
    end
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

local function remove_filters()
    local ours = {}
    for _, label in ipairs(LABELS) do
        ours[label] = true
    end
    for _, filter in ipairs(mp.get_property_native("vf", {})) do
        if filter.label and ours[filter.label] then
            mp.commandv("vf", "remove", "@" .. filter.label)
        end
    end
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
    remove_filters()
    current = nil
    if rel then
        local path = utils.join_path(root_dir(), rel)
        local filter = is_1d_cube(path) and "lut1d" or "lut3d"
        local chain = string.format(
            "@%s:format=fmt=gbrp16,@%s:%s=file=%s:interp=%s,@%s:format=primaries=bt.709:gamma=bt.1886",
            LABELS[1], LABELS[2], filter, quote(path),
            filter == "lut3d" and "tetrahedral" or "cubic", LABELS[3])
        if mp.commandv("vf", "add", chain) then
            current = rel
        else
            remove_filters()
            mp.osd_message("LUT: could not load " .. display_name(rel))
            publish()
            return false
        end
    end
    publish()
    if not quiet then
        mp.osd_message("LUT: " .. (current and display_name(current) or "off"))
    end
    return true
end

local function show_dir(rel)
    local abs = rel == "" and root_dir() or utils.join_path(root_dir(), rel)
    local dirs = sorted(utils.readdir(abs, "dirs"))
    local files = {}
    for _, name in ipairs(sorted(utils.readdir(abs, "files"))) do
        if is_lut(name) then
            files[#files + 1] = name
        end
    end

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
        add("◂ Back", { dir = rel:match("^(.*)[/\\][^/\\]+$") or "" })
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
        mp.osd_message("No LUTs found in " .. abs, 5)
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

-- Restore the last LUT.
if opts.remember and mp.get_property_bool("config") then
    local file = io.open(mp.command_native({"expand-path", STATE_FILE}))
    if file then
        local rel = file:read("*l")
        file:close()
        if rel and rel ~= "" then
            if utils.file_info(utils.join_path(root_dir(), rel)) then
                apply(rel, true)
            else
                mp.msg.warn("Saved LUT not found: " .. rel)
            end
        end
    end
end
publish()
