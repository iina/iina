-- quality-menu 4.1.1 - 2023-Oct-22
-- https://github.com/christoph-heinrich/mpv-quality-menu
--
-- Change the stream video and audio quality on the fly.
--
-- Usage:
-- add bindings to input.conf:
-- F     script-binding quality_menu/video_formats_toggle
-- Alt+f script-binding quality_menu/audio_formats_toggle

local mp = require 'mp'
local utils = require 'mp.utils'
local msg = require 'mp.msg'
local assdraw = require 'mp.assdraw'
local opt = require('mp.options')
local script_name = mp.get_script_name()

local opts = {
    --key bindings
    up_binding = 'UP WHEEL_UP',
    down_binding = 'DOWN WHEEL_DOWN',
    select_binding = 'ENTER MBTN_LEFT',
    close_menu_binding = 'ESC MBTN_RIGHT',

    --youtube-dl version(could be youtube-dl or yt-dlp, or something else)
    ytdl_ver = 'yt-dlp',

    --formatting / cursors
    selected_and_active     = '▶  - ',
    selected_and_inactive   = '●  - ',
    unselected_and_active   = '▷ - ',
    unselected_and_inactive = '○ - ',

    --font size scales by window, if false requires larger font and padding sizes
    scale_playlist_by_window = true,

    --playlist ass style overrides inside curly brackets, \keyvalue is one field, extra \ for escape in lua
    --example {\\fnUbuntu\\fs10\\b0\\bord1} equals: font=Ubuntu, size=10, bold=no, border=1
    --read http://docs.aegisub.org/3.2/ASS_Tags/ for reference of tags
    --undeclared tags will use default osd settings
    --these styles will be used for the whole playlist. More specific styling will need to be hacked in
    --
    --(a monospaced font is recommended but not required)
    style_ass_tags = '{\\fnmonospace\\fs25\\bord1}',

    -- Shift drawing coordinates. Required for mpv.net compatiblity
    shift_x = 0,
    shift_y = 0,

    --paddings from window edge
    text_padding_x = 5,
    text_padding_y = 10,

    --Screen dim when menu is open
    curtain_opacity = 0.7,

    --how many seconds until the quality menu times out
    --setting this to 0 deactivates the timeout
    menu_timeout = 6,

    --use youtube-dl to fetch a list of available formats (overrides quality_strings)
    fetch_formats = true,

    --list of ytdl-format strings to choose from
    quality_strings_video = [[
    [
    {"4320p" : "bestvideo[height<=?4320p]"},
    {"2160p" : "bestvideo[height<=?2160]"},
    {"1440p" : "bestvideo[height<=?1440]"},
    {"1080p" : "bestvideo[height<=?1080]"},
    {"720p" : "bestvideo[height<=?720]"},
    {"480p" : "bestvideo[height<=?480]"},
    {"360p" : "bestvideo[height<=?360]"},
    {"240p" : "bestvideo[height<=?240]"},
    {"144p" : "bestvideo[height<=?144]"}
    ]
    ]],
    quality_strings_audio = [[
    [
    {"default" : "bestaudio/best"}
    ]
    ]],

    --automatically fetch available formats when opening an url
    fetch_on_start = true,

    --show the video format menu after opening an url
    start_with_menu = false,

    --include unknown formats in the list
    --Unfortunately choosing which formats are video or audio is not always perfect.
    --Set to true to make sure you don't miss any formats, but then the list
    --might also include formats that aren't actually video or audio.
    --Formats that are known to not be video or audio are still filtered out.
    include_unknown = false,

    --hide columns that are identical for all formats
    hide_identical_columns = true,

    --which columns are shown in which order
    --comma separated list, prefix column with "-" to align left
    --
    --for the uosc integration it is possible to split the text up into a title and a hint
    --this is done by separating two columns with a "|" instead of a comma
    --column order in the hint is reversed
    --
    --columns that might be useful are:
    --resolution, width, height, fps, dynamic_range, tbr, vbr, abr, asr,
    --filesize, filesize_approx, vcodec, acodec, ext, video_ext, audio_ext,
    --language, format, format_note, quality
    --
    --columns that are derived from the above, but with special treatment:
    --size, frame_rate, bitrate_total, bitrate_video, bitrate_audio,
    --codec_video, codec_audio, audio_sample_rate
    --
    --If those still aren't enough or you're just curious, run:
    --yt-dlp -j <url>
    --This outputs unformatted JSON.
    --Format it and look under "formats" to see what's available.
    --
    --Not all videos have all columns available.
    --Be careful, misspelled columns simply won't be displayed, there is no error.
    columns_video = '-resolution,frame_rate,dynamic_range|language,bitrate_total,size,-codec_video,-codec_audio',
    columns_audio = 'audio_sample_rate,bitrate_total|size,language,-codec_audio',

    --columns used for sorting, see "columns_video" for available columns
    --comma separated list, prefix column with "-" to reverse sorting order
    --Leaving this empty keeps the order from yt-dlp/youtube-dl.
    --Be careful, misspelled columns won't result in an error,
    --but they might influence the result.
    sort_video = 'height,fps,tbr,size,format_id',
    sort_audio = 'asr,tbr,size,format_id',
}
opt.read_options(opts, 'quality-menu')

---@alias Format { properties: {[string]: string}, id: string, label?: string, title?: string, hint?: string }
-- *_active_id == nil means unknown, *_active_id == '' means disabled
---@alias Data { video_formats: Format[], audio_formats: Format[], video_active_id?: string, audio_active_id?: string }
---@alias UIState { type: string, type_capitalized: string, name: string , to_other_type: UIState, to_fetching: UIState, to_menu: UIState, is_video: boolean }

do
    ---@param option_string string
    ---@param option_name string
    ---@return Format[]
    local function parse_predefined(option_string, option_name)
        ---@type {[string]: string}[]
        local json, error = utils.parse_json(option_string)
        if error then
            msg.error('Error while parsing JSON of option ' .. option_name .. ': ' .. error)
            return {}
        end
        ---@type Format[]
        local formats = {}
        for i, format in ipairs(json) do
            local label, format_string = next(format)
            formats[i] = {
                label = label,
                title = label,
                id = format_string,
            }
        end
        return formats
    end

    ---@type Data
    opts.predefined_data = {
        video_formats = parse_predefined(opts.quality_strings_video, 'quality_strings_video'),
        audio_formats = parse_predefined(opts.quality_strings_audio, 'quality_strings_audio'),
        video_active_id = nil,
        audio_active_id = nil,
    }
end

opts.font_size = tonumber(opts.style_ass_tags:match('\\fs(%d+%.?%d*)')) or mp.get_property_number('osd-font-size') or 25
opts.curtain_opacity = math.max(math.min(opts.curtain_opacity, 1), 0)

---@param input string
---@param separator string
---@return string[]
local function string_split(input, separator)
    if separator == nil then
        separator = '%s'
    end
    local t = {}
    for str in string.gmatch(input, '([^' .. separator .. ']+)') do
        table.insert(t, str)
    end
    return t
end

---@param strings string[]
---@return string[], boolean[]
local function strip_minus(strings)
    local stripped_list = {}
    local had_minus = {}
    for i, val in ipairs(strings) do
        if string.sub(val, 1, 1) == '-' then
            val = string.sub(val, 2)
            had_minus[val] = true
        end
        stripped_list[i] = val
    end
    return stripped_list, had_minus
end

do
    ---@param column_definition string
    ---@return { all: string[], all_align_left: boolean[], title: string[], title_align_left: boolean[], hint?: string[] }
    local function parse_columns(column_definition)
        local columns, columns_align_left = strip_minus(string_split(column_definition, '|,'))
        local title_hint = string_split(column_definition, '|')
        local title, title_align_left = strip_minus(string_split(title_hint[1], ','))

        local hint = nil
        if title_hint[2] then
            hint = strip_minus(string_split(title_hint[2], ','))
            -- reverse column order
            local n = #hint
            for i = 1, n / 2 do
                hint[i], hint[n - i + 1] = hint[n - i + 1], hint[i]
            end
        end
        return {
            all = columns, all_align_left = columns_align_left,
            title = title, title_align_left = title_align_left,
            hint = hint
        }
    end

    ---@type { all: string[], all_align_left: boolean[], title: string[], title_align_left: boolean[], hint?: string[] }
    ---@diagnostic disable-next-line: param-type-mismatch
    opts.columns_video = parse_columns(opts.columns_video)
    ---@type { all: string[], all_align_left: boolean[], title: string[], title_align_left: boolean[], hint?: string[] }
    ---@diagnostic disable-next-line: param-type-mismatch
    opts.columns_audio = parse_columns(opts.columns_audio)
end

-- special thanks to reload.lua (https://github.com/4e6/mpv-reload/)
local function reload_resume()
    local reload_duration = mp.get_property_native('duration')
    local time_pos = mp.get_property('time-pos')

    mp.command('playlist-play-index current')

    -- Tries to determine live stream vs. pre-recorded VOD. VOD has non-zero
    -- duration property. When reloading VOD, to keep the current time position
    -- we should provide offset from the start. Stream doesn't have fixed start.
    -- Decent choice would be to reload stream from it's current 'live' position.
    -- That's the reason we don't pass the offset when reloading streams.
    if reload_duration and reload_duration > 0 then
        local function seeker()
            mp.commandv('seek', time_pos, 'absolute+exact')
            mp.unregister_event(seeker)
        end

        mp.register_event('file-loaded', seeker)
    end
end

---@type { video_menu: UIState, audio_menu: UIState, video_fetching: UIState, audio_fetching: UIState }
local states = {
    video_menu = { type = 'video', type_capitalized = 'Video', name = 'video_menu', is_video = true },
    audio_menu = { type = 'audio', type_capitalized = 'Audio', name = 'audio_menu', is_video = false },
    video_fetching = { type = 'video', type_capitalized = 'Video', name = 'video_fetching', is_video = true },
    audio_fetching = { type = 'audio', type_capitalized = 'Audio', name = 'audio_fetching', is_video = false },
}
states.video_menu.to_fetching = states.video_fetching
states.video_menu.to_menu = states.video_menu
states.video_menu.to_other_type = states.audio_menu
states.audio_menu.to_fetching = states.audio_fetching
states.audio_menu.to_menu = states.audio_menu
states.audio_menu.to_other_type = states.video_menu
states.video_fetching.to_fetching = states.video_fetching
states.video_fetching.to_menu = states.video_menu
states.video_fetching.to_other_type = states.audio_fetching
states.audio_fetching.to_fetching = states.audio_fetching
states.audio_fetching.to_menu = states.audio_menu
states.audio_fetching.to_other_type = states.video_fetching

---@type UIState | nil
local open_menu_state = nil
---@type string | nil
local current_url = nil
---@type {[string]: table}
local currently_fetching = {}
local destructor = nil

local ytdl = {
    path = opts.ytdl_ver,
    searched = false,
    blacklisted = {}
}

local menu_open
local menu_close
local video_formats_toggle
local audio_formats_toggle

local osd = mp.create_osd_overlay('ass-events')

local function hide_osd()
    -- workaround mpv bug, setting to hidden does not cause a redraw
    -- https://github.com/mpv-player/mpv/issues/10227
    osd.data = ''
    osd:update()
    osd.hidden = true
    osd:update()
end

local osd_timer = mp.add_timeout(1, function() menu_close() end)
osd_timer:kill()

---@param message string
---@param time number
local function osd_message(message, time)
    osd.res_x = 1280
    osd.res_y = 720
    osd.hidden = false
    osd.data = message
    osd:update()
    osd_timer.timeout = time
    osd_timer:kill()
    osd_timer:resume()
end

---@alias FormatRaw {format_id: string, vcodec?: string, acodec?: string, filesize: integer?, filesize_approx?: integer, fps?: number, tbr?: number, vbr?: number, abr?: number, asr?: number}

---@param json {formats: FormatRaw[], requested_formats: FormatRaw, requested_downloads: FormatRaw}
---@return Data
local function process_json(json)
    ---@param format FormatRaw
    ---@return boolean
    local function is_video(format)
        -- 'none' means it is not a video
        -- nil means it is unknown
        return (opts.include_unknown or format.vcodec) and format.vcodec ~= 'none' or false
    end

    ---@param format FormatRaw
    ---@return boolean
    local function is_audio(format)
        return (opts.include_unknown or format.acodec) and format.acodec ~= 'none' or false
    end

    local requested_video = nil
    local requested_audio = nil
    local requested_formats = json.requested_formats or json.requested_downloads or {}
    for _, format in ipairs(requested_formats) do
        if is_video(format) then
            requested_video = format.format_id
        elseif is_audio(format) then
            requested_audio = format.format_id
        end
    end

    local video_formats = {}
    local audio_formats = {}
    local all_formats = {}
    for i = #json.formats, 1, -1 do
        local format = json.formats[i]
        if is_video(format) then
            video_formats[#video_formats + 1] = format
            all_formats[#all_formats + 1] = format
        elseif is_audio(format) then
            audio_formats[#audio_formats + 1] = format
            all_formats[#all_formats + 1] = format
        end
    end

    ---@param format FormatRaw
    local function populate_special_fields(format)
        format.size = format.filesize or format.filesize_approx
        format.frame_rate = format.fps
        format.bitrate_total = format.tbr
        format.bitrate_video = format.vbr
        format.bitrate_audio = format.abr
        format.codec_video = format.vcodec
        format.codec_audio = format.acodec
        format.audio_sample_rate = format.asr
    end

    for _, format in ipairs(all_formats) do
        populate_special_fields(format)
    end

    local sort_video, reverse_video = strip_minus(string_split(opts.sort_video, ','))
    local sort_audio, reverse_audio = strip_minus(string_split(opts.sort_audio, ','))

    ---@param properties string[]
    ---@param reverse {[string]: boolean}
    ---@return fun(a: FormatRaw, b: FormatRaw): boolean
    local function comp(properties, reverse)
        return function(a, b)
            for _, prop in ipairs(properties) do
                local a_val = a[prop]
                local b_val = b[prop]
                if a_val and b_val and type(a_val) ~= 'table' and a_val ~= b_val then
                    if reverse[prop] then
                        return a_val < b_val
                    else
                        return a_val > b_val
                    end
                end
            end
            return false
        end
    end

    if #sort_video > 0 then
        table.sort(video_formats, comp(sort_video, reverse_video))
    end
    if #sort_audio > 0 then
        table.sort(audio_formats, comp(sort_audio, reverse_audio))
    end

    ---@param size integer
    ---@return string
    local function scale_filesize(size)
        if size == nil then
            return ''
        end

        local counter = 0
        while size > 1024 do
            size = size / 1024
            counter = counter + 1
        end

        if counter >= 3 then return string.format('%.1fGiB', size)
        elseif counter >= 2 then return string.format('%.1fMiB', size)
        elseif counter >= 1 then return string.format('%.1fKiB', size)
        else return string.format('%.1fB  ', size)
        end
    end

    ---@param bitrate integer
    ---@return string
    local function scale_bitrate(bitrate)
        if bitrate == nil then
            return ''
        end

        local counter = 0
        while bitrate > 1000 do
            bitrate = bitrate / 1000
            counter = counter + 1
        end

        if counter >= 2 then return string.format('%.1fGbps', bitrate)
        elseif counter >= 1 then return string.format('%.1fMbps', bitrate)
        else return string.format('%.1fKbps', bitrate)
        end
    end

    ---@param format FormatRaw
    local function format_special_fields(format)
        local size_prefix = not format.filesize and format.filesize_approx and '~' or ''
        ---@diagnostic disable-next-line: param-type-mismatch
        format.size = (size_prefix) .. scale_filesize(format.size)
        format.frame_rate = format.fps and format.fps .. 'fps' or ''
        format.bitrate_total = scale_bitrate(format.tbr)
        format.bitrate_video = scale_bitrate(format.vbr)
        format.bitrate_audio = scale_bitrate(format.abr)
        format.codec_video = format.vcodec == nil and 'unknown' or format.vcodec == 'none' and '' or format.vcodec
        format.codec_audio = format.acodec == nil and 'unknown' or format.acodec == 'none' and '' or format.acodec
        format.audio_sample_rate = format.asr and tostring(format.asr) .. 'Hz' or ''
    end

    for _, format in ipairs(all_formats) do
        format_special_fields(format)
    end

    ---@param raw_formats { [string]: any }
    ---@param properties string[]
    ---@return Format[]
    local function convert_to_format(raw_formats, properties)
        ---@type Format[]
        local formats = {}
        for i, format in ipairs(raw_formats) do
            local props = {}
            for _, prop in ipairs(properties) do
                props[prop] = tostring(format[prop] or '')
            end
            formats[i] = { properties = props, id = format.format_id }
        end
        return formats
    end

    return {
        video_formats = convert_to_format(video_formats, opts.columns_video.all),
        audio_formats = convert_to_format(audio_formats, opts.columns_audio.all),
        video_active_id = requested_video,
        audio_active_id = requested_audio,
    }
end

---@return string | nil
local function get_url()
    local path = mp.get_property('path')
    if not path then return nil end
    path = path:gsub('ytdl://', '') -- Strip possible ytdl:// prefix.

    ---@param str string
    ---@return boolean
    local function is_url(str)
        -- adapted the regex from
        -- https://stackoverflow.com/questions/3809401/what-is-a-good-regular-expression-to-match-a-url
        return nil ~=
            str:match(
                '^[%w]-://[-a-zA-Z0-9@:%._\\+~#=]+%.' ..
                '[a-zA-Z0-9()][a-zA-Z0-9()]?[a-zA-Z0-9()]?[a-zA-Z0-9()]?[a-zA-Z0-9()]?[a-zA-Z0-9()]?' ..
                '[-a-zA-Z0-9()@:%_\\+.~#?&/=]*')
    end

    return is_url(path) and path or nil
end

local uosc_available = false
---@type { [string]: Data }
local url_data = {}

local function uosc_set_format_counts()
    if not uosc_available then return end

    local data = url_data[current_url]
    if data then
        mp.commandv('script-message-to', 'uosc', 'set', 'vformats', #data.video_formats)
        mp.commandv('script-message-to', 'uosc', 'set', 'aformats', #data.audio_formats)
    else
        mp.commandv('script-message-to', 'uosc', 'set', 'vformats', 0)
        mp.commandv('script-message-to', 'uosc', 'set', 'aformats', 0)
    end
end

---@param json string
---@return Data | nil
local function process_json_string(json)
    local json_table, err = utils.parse_json(json)

    if (json_table == nil) then
        osd_message('fetching formats failed...', 2)
        if err == nil then err = 'unexpected error occurred' end
        msg.error('failed to parse JSON data: ' .. err)
        return
    end

    if json_table.formats == nil then
        return
    end

    return process_json(json_table)
end

---@param url string
local function download_formats(url)
    if currently_fetching[url] then return end

    msg.info('fetching available formats...')

    if not (ytdl.searched) then
        local ytdl_mcd = mp.find_config_file(opts.ytdl_ver)
        if not (ytdl_mcd == nil) then
            msg.verbose('found ytdl at: ' .. ytdl_mcd)
            ytdl.path = ytdl_mcd
        end
        ytdl.searched = true
    end

    local ytdl_format = mp.get_property('ytdl-format')
    local raw_options = mp.get_property_native('ytdl-raw-options')
    local command = { ytdl.path, '--no-warnings', '--no-playlist', '-J' }
    if ytdl_format and #ytdl_format > 0 then
        command[#command + 1] = '-f'
        command[#command + 1] = ytdl_format
    end
    for param, arg in pairs(raw_options) do
        command[#command + 1] = '--' .. param
        if #arg > 0 then
            command[#command + 1] = arg
        end
    end
    if opts.ytdl_ver == 'yt-dlp' then command[#command + 1] = '--no-match-filter' end
    command[#command + 1] = '--'
    command[#command + 1] = url

    msg.verbose('calling ytdl with command: ' .. table.concat(command, ' '))

    --- result.status is exit status
    --- result.error_string can be empty string, 'killed' or 'init'
    ---@param success boolean
    ---@param result { status: integer, stdout: string, stderr: string, error_string: string , killed_by_us: boolean }
    ---@param error string | nil
    local function callback(success, result, error)
        currently_fetching[url] = nil
        if result.killed_by_us then return end
        if result.status < 0 or result.stdout == '' or result.error_string ~= '' then
            osd_message('fetching formats failed...', 2)
            msg.verbose('status:', result.status)
            msg.verbose('reason:', result.error_string)
            msg.verbose('stdout:', result.stdout)
            msg.verbose('stderr:', result.stderr)

            -- trim our stderr to avoid spurious newlines
            local ytdl_err = result.stderr:gsub('^%s*(.-)%s*$', '%1')
            msg.error(ytdl_err)
            local err = 'ytdl failed: '
            if result.error_string and result.error_string == 'init' then
                err = err .. 'not found or not enough permissions'
            elseif not result.killed_by_us then
                err = err .. 'unexpected error occurred'
            else
                err = string.format('%s returned "%d"', err, result.status)
            end
            msg.error(err)
            if string.find(ytdl_err, 'yt%-dl%.org/bug') then
                -- check version
                local version_command = {
                    name = 'subprocess',
                    capture_stdout = true,
                    args = { ytdl.path, '--version' }
                }
                local version_string = mp.command_native(version_command).stdout
                local year, month, day = string.match(version_string, '(%d+).(%d+).(%d+)')

                -- sanity check
                if (tonumber(year) < 2000) or (tonumber(month) > 12) or
                    (tonumber(day) > 31) then
                    return
                end
                local version_ts = os.time { year = year, month = month, day = day }
                if (os.difftime(os.time(), version_ts) > 60 * 60 * 24 * 90) then
                    msg.warn('It appears that your ytdl version is severely out of date.')
                end
            end
            return
        end

        msg.verbose('ytdl succeeded!')
        local data = process_json_string(result.stdout)
        url_data[url] = data
        uosc_set_format_counts()

        if not data then return end
        if open_menu_state and open_menu_state == open_menu_state.to_fetching and url == current_url then
            menu_open(open_menu_state)
        end
    end

    currently_fetching[url] = mp.command_native_async({
        name = 'subprocess',
        args = command,
        capture_stdout = true,
        capture_stderr = true
    }, callback)
end

---Unknown format falls back on highest ranked format if possible
---@param id string | nil
---@param formats Format[]
---@return string
local function sanitize_format_id(id, formats)
    return id or (formats[1] or {}).id or ''
end

---@param video_id string
---@param audio_id string
---@return string
local function format_string(video_id, audio_id)
    if #video_id > 0 and #audio_id > 0 then
        return video_id .. '+' .. audio_id
    elseif #video_id > 0 then
        return video_id
    elseif #audio_id > 0 then
        return audio_id
    else
        return ''
    end
end

---@param url string
---@param video_format string
---@param audio_format string
local function set_format(url, video_format, audio_format)
    if (url_data[url].video_active_id ~= video_format or url_data[url].audio_active_id ~= audio_format) then
        url_data[url].video_active_id = video_format
        url_data[url].audio_active_id = audio_format
        if url == mp.get_property('path') then reload_resume() end
    end
end

---@param formats Format[]
---@param active_format string | nil
---@param menu_type UIState
local function text_menu_open(formats, active_format, menu_type)
    local active = 0
    local selected = 1
    --set the cursor to the current format
    for i, format in ipairs(formats) do
        if format.id == active_format then
            active = i
            selected = active
            break
        end
    end
    if active_format == '' then
        active = #formats + 1
        selected = active
    end

    ---@param i integer
    ---@return string
    local function choose_prefix(i)
        if i == selected and i == active then return opts.selected_and_active
        elseif i == selected then return opts.selected_and_inactive end

        if i ~= selected and i == active then return opts.unselected_and_active
        elseif i ~= selected then return opts.unselected_and_inactive end
        return '> ' --shouldn't get here.
    end

    local width, height
    local margin_top, margin_bottom = 0, 0
    local num_options = #formats > 0 and #formats + 2 or 1

    ---@return integer
    local function get_scrolled_lines()
        local output_height = height - opts.text_padding_y * 2 - margin_top * height - margin_bottom * height
        local screen_lines = math.max(math.floor(output_height / opts.font_size), 1)
        local max_scroll = math.max(num_options - screen_lines, 0)
        return math.min(math.max(selected - math.ceil(screen_lines / 2), 0), max_scroll)
    end

    local function draw_menu()
        local ass = assdraw.ass_new()

        if opts.curtain_opacity > 0 then
            local alpha = 255 - math.ceil(255 * opts.curtain_opacity)
            ass.text = string.format('{\\pos(0,0)\\rDefault\\an7\\1c&H000000&\\alpha&H%X&}', alpha)
            ass:draw_start()
            ass:rect_cw(0, 0, width, height)
            ass:draw_stop()
            ass:new_event()
        end

        local scrolled_lines = get_scrolled_lines()
        local pos_y = opts.shift_y + margin_top * height + opts.text_padding_y - scrolled_lines * opts.font_size
        ass:pos(opts.shift_x + opts.text_padding_x, pos_y)
        local clip_top = math.floor(margin_top * height + 0.5)
        local clip_bottom = math.floor((1 - margin_bottom) * height + 0.5)
        local clipping_coordinates = '0,' .. clip_top .. ',' .. width .. ',' .. clip_bottom
        ass:append('{\\rDefault\\q2\\clip(' .. clipping_coordinates .. ')}' .. opts.style_ass_tags)

        if #formats > 0 then
            for i, format in ipairs(formats) do
                ass:append(choose_prefix(i) .. format.label .. '\\N')
            end
            ass:append(choose_prefix(#formats + 1) .. 'Disabled\\N')
            ass:append(choose_prefix(#formats + 2) .. menu_type.to_other_type.type_capitalized .. ' menu')
        else
            ass:append('no formats found\\N')
            ass:append(opts.selected_and_inactive .. menu_type.to_other_type.type_capitalized .. ' menu')
        end

        osd.data = ass.text
        osd:update()
    end

    local function update_dimensions()
        local _, h, aspect = mp.get_osd_size()
        if opts.scale_playlist_by_window then h = 720 end
        height = h
        width = height * aspect
        osd.res_y = height
        osd.res_x = width
        draw_menu()
    end

    local update_margins;
    if utils.shared_script_property_set then
        update_margins = function()
            local shared_props = mp.get_property_native('shared-script-properties')
            local val = shared_props['osc-margins']
            if val then
                -- formatted as '%f,%f,%f,%f' with left, right, top, bottom, each
                -- value being the border size as ratio of the window size (0.0-1.0)
                local vals = {}
                for v in string.gmatch(val, '[^,]+') do
                    vals[#vals + 1] = tonumber(v)
                end
                margin_top = vals[3] -- top
                margin_bottom = vals[4] -- bottom
            else
                margin_top = 0
                margin_bottom = 0
            end
            draw_menu()
        end
        mp.observe_property('shared-script-properties', 'native', update_margins)
    else
        update_margins = function(_, val)
            if not val then
                val = mp.get_property_native('user-data/osc/margins')
            end
            if val then
                margin_top = val.t
                margin_bottom = val.b
            else
                margin_top = 0
                margin_bottom = 0
            end
            draw_menu()
        end
        mp.observe_property('user-data/osc/margins', 'native', update_margins)
    end

    update_dimensions()
    update_margins()
    mp.observe_property('osd-dimensions', 'native', update_dimensions)

    ---@param amount integer
    local function selected_move(amount)
        selected = selected + amount
        if selected < 1 then selected = num_options
        elseif selected > num_options then selected = 1 end
        if osd_timer then
            osd_timer:kill()
            osd_timer:resume()
        end
        draw_menu()
    end

    ---@param keys string | nil
    ---@param name string
    ---@param func function
    ---@param opts table | nil
    local function bind_keys(keys, name, func, opts)
        if not keys then
            mp.add_forced_key_binding(keys, name, func, opts)
            return
        end
        local i = 1
        for key in keys:gmatch('[^%s]+') do
            local prefix = i == 1 and '' or i
            mp.add_forced_key_binding(key, name .. prefix, func, opts)
            i = i + 1
        end
    end

    ---@param keys string | nil
    ---@param name string
    local function unbind_keys(keys, name)
        if not keys then
            mp.remove_key_binding(name)
            return
        end
        local i = 1
        for key in keys:gmatch('[^%s]+') do
            local prefix = i == 1 and '' or i
            mp.remove_key_binding(name .. prefix)
            i = i + 1
        end
    end

    -- make sure observers are cleaned up
    if open_menu_state and open_menu_state == open_menu_state.to_menu and destructor then destructor() end
    destructor = function()
        unbind_keys(opts.up_binding, 'move_up')
        unbind_keys(opts.down_binding, 'move_down')
        unbind_keys(opts.select_binding, 'select')
        unbind_keys(opts.close_menu_binding, 'close')
        mp.unobserve_property(update_dimensions)
        mp.unobserve_property(update_margins)
    end

    osd_timer:kill()
    if opts.menu_timeout > 0 then
        osd_timer.timeout = opts.menu_timeout
        osd_timer:resume()
    end

    bind_keys(opts.up_binding, 'move_up', function() selected_move( -1) end, { repeatable = true })
    bind_keys(opts.down_binding, 'move_down', function() selected_move(1) end, { repeatable = true })
    bind_keys(opts.close_menu_binding, 'close', menu_close)
    bind_keys(opts.select_binding, 'select', function()
        if selected == num_options then
            mp.unobserve_property(update_dimensions)
            mp.unobserve_property(update_margins)
            if menu_type.is_video then audio_formats_toggle()
            else video_formats_toggle() end
            return
        end
        menu_close()
        if selected == active then return end
        if current_url == nil then return end

        local video_id, audio_id
        local id = formats[selected] and formats[selected].id or ''
        local data = url_data[current_url]
        if menu_type.is_video then
            video_id = id
            audio_id = sanitize_format_id(data.audio_active_id, data.audio_formats)
        else
            video_id = sanitize_format_id(data.video_active_id, data.video_formats)
            audio_id = id
        end
        set_format(current_url, video_id, audio_id)
    end)

    osd.hidden = false
    draw_menu()
end

---@param menu table
---@param menu_type UIState
local function uosc_show_menu(menu, menu_type)
    local json = utils.format_json(menu)
    -- always using update wouldn't work, because it doesn't support the on_close command
    -- therefore opening a different kind requires `open-menu`
    -- while updating the same kind requires `update-menu`
    if open_menu_state == menu_type then mp.commandv('script-message-to', 'uosc', 'update-menu', json)
    else mp.commandv('script-message-to', 'uosc', 'open-menu', json) end
end

---@param formats Format[]
---@param active_format string | nil
---@param menu_type UIState
local function uosc_menu_open(formats, active_format, menu_type)
    local menu = {
        title = menu_type.type_capitalized .. ' Formats',
        items = {},
        type = 'quality-menu-' .. menu_type.name,
        keep_open = true,
        on_close = {
            'script-message-to',
            script_name,
            'uosc-menu-closed',
            menu_type.name,
        }
    }

    menu.items[#menu.items + 1] = {
        title = menu_type.to_other_type.type_capitalized,
        italic = true,
        bold = true,
        hint = 'open menu',
        value = {
            'script-message-to',
            script_name,
            menu_type.to_other_type.type .. '_formats_toggle',
        },
    }
    menu.items[#menu.items + 1] = {
        title = 'Disabled',
        italic = true,
        muted = true,
        hint = '—',
        active = active_format == '',
        value = {
            'script-message-to',
            script_name,
            menu_type.type .. '-format-set',
            current_url,
            '',
        }
    }

    for _, format in ipairs(formats) do
        menu.items[#menu.items + 1] = {
            title = format.title,
            hint = format.hint,
            active = format.id == active_format,
            value = {
                'script-message-to',
                script_name,
                menu_type.type .. '-format-set',
                current_url,
                format.id,
            }
        }
    end

    uosc_show_menu(menu, menu_type)
    destructor = function()
        mp.commandv('script-message-to', 'uosc', 'close-menu', menu.type)
    end
end

---Check if property is same for all formats
---@param formats Format[]
---@param properties string[]
---@return { [string]: boolean }
local function identical_for_all(formats, properties)
    ---@param formats Format[]
    ---@param prop string
    ---@return boolean
    local function all_formats_same_value(formats, prop)
        local first_value = nil
        for _, format in ipairs(formats) do
            first_value = first_value or format.properties[prop]
            if format.properties[prop] ~= first_value then return false end
        end
        return true
    end

    local identical_props = {}
    for _, prop in ipairs(properties) do
        identical_props[prop] = all_formats_same_value(formats, prop)
    end
    return identical_props
end

---@param formats Format[]
---@param columns string[]
---@param column_align_left boolean[]
---@return string[]
local function format_table(formats, columns, column_align_left)
    local column_widths = {}
    for _, format in pairs(formats) do
        for col, prop in ipairs(columns) do
            local width = format.properties[prop]:len()
            if not column_widths[col] or column_widths[col] < width then
                column_widths[col] = width
            end
        end
    end

    local identical_columns = identical_for_all(formats, columns)

    local show_columns = {}
    for i, width in ipairs(column_widths) do
        local prop = columns[i]
        if width > 0 and not (opts.hide_identical_columns and identical_columns[prop]) then
            show_columns[#show_columns + 1] = {
                prop = prop,
                width = width,
                align_left = column_align_left[prop]
            }
        end
    end

    local spacing = 2
    ---@type string[]
    local rows = {}
    for i, format in ipairs(formats) do
        local row = {}
        for j, column in ipairs(show_columns) do
            -- lua errors out with width > 99 ("invalid conversion specification")
            local width = math.min(column.width * (column.align_left and -1 or 1), 99)
            row[j] = string.format('%' .. width .. 's', format.properties[column.prop] or '')
        end
        rows[i] = table.concat(row, string.format('%' .. spacing .. 's', '')):gsub('%s+$', '')
    end
    return rows
end

---@param formats Format[]
---@param columns string[]
---@return string[]
local function format_csv(formats, columns)
    local identical_props = identical_for_all(formats, columns)
    local hints = {}
    for i, format in ipairs(formats) do
        local row = {}
        for _, prop in ipairs(columns) do
            local val = format.properties[prop]
            if #val > 0 and not (opts.hide_identical_columns and identical_props[prop]) then
                row[#row + 1] = val
            end
        end
        hints[i] = table.concat(row, ', ')
    end
    return hints
end

---@param formats Format[]
---@param menu_type UIState
local function ensure_menu_data_filled(formats, menu_type)
    if uosc_available then
        if formats[1] and formats[1].title == nil then
            local columns = menu_type.is_video and opts.columns_video or opts.columns_audio
            local titles = format_table(formats, columns.title, columns.title_align_left)

            local hints = {}
            if columns.hint then
                hints = format_csv(formats, columns.hint)
            end

            for i, format in ipairs(formats) do
                format.title = titles[i]
                format.hint = hints[i]
            end
        end
    else
        if formats[1] and formats[1].label == nil then
            local columns = menu_type.is_video and opts.columns_video or opts.columns_audio
            local labels = format_table(formats, columns.all, columns.all_align_left)
            for i, format in ipairs(formats) do format.label = labels[i] end
        end
    end
end

---@param menu_type UIState
local function loading_message(menu_type)
    menu_type = menu_type.to_fetching
    if uosc_available then
        if open_menu_state and open_menu_state == menu_type then return end
        local menu = {
            title = menu_type.type_capitalized .. ' Formats',
            items = { { icon = 'spinner', selectable = false, value = 'ignore' } },
            type = 'quality-menu-' .. menu_type.name,
            keep_open = true,
            on_close = {
                'script-message-to',
                script_name,
                'uosc-menu-closed',
                menu_type.name
            }
        }
        uosc_show_menu(menu, menu_type)
        destructor = function()
            mp.commandv('script-message-to', 'uosc', 'close-menu', menu.type)
        end
    else
        osd_message('fetching available ' .. menu_type.type .. ' formats...', 60)
    end
    open_menu_state = menu_type
end

---@param menu_type UIState
function menu_open(menu_type)
    if not current_url then return end
    menu_type = menu_type.to_menu

    local data = url_data[current_url]
    if not data then
        if opts.fetch_formats then
            loading_message(menu_type)
            download_formats(current_url)
            return
        end

        -- shallow clone so that each url has it's own active format ids
        data = {}
        for k, v in pairs(opts.predefined_data) do
            data[k] = v
        end
        url_data[current_url] = data
    end
    local formats = menu_type.is_video and data.video_formats or data.audio_formats
    local active_format
    if menu_type.is_video then active_format = data.video_active_id
    else active_format = data.audio_active_id end

    msg.verbose('current ytdl-format: ' .. mp.get_property('ytdl-format', ''))

    ensure_menu_data_filled(formats, menu_type)
    if uosc_available then uosc_menu_open(formats, active_format, menu_type)
    else text_menu_open(formats, active_format, menu_type) end
    open_menu_state = menu_type
end

function menu_close()
    if destructor then
        destructor()
        destructor = nil
    end
    if not osd.hidden then hide_osd() end
    open_menu_state = nil
end

---@param menu_type UIState
local function toggle_menu(menu_type)
    if open_menu_state and open_menu_state.type == menu_type.type then
        menu_close()
        return
    end

    if current_url == nil then
        if uosc_available then
            if menu_type.is_video then
                mp.commandv('script-binding', 'uosc/video')
            else
                mp.commandv('script-binding', 'uosc/audio')
            end
        end
        return
    end

    menu_open(menu_type)
end

function video_formats_toggle() toggle_menu(states.video_menu) end
function audio_formats_toggle() toggle_menu(states.audio_menu) end

-- keybind to launch menu
mp.add_key_binding(nil, 'video_formats_toggle', video_formats_toggle)
mp.add_key_binding(nil, 'audio_formats_toggle', audio_formats_toggle)
mp.add_key_binding(nil, 'reload', reload_resume)

mp.register_event('start-file', function()
    local new_url = get_url()
    local url_changed = current_url ~= new_url
    current_url = new_url
    uosc_set_format_counts()

    -- new path isn't an url
    if not new_url then return menu_close() end

    -- open or update menu
    if opts.start_with_menu and url_changed or open_menu_state then
        menu_open(open_menu_state or states.video_menu)
    end
end)

mp.register_event('file-loaded', function()
    if not (opts.fetch_formats and opts.fetch_on_start) then return end
    if not current_url or url_data[current_url] then return end
    download_formats(current_url)
end)

-- run before ytdl_hook, which uses a priority of 10
mp.add_hook('on_load', 9, function()
    local path = mp.get_property('path')
    local data = url_data[path]
    if not (data and data.video_active_id and data.audio_active_id) then return end
    local format = format_string(data.video_active_id, data.audio_active_id)
    msg.verbose('setting ytdl-format: ' .. format)
    mp.set_property('file-local-options/ytdl-format', format)
end)

---@param url string
---@param format_id string
mp.register_script_message('video-format-set', function(url, format_id)
    menu_close()
    local data = url_data[url]
    set_format(url, format_id, sanitize_format_id(data.audio_active_id, data.audio_formats))
end)

---@param url string
---@param format_id string
mp.register_script_message('audio-format-set', function(url, format_id)
    menu_close()
    local data = url_data[url]
    set_format(url, sanitize_format_id(data.video_active_id, data.video_formats), format_id)
end)

--- check if uosc is running
---@param version string
mp.register_script_message('uosc-version', function(version)
    ---Like the comperator for table.sort, this returns v1 < v2
    ---Assumes two valid semver strings
    ---@param v1 string
    ---@param v2 string
    ---@return boolean
    local function semver_comp(v1, v2)
        local v1_iterator = v1:gmatch('%d+')
        local v2_iterator = v2:gmatch('%d+')
        for v2_num_str in v2_iterator do
            local v1_num_str = v1_iterator()
            if not v1_num_str then return true end
            local v1_num = tonumber(v1_num_str)
            local v2_num = tonumber(v2_num_str)
            if v1_num < v2_num then return true end
            if v1_num > v2_num then return false end
        end
        return false
    end

    local min_version = '4.6.0'
    uosc_available = not semver_comp(version, min_version)
    if not uosc_available then return end
    uosc_set_format_counts()
    mp.commandv(
        'script-message-to',
        'uosc',
        'overwrite-binding',
        'stream-quality',
        'script-binding ' .. script_name .. '/video_formats_toggle'
    )
    ---@param name string
    mp.register_script_message('uosc-menu-closed', function(name)
        -- got closed from the uosc side
        if open_menu_state and open_menu_state.name == name then
            destructor = nil
            menu_close()
        end
    end)
end)
mp.commandv('script-message-to', 'uosc', 'get-version', mp.get_script_name())
