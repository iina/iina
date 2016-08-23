-- This script automatically loads playlist entries before and after the
-- the currently played file. It does so by scanning the directory a file is
-- located in when starting playback. It sorts the directory entries
-- alphabetically, and adds entries before and after the current file to
-- the internal playlist. (It stops if the it would add an already existing
-- playlist entry at the same position - this makes it "stable".)
-- Add at most 5000 * 2 files when starting a file (before + after).
MAXENTRIES = 5000

function Set (t)
    local set = {}
    for _, v in pairs(t) do set[v] = true end
    return set
end

EXTENSIONS = Set {
    'mkv', 'avi', 'mp4', 'ogv', 'webm', 'rmvb', 'flv', 'wmv', 'mpeg', 'mpg', 'm4v', '3gp',
    'mp3', 'wav', 'ogv', 'flac', 'm4a', 'wma',
}

mputils = require 'mp.utils'

function add_files_at(index, files)
    index = index - 1
    local oldcount = mp.get_property_number("playlist-count", 1)
    for i = 1, #files do
        mp.commandv("loadfile", files[i], "append")
        mp.commandv("playlist-move", oldcount + i - 1, index + i - 1)
    end
end

function get_extension(path)
    match = string.match(path, "%.([^%.]+)$" )
    if match == nil then
        return "nomatch"
    else
        return match
    end
end

table.filter = function(t, iter)
    for i = #t, 1, -1 do
        if not iter(t[i]) then
            table.remove(t, i)
        end
    end
end

function find_and_add_entries()
    local path = mp.get_property("path", "")
    local dir, filename = mputils.split_path(path)
    if #dir == 0 then
        return
    end
    local pl_count = mp.get_property_number("playlist-count", 1)
    if (pl_count > 1 and autoload == nil) or
       (pl_count == 1 and EXTENSIONS[string.lower(get_extension(filename))] == nil) then
        return
    else
        autoload = true
    end

    local files = mputils.readdir(dir, "files")
    if files == nil then
        return
    end
    table.filter(files, function (v, k)
        local ext = get_extension(v)
        if ext == nil then
            return false
        end
        return EXTENSIONS[string.lower(ext)]
    end)
    table.sort(files, function (a, b)
        local len = string.len(a) - string.len(b)
        if len ~= 0 then -- case for ordering filename ending with such as X.Y.Z
            local ext = string.len(get_extension(a)) + 1
            return string.sub(a, 1, -ext) < string.sub(b, 1, -ext)
        end
        return string.lower(a) < string.lower(b)
    end)

    if dir == "." then
        dir = ""
    end

    local pl = mp.get_property_native("playlist", {})
    local pl_current = mp.get_property_number("playlist-pos", 0) + 1
    -- Find the current pl entry (dir+"/"+filename) in the sorted dir list
    local current
    for i = 1, #files do
        if files[i] == filename then
            current = i
            break
        end
    end
    if current == nil then
        return
    end

    local append = {[-1] = {}, [1] = {}}
    for direction = -1, 1, 2 do -- 2 iterations, with direction = -1 and +1
        for i = 1, MAXENTRIES do
            local file = files[current + i * direction]
            local pl_e = pl[pl_current + i * direction]
            if file == nil or file[1] == "." then
                break
            end

            local filepath = dir .. file
            if pl_e then
                -- If there's a playlist entry, and it's the same file, stop.
                if pl_e.filename == filepath then
                    break
                end
            end

            if direction == -1 then
                if pl_current == 1 then -- never add additional entries in the middle
                    mp.msg.info("Prepending " .. file)
                    table.insert(append[-1], 1, filepath)
                end
            else
                mp.msg.info("Adding " .. file)
                table.insert(append[1], filepath)
            end
        end
    end

    add_files_at(pl_current + 1, append[1])
    add_files_at(pl_current, append[-1])
end

mp.register_event("start-file", find_and_add_entries)
