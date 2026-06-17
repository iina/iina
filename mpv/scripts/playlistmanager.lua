local settings = {

  -- #### FUNCTIONALITY SETTINGS

  --navigation keybindings force override only while playlist is visible
  --if "no" then you can display the playlist by any of the navigation keys
  dynamic_binds = true,

  -- to bind multiple keys separate them by a space

  -- main key to show playlist
  key_showplaylist = "SHIFT+ENTER",

  -- display playlist while key is held down
  key_peek_at_playlist = "",

  -- dynamic keys
  key_moveup = "UP",
  key_movedown = "DOWN",
  key_movepageup = "PGUP",
  key_movepagedown = "PGDWN",
  key_movebegin = "HOME",
  key_moveend = "END",
  key_selectfile = "RIGHT LEFT",
  key_unselectfile = "",
  key_playfile = "ENTER",
  key_removefile = "BS",
  key_closeplaylist = "ESC SHIFT+ENTER",

  -- extra functionality keys
  key_sortplaylist = "",
  key_shuffleplaylist = "",
  key_reverseplaylist = "",
  key_loadfiles = "",
  key_saveplaylist = "",

  --replaces matches on filenames based on extension, put as empty string to not replace anything
  --replace rules are executed in provided order
  --replace rule key is the pattern and value is the replace value
  --uses :gsub('pattern', 'replace'), read more http://lua-users.org/wiki/StringLibraryTutorial
  --'all' will match any extension or protocol if it has one
  --uses json and parses it into a lua table to be able to support .conf file

  filename_replace = [[
    [
      {
        "protocol": { "all": true },
        "rules": [
          { "%%(%x%x)": "hex_to_char" }
        ]
      }
    ]
  ]],

--[=====[ START OF SAMPLE REPLACE - Remove this line to use it
  --Sample replace: replaces underscore to space on all files
  --for mp4 and webm; remove extension, remove brackets and surrounding whitespace, change dot between alphanumeric to space
  filename_replace = [[
    [
      {
        "ext": { "all": true},
        "rules": [
          { "_" : " " }
        ]
      },{
        "ext": { "mp4": true, "mkv": true },
        "rules": [
          { "^(.+)%..+$": "%1" },
          { "%s*[%[%(].-[%]%)]%s*": "" },
          { "(%w)%.(%w)": "%1 %2" }
        ]
      },{
        "protocol": { "http": true, "https": true },
        "rules": [
          { "^%a+://w*%.?": "" }
        ]
      }
    ]
  ]],
--END OF SAMPLE REPLACE ]=====]

  --json array of filetypes to search from directory
  loadfiles_filetypes = [[
    [
      "jpg", "jpeg", "png", "tif", "tiff", "gif", "webp", "svg", "bmp",
      "mp3", "wav", "ogm", "flac", "m4a", "wma", "ogg", "opus",
      "mkv", "avi", "mp4", "ogv", "webm", "rmvb", "flv", "wmv", "mpeg", "mpg", "m4v", "3gp"
    ]
  ]],

  --loadfiles at startup if 1 or more items in playlist
  loadfiles_on_start = false,
  -- loadfiles from working directory on idle startup
  loadfiles_on_idle_start = false,
  --always put loaded files after currently playing file
  loadfiles_always_append = false,

  --sort playlist when files are added to playlist
  sortplaylist_on_file_add = false,

  --default sorting method, must be one of: "name-asc", "name-desc", "date-asc", "date-desc", "size-asc", "size-desc".
  default_sort = "name-asc",

  --"linux | windows | auto"
  system = "auto",

  --Use ~ for home directory. Leave as empty to use mpv/playlists
  playlist_savepath = "",

  -- constant filename to save playlist as. Note that it will override existing playlist. Leave empty for generated name.
  playlist_save_filename = "",

  --save playlist automatically after current file was unloaded
  save_playlist_on_file_end = false,


  --show file title every time a new file is loaded
  show_title_on_file_load = false,
  --show playlist every time a new file is loaded
  show_playlist_on_file_load = false,
  --close playlist when selecting file to play
  close_playlist_on_playfile = false,

  --sync cursor when file is loaded from outside reasons(file-ending, playlist-next shortcut etc.)
  --has the sideeffect of moving cursor if file happens to change when navigating
  --good side is cursor always following current file when going back and forth files with playlist-next/prev
  sync_cursor_on_load = true,

  --allow the playlist cursor to loop from end to start and vice versa
  loop_cursor = true,

  --youtube-dl executable for title resolving if enabled, probably "youtube-dl" or "yt-dlp", can be absolute path
  youtube_dl_executable = "youtube-dl",

  -- allow playlistmanager to write watch later config when navigating between files
  allow_write_watch_later_config = true,

  -- reset cursor navigation when closing or opening playlist
  reset_cursor_on_close = true,
  reset_cursor_on_open = true,

  --####  VISUAL SETTINGS

  --prefer to display titles for following files: "all", "url", "none". Sorting still uses filename.
  prefer_titles = "url",

  --call youtube-dl to resolve the titles of urls in the playlist
  resolve_url_titles = false,

  --call ffprobe to resolve the titles of local files in the playlist (if they exist in the metadata)
  resolve_local_titles = false,

  -- timeout in seconds for url title resolving
  resolve_title_timeout = 15,

  -- how many url titles can be resolved at a time. Higher number might lead to stutters.
  concurrent_title_resolve_limit = 10,

  --osd timeout on inactivity in seconds, use 0 for no timeout
  playlist_display_timeout = 0,

  -- when peeking at playlist, show playlist at the very least for display timeout
  peek_respect_display_timeout = false,

  -- the maximum amount of lines playlist will render. -1 will automatically calculate lines.
  showamount = -1,

  --playlist ass style overrides inside curly brackets, \keyvalue is one field, extra \ for escape in lua
  --example {\\q2\\an7\\fnUbuntu\\fs10\\b0\\bord1} equals: line-wrap=no, align=top left, font=Ubuntu, size=10, bold=no, border=1
  --read http://docs.aegisub.org/3.2/ASS_Tags/ for reference of tags
  --undeclared tags will use default osd settings
  --these styles will be used for the whole playlist
  --\\q2 style is recommended since filename wrapping may lead to unexpected rendering
  --\\an7 style is recommended to align to top left otherwise, osd-align-x/y is respected
  style_ass_tags = "{\\q2\\an7}",
  --paddings for left right and top bottom, depends on alignment 
  text_padding_x = 30,
  text_padding_y = 60,
  
  --screen dim when menu is open 0.0 - 1.0 (0 is no dim, 1 is black)
  curtain_opacity=0.0,

  --set title of window with stripped name
  set_title_stripped = false,
  title_prefix = "",
  title_suffix = " - mpv",

  --slice long filenames, and how many chars to show
  slice_longfilenames = false,
  slice_longfilenames_amount = 70,

  --Playlist header template
  --%mediatitle or %filename = title or name of playing file
  --%pos = position of playing file
  --%cursor = position of navigation
  --%plen = playlist length
  --%N = newline
  playlist_header = "[%cursor/%plen]",

  --Playlist file templates
  --%pos = position of file with leading zeros
  --%name = title or name of file
  --%N = newline
  --you can also use the ass tags mentioned above. For example:
  --  selected_file="{\\c&HFF00FF&}➔ %name"   | to add a color for selected file. However, if you
  --  use ass tags you need to reset them for every line (see https://github.com/jonniek/mpv-playlistmanager/issues/20)
  normal_file = "○ %name",
  hovered_file = "● %name",
  selected_file = "➔ %name",
  playing_file = "▷ %name",
  playing_hovered_file = "▶ %name",
  playing_selected_file = "➤ %name",


  -- what to show when playlist is truncated
  playlist_sliced_prefix = "...",
  playlist_sliced_suffix = "...",

  --output visual feedback to OSD for tasks
  display_osd_feedback = true,
}
local opts = require("mp.options")
opts.read_options(settings, "playlistmanager", function(list) update_opts(list) end)

local utils = require("mp.utils")
local msg = require("mp.msg")
local assdraw = require("mp.assdraw")

local alignment_table = {
    [1] = { ["x"] = "left",   ["y"] = "bottom" },
    [2] = { ["x"] = "center", ["y"] = "bottom" },
    [3] = { ["x"] = "right",  ["y"] = "bottom" },
    [4] = { ["x"] = "left",   ["y"] = "center" },
    [5] = { ["x"] = "center", ["y"] = "center" },
    [6] = { ["x"] = "right",  ["y"] = "center" },
    [7] = { ["x"] = "left",   ["y"] = "top" },
    [8] = { ["x"] = "center", ["y"] = "top" },
    [9] = { ["x"] = "right",  ["y"] = "top" },
}

--check os
if settings.system=="auto" then
  local o = {}
  if mp.get_property_native('options/vo-mmcss-profile', o) ~= o then
    settings.system = "windows"
  else
    settings.system = "linux"
  end
end

-- auto calculate showamount
if settings.showamount == -1 then
  -- same as draw_playlist() height
  local h = 720
  
  local playlist_h = h
  -- both top and bottom with same padding
  playlist_h = playlist_h - settings.text_padding_y * 2
  
  -- osd-font-size is based on 720p height
  -- see https://mpv.io/manual/stable/#options-osd-font-size 
  -- details in https://mpv.io/manual/stable/#options-sub-font-size
  -- draw_playlist() is based on 720p, need some conversion
  local fs = mp.get_property_native('osd-font-size') * h / 720
  -- get the ass font size
  if settings.style_ass_tags ~= nil then
    local ass_fs_tag = settings.style_ass_tags:match('\\fs%d+')
    if ass_fs_tag ~= nil then
      fs = tonumber(ass_fs_tag:match('%d+'))
    end
  end
 
  settings.showamount = math.floor(playlist_h / fs)
  
  -- exclude the header line
  if settings.playlist_header ~= "" then
    settings.showamount = settings.showamount - 1
    -- probably some newlines (%N or \N) in the header
    for _ in settings.playlist_header:gmatch('%%N') do
      settings.showamount = settings.showamount - 1
    end
    for _ in settings.playlist_header:gmatch('\\N') do
      settings.showamount = settings.showamount - 1
    end
  end
  
  msg.info('auto showamount: ' .. settings.showamount)
end

--global variables
local playlist_overlay = mp.create_osd_overlay("ass-events")
local playlist_visible = false
local strippedname = nil
local path = nil
local directory = nil
local filename = nil
local pos = 0
local plen = 0
local cursor = 0
--table for saved media titles for later if we prefer them
local title_table = {}
-- table for urls and local file paths that we have requested to be resolved to titles
local requested_titles = {}

local filetype_lookup = {}

function refresh_UI()
  if not playlist_visible then return end
  refresh_globals()
  if plen == 0 then return end
  draw_playlist()
end

function update_opts(changelog)
  msg.verbose('updating options')

  --parse filename json
  if changelog.filename_replace then
    if(settings.filename_replace~="") then
      settings.filename_replace = utils.parse_json(settings.filename_replace)
    else
      settings.filename_replace = false
    end
  end

  --parse loadfiles json
  if changelog.loadfiles_filetypes then
    settings.loadfiles_filetypes = utils.parse_json(settings.loadfiles_filetypes)

    filetype_lookup = {}
    --create loadfiles set
    for _, ext in ipairs(settings.loadfiles_filetypes) do
      filetype_lookup[ext] = true
    end
  end

  if changelog.resolve_url_titles then
    resolve_titles()
  end

  if changelog.resolve_local_titles then
    resolve_titles()
  end

  if changelog.playlist_display_timeout then
    keybindstimer = mp.add_periodic_timer(settings.playlist_display_timeout, remove_keybinds)
    keybindstimer:kill()
  end

  refresh_UI()
end

update_opts({filename_replace = true, loadfiles_filetypes = true})

----- winapi start -----
-- in windows system, we can use the sorting function provided by the win32 API
-- see https://learn.microsoft.com/en-us/windows/win32/api/shlwapi/nf-shlwapi-strcmplogicalw
local winapisort = nil
if settings.system == "windows" then
  -- ffiok is false usually means the mpv builds without luajit
  local ffiok, ffi = pcall(require, "ffi")
  if ffiok then
    ffi.cdef[[
      int MultiByteToWideChar(unsigned int CodePage, unsigned long dwFlags, const char *lpMultiByteStr, int cbMultiByte, wchar_t *lpWideCharStr, int cchWideChar);
      int StrCmpLogicalW(const wchar_t * psz1, const wchar_t * psz2);        
    ]]
   
    local shlwapi = ffi.load("shlwapi.dll")
    
    function MultiByteToWideChar(MultiByteStr)
      local UTF8_CODEPAGE = 65001
      if MultiByteStr then
        local utf16_len = ffi.C.MultiByteToWideChar(UTF8_CODEPAGE, 0, MultiByteStr, -1, nil, 0)
        if utf16_len > 0 then
          local utf16_str = ffi.new("wchar_t[?]", utf16_len)
          if ffi.C.MultiByteToWideChar(UTF8_CODEPAGE, 0, MultiByteStr, -1, utf16_str, utf16_len) > 0 then
            return utf16_str
          end
        end
      end
      return ""
    end
    
    winapisort = function (a, b)
      return shlwapi.StrCmpLogicalW(MultiByteToWideChar(a), MultiByteToWideChar(b)) < 0
    end
    
  end
end
----- winapi end -----

local sort_modes = {
  {
    id="name-asc",
    title="name ascending",
    sort_fn=function (a, b, playlist)
      if winapisort ~= nil then 
        return winapisort(playlist[a].string, playlist[b].string)
      end
      return alphanumsort(playlist[a].string, playlist[b].string)
    end,
  },
  {
    id="name-desc",
    title="name descending",
    sort_fn=function (a, b, playlist)
      if winapisort ~= nil then 
        return winapisort(playlist[b].string, playlist[a].string)
      end
      return alphanumsort(playlist[b].string, playlist[a].string)
    end,
  },
  {
    id="date-asc",
    title="date ascending",
    sort_fn=function (a, b)
      return (get_file_info(a).mtime or 0) < (get_file_info(b).mtime or 0)
    end,
  },
  {
    id="date-desc",
    title="date descending",
    sort_fn=function (a, b)
      return (get_file_info(a).mtime or 0) > (get_file_info(b).mtime or 0)
    end,
  },
  {
    id="size-asc",
    title="size ascending",
    sort_fn=function (a, b)
      return (get_file_info(a).size or 0) < (get_file_info(b).size or 0)
    end,
  },
  {
    id="size-desc",
    title="size descending",
    sort_fn=function (a, b)
      return (get_file_info(a).size or 0) > (get_file_info(b).size or 0)
    end,
  },
}

local sort_mode = 1
for mode, sort_data in pairs(sort_modes) do
  if sort_data.id == settings.default_sort then
    sort_mode = mode
  end
end

function is_protocol(path)
  return type(path) == 'string' and path:match('^%a[%a%d-_]+://') ~= nil
end

function on_file_loaded()
  refresh_globals()
  if settings.sync_cursor_on_load then cursor=pos end
  refresh_UI() -- refresh only after moving cursor

  filename = mp.get_property("filename")
  path = mp.get_property('path')
  local media_title = mp.get_property("media-title")
  if is_protocol(path) and not title_table[path] and path ~= media_title then
    title_table[path] = media_title
  end


  strippedname = stripfilename(mp.get_property('media-title'))
  if settings.show_title_on_file_load then
    mp.commandv('show-text', strippedname)
  end
  if settings.show_playlist_on_file_load then
    showplaylist()
  end
  if settings.set_title_stripped then
    mp.set_property("title", settings.title_prefix..strippedname..settings.title_suffix)
  end
end

function on_start_file()
  refresh_globals()
  filename = mp.get_property("filename")
  path = mp.get_property('path')
  --if not a url then join path with working directory
  if not is_protocol(path) then
    path = utils.join_path(mp.get_property('working-directory'), path)
    directory = utils.split_path(path)
  else
    directory = nil
  end

  if settings.loadfiles_on_start and plen == 1 then
    local ext = filename:match("%.([^%.]+)$")
    -- a directory or playlist has been loaded, let's not do anything as mpv will expand it into files
    if ext and filetype_lookup[ext:lower()] then
      msg.info("Loading files from playing files directory")
      playlist()
    end
  end
end

function on_end_file()
  if settings.save_playlist_on_file_end then save_playlist() end
  strippedname = nil
  path = nil
  directory = nil
  filename = nil
end

function refresh_globals()
  pos = mp.get_property_number('playlist-pos', 0)
  plen = mp.get_property_number('playlist-count', 0)
end

function escapepath(dir, escapechar)
  return string.gsub(dir, escapechar, '\\'..escapechar)
end

function replace_table_has_value(value, valid_values)
  if value == nil or valid_values == nil then
    return false
  end
  return valid_values['all'] or valid_values[value]
end

local filename_replace_functions = {
  --decode special characters in url
  hex_to_char = function(x) return string.char(tonumber(x, 16)) end
}

--strip a filename based on its extension or protocol according to rules in settings
function stripfilename(pathfile, media_title)
  if pathfile == nil then return '' end
  local ext = pathfile:match("%.([^%.]+)$")
  local protocol = pathfile:match("^(%a%a+)://")
  if not ext then ext = "" end
  local tmp = pathfile
  if settings.filename_replace and not media_title then
    for k,v in ipairs(settings.filename_replace) do
      if replace_table_has_value(ext, v['ext']) or replace_table_has_value(protocol, v['protocol']) then
        for ruleindex, indexrules in ipairs(v['rules']) do
          for rule, override in pairs(indexrules) do
            override = filename_replace_functions[override] or override
            tmp = tmp:gsub(rule, override)
          end
        end
      end
    end
  end
  if settings.slice_longfilenames and tmp:len()>settings.slice_longfilenames_amount+5 then
    tmp = tmp:sub(1, settings.slice_longfilenames_amount).." ..."
  end
  return tmp
end

--gets the file info of an item
function get_file_info(item)
  local path = mp.get_property('playlist/' .. item - 1 .. '/filename')
  if is_protocol(path) then return {} end
  local file_info = utils.file_info(path)
  if not file_info then
    msg.warn('failed to read file info for', path)
    return {}
  end

  return file_info
end

--gets a nicename of playlist entry at 0-based position i
function get_name_from_index(i, notitle)
  refresh_globals()
  if plen <= i then msg.error("no index in playlist", i, "length", plen); return nil end
  local _, name = nil
  local title = mp.get_property('playlist/'..i..'/title')
  local name = mp.get_property('playlist/'..i..'/filename')

  local should_use_title = settings.prefer_titles == 'all' or is_protocol(name) and settings.prefer_titles == 'url'
  --check if file has a media title stored or as property
  if not title and should_use_title then
    local mtitle = mp.get_property('media-title')
    if i == pos and mp.get_property('filename') ~= mtitle then
      if not title_table[name] then
        title_table[name] = mtitle
      end
      title = mtitle
    elseif title_table[name] then
      title = title_table[name]
    end
  end

  --if we have media title use a more conservative strip
  if title and not notitle and should_use_title then
    -- Escape a string for verbatim display on the OSD
    -- Ref: https://github.com/mpv-player/mpv/blob/94677723624fb84756e65c8f1377956667244bc9/player/lua/stats.lua#L145
    return stripfilename(title, true):gsub("\\", '\\\239\187\191'):gsub("{", "\\{"):gsub("^ ", "\\h")
  end

  --remove paths if they exist, keeping protocols for stripping
  if string.sub(name, 1, 1) == '/' or name:match("^%a:[/\\]") then
    _, name = utils.split_path(name)
  end
  return stripfilename(name):gsub("\\", '\\\239\187\191'):gsub("{", "\\{"):gsub("^ ", "\\h")
end

function parse_header(string)
  local esc_title = stripfilename(mp.get_property("media-title"), true):gsub("%%", "%%%%")
  local esc_file = stripfilename(mp.get_property("filename")):gsub("%%", "%%%%")
  return string:gsub("%%N", "\\N")
               -- add a blank character at the end of each '\N'  to ensure that the height of the empty line is the same as the non empty line
               :gsub("\\N", "\\N ")
               :gsub("%%pos", mp.get_property_number("playlist-pos",0)+1)
               :gsub("%%plen", mp.get_property("playlist-count"))
               :gsub("%%cursor", cursor+1)
               :gsub("%%mediatitle", esc_title)
               :gsub("%%filename", esc_file)
               -- undo name escape
               :gsub("%%%%", "%%")
end

function parse_filename(string, name, index)
  local base = tostring(plen):len()
  local esc_name = stripfilename(name):gsub("%%", "%%%%")
  return string:gsub("%%N", "\\N")
               :gsub("%%pos", string.format("%0"..base.."d", index+1))
               :gsub("%%name", esc_name)
               -- undo name escape
               :gsub("%%%%", "%%")
end

function parse_filename_by_index(index)
  local template = settings.normal_file

  local is_idle = mp.get_property_native('idle-active')
  local position = is_idle and -1 or pos

  if index == position then
    if index == cursor then
      if selection then
        template = settings.playing_selected_file
      else
        template = settings.playing_hovered_file
      end
    else
      template = settings.playing_file
    end
  elseif index == cursor then
    if selection then
      template = settings.selected_file
    else
      template = settings.hovered_file
    end
  end

  return parse_filename(template, get_name_from_index(index), index)
end

function draw_playlist()
  refresh_globals()
  local ass = assdraw.ass_new()
	
  local _, _, a = mp.get_osd_size()
  local h = 720
  local w = math.ceil(h * a)

  if settings.curtain_opacity ~= nil and settings.curtain_opacity ~= 0 and settings.curtain_opacity <= 1.0 then
  -- curtain dim from https://github.com/christoph-heinrich/mpv-quality-menu/blob/501794bfbef468ee6a61e54fc8821fe5cd72c4ed/quality-menu.lua#L699-L707
    local alpha = 255 - math.ceil(255 * settings.curtain_opacity)
    ass.text = string.format('{\\pos(0,0)\\rDefault\\an7\\1c&H000000&\\alpha&H%X&}', alpha)
    ass:draw_start()
    ass:rect_cw(0, 0, w, h)
    ass:draw_stop()
    ass:new_event()
  end
	
  ass:append(settings.style_ass_tags)

  -- align from mpv.conf
  local align_x = mp.get_property("osd-align-x")
  local align_y = mp.get_property("osd-align-y")
  -- align from style_ass_tags
  if settings.style_ass_tags ~= nil then
    local an = tonumber(settings.style_ass_tags:match('\\an(%d)'))
    if an ~= nil and alignment_table[an] ~= nil then
      align_x = alignment_table[an]["x"]
      align_y = alignment_table[an]["y"]
    end
  end
  -- range of x [0, w-1]
  local pos_x
  if align_x == 'left' then
    pos_x = settings.text_padding_x
  elseif align_x == 'right' then
    pos_x = w - 1 - settings.text_padding_x
  else
    pos_x = math.floor((w - 1) / 2)
  end
  -- range of y [0, h-1]
  local pos_y
  if align_y == 'top' then
    pos_y = settings.text_padding_y
  elseif align_y == 'bottom' then
    pos_y = h - 1 - settings.text_padding_y
  else
    pos_y = math.floor((h - 1) / 2)
  end
  ass:pos(pos_x, pos_y)

  if settings.playlist_header ~= "" then
    ass:append(parse_header(settings.playlist_header).."\\N")
  end

  -- (visible index, playlist index) pairs of playlist entries that should be rendered
  local visible_indices = {}

  local one_based_cursor = cursor + 1
  table.insert(visible_indices, one_based_cursor)

  local offset = 1;
  local visible_indices_length = 1;
  while visible_indices_length < settings.showamount and visible_indices_length < plen do
    -- add entry for offset steps below the cursor
    local below = one_based_cursor + offset
    if below <= plen then
      table.insert(visible_indices, below)
      visible_indices_length = visible_indices_length + 1;
    end

    -- add entry for offset steps above the cursor
    -- also need to double check that there is still space, this happens if we have even numbered limit
    local above = one_based_cursor - offset
    if above >= 1 and visible_indices_length < settings.showamount and visible_indices_length < plen then
      table.insert(visible_indices, 1, above)
      visible_indices_length = visible_indices_length + 1;
    end

    offset = offset + 1
  end

  -- both indices are 1 based
  for display_index, playlist_index in pairs(visible_indices) do
    if display_index == 1 and playlist_index ~= 1 then
      ass:append(settings.playlist_sliced_prefix.."\\N")
    elseif display_index == settings.showamount and playlist_index ~= plen then
      ass:append(settings.playlist_sliced_suffix)
    else
      -- parse_filename_by_index expects 0 based index
      ass:append(parse_filename_by_index(playlist_index - 1).."\\N")
    end
  end

  playlist_overlay.data = ass.text
  playlist_overlay:update()
end

local peek_display_timer = nil
local peek_button_pressed = false

function peek_timeout()
  peek_display_timer:kill()
  if not peek_button_pressed and not playlist_visible then
    remove_keybinds()
  end
end

function handle_complex_playlist_toggle(table)
  local event = table["event"]
  if event == "press" then
    msg.error("Complex key event not supported. Falling back to normal playlist display.")
    showplaylist()
  elseif event == "down" then
    showplaylist(1000000)
    if settings.peek_respect_display_timeout then
      peek_button_pressed = true
      peek_display_timer = mp.add_periodic_timer(settings.playlist_display_timeout, peek_timeout)
    end
  elseif event == "up" then
    -- set playlist state to not visible, doesn't actually hide playlist yet
    -- this will allow us to check if other functionality has rendered playlist before removing binds
    playlist_visible = false

    function remove_keybinds_after_timeout()
      -- if playlist is still not visible then lets actually hide it
      -- this lets other keys that interupt the peek to render playlist without peek up event closing it
      if not playlist_visible then
        remove_keybinds()
      end
    end

    if settings.peek_respect_display_timeout then
      peek_button_pressed = false
      if not peek_display_timer:is_enabled() then
        mp.add_timeout(0.01, remove_keybinds_after_timeout)
      end
    else
      -- use small delay to let dynamic binds run before keys are potentially unbound
      mp.add_timeout(0.01, remove_keybinds_after_timeout)
    end
  end
end

function toggle_playlist(show_function)
  local show = show_function or showplaylist
  if playlist_visible then
    remove_keybinds()
  else
    -- toggle always shows without timeout
    show(0)
  end
end

function showplaylist(duration)
  refresh_globals()
  if plen == 0 then return end
  if not playlist_visible and settings.reset_cursor_on_open then
    resetcursor()
  end

  playlist_visible = true
  add_keybinds()

  draw_playlist()
  keybindstimer:kill()

  local dur = tonumber(duration) or settings.playlist_display_timeout
  if dur > 0 then
    keybindstimer = mp.add_periodic_timer(dur, remove_keybinds)
  end
end

function showplaylist_non_interactive(duration)
  refresh_globals()
  if plen == 0 then return end
  if not playlist_visible and settings.reset_cursor_on_open then
    resetcursor()
  end
  playlist_visible = true
  draw_playlist()
  keybindstimer:kill()

  local dur = tonumber(duration) or settings.playlist_display_timeout
  if dur > 0 then
    keybindstimer = mp.add_periodic_timer(dur, remove_keybinds)
  end
end

selection=nil
function selectfile()
  refresh_globals()
  if plen == 0 then return end
  if not selection then
    selection=cursor
  else
    selection=nil
  end
  showplaylist()
end

function unselectfile()
  selection=nil
  showplaylist()
end

function resetcursor()
  selection = nil
  cursor = mp.get_property_number('playlist-pos', 1)
end

function removefile()
  refresh_globals()
  if plen == 0 then return end
  selection = nil
  if cursor==pos then mp.command("script-message unseenplaylist mark true \"playlistmanager avoid conflict when removing file\"") end
  mp.commandv("playlist-remove", cursor)
  if cursor==plen-1 then cursor = cursor - 1 end
  if plen == 1 then
    remove_keybinds()
  else
    showplaylist()
  end
end

function moveup()
  refresh_globals()
  if plen == 0 then return end
  if cursor~=0 then
    if selection then mp.commandv("playlist-move", cursor,cursor-1) end
    cursor = cursor-1
  elseif settings.loop_cursor then
    if selection then mp.commandv("playlist-move", cursor,plen) end
    cursor = plen-1
  end
  showplaylist()
end

function movedown()
  refresh_globals()
  if plen == 0 then return end
  if cursor ~= plen-1 then
    if selection then mp.commandv("playlist-move", cursor,cursor+2) end
    cursor = cursor + 1
  elseif settings.loop_cursor then
    if selection then mp.commandv("playlist-move", cursor,0) end
    cursor = 0
  end
  showplaylist()
end

function movepageup()
  refresh_globals()
  if plen == 0 or cursor == 0 then return end
  local prev_cursor = cursor
  cursor = cursor - settings.showamount
  if cursor < 0 then cursor = 0 end
  if selection then mp.commandv("playlist-move", prev_cursor, cursor) end
  showplaylist()
end

function movepagedown()
  refresh_globals()
  if plen == 0 or cursor == plen-1 then return end
  local prev_cursor = cursor
  cursor = cursor + settings.showamount
  if cursor >= plen then cursor = plen-1 end
  if selection then mp.commandv("playlist-move", prev_cursor, cursor+1) end
  showplaylist()
end

function movebegin()
  refresh_globals()
  if plen == 0 or cursor == 0 then return end
  local prev_cursor = cursor
  cursor = 0
  if selection then mp.commandv("playlist-move", prev_cursor, cursor) end
  showplaylist()
end

function moveend()
  refresh_globals()
  if plen == 0 or cursor == plen-1 then return end
  local prev_cursor = cursor
  cursor = plen-1
  if selection then mp.commandv("playlist-move", prev_cursor, cursor+1) end
  showplaylist()
end

function write_watch_later(force_write)
  if settings.allow_write_watch_later_config then
    if mp.get_property_bool("save-position-on-quit") or force_write then
      mp.command("write-watch-later-config")
    end
  end
end

function playlist_next()
  write_watch_later(true)
  mp.commandv("playlist-next", "weak")
  if settings.close_playlist_on_playfile then
    remove_keybinds()
  end
  refresh_UI()
end

function playlist_prev()
  write_watch_later(true)
  mp.commandv("playlist-prev", "weak")
  if settings.close_playlist_on_playfile then
    remove_keybinds()
  end
  refresh_UI()
end

function playlist_random()
  write_watch_later()
  refresh_globals()
  if plen < 2 then return end
  math.randomseed(os.time())
  local random = pos
  while random == pos do
    random = math.random(0, plen-1)
  end
  mp.set_property("playlist-pos", random)
  if settings.close_playlist_on_playfile then
    remove_keybinds()
  end
end

function playfile()
  refresh_globals()
  if plen == 0 then return end
  selection = nil
  local is_idle = mp.get_property_native('idle-active')
  if cursor ~= pos or is_idle then
    write_watch_later()
    mp.set_property("playlist-pos", cursor)
  else
    if cursor~=plen-1 then
      cursor = cursor + 1
    end
    write_watch_later()
    mp.commandv("playlist-next", "weak")
  end
  if settings.close_playlist_on_playfile then
    remove_keybinds()
  elseif playlist_visible then
    showplaylist()
  end
end

function file_filter(filenames)
    local files = {}
    for i = 1, #filenames do
        local file = filenames[i]
        local ext = file:match('%.([^%.]+)$')
        if ext and filetype_lookup[ext:lower()] then
            table.insert(files, file)
        end
    end
    return files
end

function get_playlist_filenames_set()
  local filenames = {}
  for n=0,plen-1,1 do
    local filename = mp.get_property('playlist/'..n..'/filename')
    local _, file = utils.split_path(filename)
    filenames[file] = true
  end
  return filenames
end

--Creates a playlist of all files in directory, will keep the order and position
--For exaple, Folder has 12 files, you open the 5th file and run this, the remaining 7 are added behind the 5th file and prior 4 files before it
function playlist(force_dir)
  refresh_globals()
  if not directory and plen > 0 then return end
  local hasfile = true
  if plen == 0 then
    hasfile = false
    dir = mp.get_property('working-directory')
  else
    dir = directory
  end

  if dir == "." then dir = "" end
  if force_dir then dir = force_dir end

  local files = file_filter(utils.readdir(dir, "files"))
  if winapisort ~= nil then
    table.sort(files, winapisort)
  else
    table.sort(files, alphanumsort)
  end
  
  
  if files == nil then
    msg.verbose("no files in directory")
    return
  end

  local filenames = get_playlist_filenames_set()
  local c, c2 = 0,0
  if files then
    local cur = false
    local filename = mp.get_property("filename")
    for _, file in ipairs(files) do
      if file == nil or file[1] == "." then
          break
      end
      local appendstr = "append"
      if not hasfile then
        cur = true
        appendstr = "append-play"
        hasfile = true
      end
      if filename == file then
        cur = true
      elseif filenames[file] then
        -- skip files already in playlist
      elseif cur == true or settings.loadfiles_always_append then
        mp.commandv("loadfile", utils.join_path(dir, file), appendstr)
        msg.info("Appended to playlist: " .. file)
        c2 = c2 + 1
      else
        mp.commandv("loadfile", utils.join_path(dir, file), appendstr)
        msg.info("Prepended to playlist: " .. file)
        mp.commandv("playlist-move", mp.get_property_number("playlist-count", 1)-1,  c)
        c = c + 1
      end
    end
    if c2 > 0 or c>0 then
      msg.info("Added "..c + c2.." files to playlist")
    else
      msg.info("No additional files found")
    end
    cursor = mp.get_property_number('playlist-pos', 1)
  else
    msg.error("Could not scan for files: "..(error or ""))
  end
  refresh_globals()
  if playlist_visible then
    showplaylist()
  end
  if settings.display_osd_feedback then
    if c2 > 0 or c>0 then
      mp.osd_message("Added "..c + c2.." files to playlist")
    else
      mp.osd_message("No additional files found")
    end
  end
  return c + c2
end

function parse_home(path)
  if not path:find("^~") then
    return path
  end
  local home_dir = os.getenv("HOME") or os.getenv("USERPROFILE")
  if not home_dir then
    local drive = os.getenv("HOMEDRIVE")
    local path = os.getenv("HOMEPATH")
    if drive and path then
      home_dir = utils.join_path(drive, path)
    else
      msg.error("Couldn't find home dir.")
      return nil
    end
  end
  local result = path:gsub("^~", home_dir)
  return result
end

local interactive_save = false
function activate_playlist_save()
  if interactive_save then
    remove_keybinds()
    mp.command("script-message playlistmanager-save-interactive \"start interactive filenaming process\"")
  else
    save_playlist()
  end
end

--saves the current playlist into a m3u file
function save_playlist(filename)
  local length = mp.get_property_number('playlist-count', 0)
  if length == 0 then return end

  --get playlist save path
  local savepath
  if settings.playlist_savepath == nil or settings.playlist_savepath == "" then
    savepath = mp.command_native({"expand-path", "~~home/"}).."/playlists"
  else
    savepath = parse_home(settings.playlist_savepath)
    if savepath == nil then return end
  end

  --create savepath if it doesn't exist
  if utils.readdir(savepath) == nil then
    local windows_args = {'powershell', '-NoProfile', '-Command', 'mkdir', savepath}
    local unix_args = { 'mkdir', savepath }
    local args = settings.system == 'windows' and windows_args or unix_args
    local res = utils.subprocess({ args = args, cancellable = false })
    if res.status ~= 0 then
      msg.error("Failed to create playlist save directory "..savepath..". Error: "..(res.error or "unknown"))
      return
    end
  end

  local name = filename
  if name == nil then
    if settings.playlist_save_filename == nil or settings.playlist_save_filename == "" then
      local date = os.date("*t")
      local datestring = ("%02d-%02d-%02d_%02d-%02d-%02d"):format(date.year, date.month, date.day, date.hour, date.min, date.sec)

      name = datestring.."_playlist-size_"..length..".m3u"
    else
      name = settings.playlist_save_filename
    end
  end

  local savepath = utils.join_path(savepath, name)
  local file, err = io.open(savepath, "w")
  if not file then
    msg.error("Error in creating playlist file, check permissions. Error: "..(err or "unknown"))
  else
    file:write("#EXTM3U\n")
    local i=0
    while i < length do
      local pwd = mp.get_property("working-directory")
      local filename = mp.get_property('playlist/'..i..'/filename')
      local fullpath = filename
      if not is_protocol(filename) then
        fullpath = utils.join_path(pwd, filename)
      end
      local title = mp.get_property('playlist/'..i..'/title') or title_table[filename]
      if title then
        file:write("#EXTINF:,"..title.."\n")
      end
      file:write(fullpath, "\n")
      i=i+1
    end
    local saved_msg = "Playlist written to: "..savepath
    if settings.display_osd_feedback then mp.osd_message(saved_msg) end
    msg.info(saved_msg)
    file:close()
  end
end

function alphanumsort(a, b)
  local function padnum(d)
    local dec, n = string.match(d, "(%.?)0*(.+)")
    return #dec > 0 and ("%.12f"):format(d) or ("%s%03d%s"):format(dec, #n, n)
  end
  return tostring(a):lower():gsub("%.?%d+",padnum)..("%3d"):format(#b)
       < tostring(b):lower():gsub("%.?%d+",padnum)..("%3d"):format(#a)
end

-- fast sort algo from https://github.com/zsugabubus/dotfiles/blob/master/.config/mpv/scripts/playlist-filtersort.lua
function sortplaylist(startover)
  local playlist = mp.get_property_native('playlist')
  if #playlist < 2 then return end

  local order = {}
  for i=1, #playlist do
		order[i] = i
    playlist[i].string = get_name_from_index(i - 1, true)
	end

  table.sort(order, function(a, b)
    return sort_modes[sort_mode].sort_fn(a, b, playlist)
  end)

  for i=1, #playlist do
    playlist[order[i]].new_pos = i
  end

  for i=1, #playlist do
    while true do
      local j = playlist[i].new_pos
      if i == j then
        break
      end
      mp.commandv('playlist-move', (i)     - 1, (j + 1) - 1)
      mp.commandv('playlist-move', (j - 1) - 1, (i)     - 1)
      playlist[j], playlist[i] = playlist[i], playlist[j]
    end
  end

  for i = 1, #playlist do
    local filename = mp.get_property('playlist/' .. i - 1 .. '/filename')
    local ext = filename:match("%.([^%.]+)$")
    if not ext or not filetype_lookup[ext:lower()] then
      --move the directory to the end of the playlist
      mp.commandv('playlist-move', i - 1, #playlist)
    end
  end

  cursor = mp.get_property_number('playlist-pos', 0)
  if startover then
    mp.set_property('playlist-pos', 0)
  end
  if playlist_visible then
    showplaylist()
  end
  if settings.display_osd_feedback then
    mp.osd_message("Playlist sorted with "..sort_modes[sort_mode].title)
  end
end

function reverseplaylist()
  local length = mp.get_property_number('playlist-count', 0)
  if length < 2 then return end
  for outer=1, length-1, 1 do
    mp.commandv('playlist-move', outer, 0)
  end
  if playlist_visible then
    showplaylist()
  end
  if settings.display_osd_feedback then
    mp.osd_message("Playlist reversed")
  end
end

function shuffleplaylist()
  refresh_globals()
  if plen < 2 then return end
  mp.command("playlist-shuffle")
  math.randomseed(os.time())
  mp.commandv("playlist-move", pos, math.random(0, plen-1))

  local playlist = mp.get_property_native('playlist')
  for i = 1, #playlist do
    local filename = mp.get_property('playlist/' .. i - 1 .. '/filename')
    local ext = filename:match("%.([^%.]+)$")
    if not ext or not filetype_lookup[ext:lower()] then
      --move the directory to the end of the playlist
      mp.commandv('playlist-move', i - 1, #playlist)
    end
  end

  mp.set_property('playlist-pos', 0)
  refresh_globals()
  if playlist_visible then
    showplaylist()
  end
  if settings.display_osd_feedback then
    mp.osd_message("Playlist shuffled")
  end
end

function bind_keys(keys, name, func, opts)
  if keys == nil or keys == "" then
    mp.add_key_binding(keys, name, func, opts)
    return
  end
  local i = 1
  for key in keys:gmatch("[^%s]+") do
    local prefix = i == 1 and '' or i
    mp.add_key_binding(key, name..prefix, func, opts)
    i = i + 1
  end
end

function bind_keys_forced(keys, name, func, opts)
  if keys == nil or keys == "" then
    mp.add_forced_key_binding(keys, name, func, opts)
    return
  end
  local i = 1
  for key in keys:gmatch("[^%s]+") do
    local prefix = i == 1 and '' or i
    mp.add_forced_key_binding(key, name..prefix, func, opts)
    i = i + 1
  end
end

function unbind_keys(keys, name)
  if keys == nil or keys == "" then
    mp.remove_key_binding(name)
    return
  end
  local i = 1
  for key in keys:gmatch("[^%s]+") do
    local prefix = i == 1 and '' or i
    mp.remove_key_binding(name..prefix)
    i = i + 1
  end
end

function add_keybinds()
  bind_keys_forced(settings.key_moveup, 'moveup', moveup, "repeatable")
  bind_keys_forced(settings.key_movedown, 'movedown', movedown, "repeatable")
  bind_keys_forced(settings.key_movepageup, 'movepageup', movepageup, "repeatable")
  bind_keys_forced(settings.key_movepagedown, 'movepagedown', movepagedown, "repeatable")
  bind_keys_forced(settings.key_movebegin, 'movebegin', movebegin, "repeatable")
  bind_keys_forced(settings.key_moveend, 'moveend', moveend, "repeatable")
  bind_keys_forced(settings.key_selectfile, 'selectfile', selectfile)
  bind_keys_forced(settings.key_unselectfile, 'unselectfile', unselectfile)
  bind_keys_forced(settings.key_playfile, 'playfile', playfile)
  bind_keys_forced(settings.key_removefile, 'removefile', removefile, "repeatable")
  bind_keys_forced(settings.key_closeplaylist, 'closeplaylist', remove_keybinds)
end

function remove_keybinds()
  keybindstimer:kill()
  keybindstimer = mp.add_periodic_timer(settings.playlist_display_timeout, remove_keybinds)
  keybindstimer:kill()
  playlist_overlay.data = ""
  playlist_overlay:update()
  playlist_visible = false
  if settings.reset_cursor_on_close then
    resetcursor()
  end
  if settings.dynamic_binds then
    unbind_keys(settings.key_moveup, 'moveup')
    unbind_keys(settings.key_movedown, 'movedown')
    unbind_keys(settings.key_movepageup, 'movepageup')
    unbind_keys(settings.key_movepagedown, 'movepagedown')
    unbind_keys(settings.key_movebegin, 'movebegin')
    unbind_keys(settings.key_moveend, 'moveend')
    unbind_keys(settings.key_selectfile, 'selectfile')
    unbind_keys(settings.key_unselectfile, 'unselectfile')
    unbind_keys(settings.key_playfile, 'playfile')
    unbind_keys(settings.key_removefile, 'removefile')
    unbind_keys(settings.key_closeplaylist, 'closeplaylist')
  end
end

keybindstimer = mp.add_periodic_timer(settings.playlist_display_timeout, remove_keybinds)
keybindstimer:kill()

if not settings.dynamic_binds then
  add_keybinds()
end

if settings.loadfiles_on_idle_start and mp.get_property_number('playlist-count', 0) == 0 then
  playlist()
end

mp.observe_property('playlist-count', "number", function(_, plcount)
  --if we promised to listen and sort on playlist size increase do it
  if settings.sortplaylist_on_file_add and (plcount > plen) then
    msg.info("Added files will be automatically sorted")
    refresh_globals()
    sortplaylist()
  end
  refresh_UI()
  resolve_titles()
end)


url_request_queue = {}
function url_request_queue.push(item) table.insert(url_request_queue, item) end
function url_request_queue.pop() return table.remove(url_request_queue, 1) end
local url_titles_to_fetch = url_request_queue
local ongoing_url_requests = {}

function url_fetching_throttler()
  if #url_titles_to_fetch == 0 then
    url_title_fetch_timer:kill()
  end

  local ongoing_url_requests_count = 0
  for _, ongoing in pairs(ongoing_url_requests) do
    if ongoing then
      ongoing_url_requests_count = ongoing_url_requests_count + 1
    end
  end

  -- start resolving some url titles if there is available slots
  local amount_to_fetch = math.max(0, settings.concurrent_title_resolve_limit - ongoing_url_requests_count)
  for index=1,amount_to_fetch,1 do
    local file = url_titles_to_fetch.pop()
    if file then
      ongoing_url_requests[file] = true
      resolve_ytdl_title(file)
    end
  end
end

url_title_fetch_timer = mp.add_periodic_timer(0.1, url_fetching_throttler)
url_title_fetch_timer:kill()

local_request_queue = {}
function local_request_queue.push(item) table.insert(local_request_queue, item) end
function local_request_queue.pop() return table.remove(local_request_queue, 1) end
local local_titles_to_fetch = local_request_queue
local ongoing_local_request = false

-- this will only allow 1 concurrent local title resolve process
function local_fetching_throttler()
  if not ongoing_local_request then
    local file = local_titles_to_fetch.pop()
    if file then
      ongoing_local_request = true
      resolve_ffprobe_title(file)
    end
  end
end

function resolve_titles()
  if settings.prefer_titles == 'none' then return end
  if not settings.resolve_url_titles and not settings.resolve_local_titles then return end

  local length = mp.get_property_number('playlist-count', 0)
  if length < 2 then return end
  -- loop all items in playlist because we can't predict how it has changed
  local added_urls = false
  local added_local = false
  for i=0,length - 1,1 do
    local filename = mp.get_property('playlist/'..i..'/filename')
    local title = mp.get_property('playlist/'..i..'/title')
    if i ~= pos
      and filename
      and not title
      and not title_table[filename]
      and not requested_titles[filename]
    then
      requested_titles[filename] = true
      if filename:match('^https?://') then
        url_titles_to_fetch.push(filename)
        added_urls = true
      elseif settings.prefer_titles == "all" then
        local_titles_to_fetch.push(filename)
        added_local = true
      end
    end
  end
  if added_urls then
    url_title_fetch_timer:resume()
  end
  if added_local then
    local_fetching_throttler()
  end
end

function resolve_ytdl_title(filename)
  local args = {
    settings.youtube_dl_executable,
    '--no-playlist',
    '--flat-playlist',
    '-sJ',
    '--no-config',
    filename,
  }
  local req = mp.command_native_async(
    {
      name = "subprocess",
      args = args,
      playback_only = false,
      capture_stdout = true
    },
    function (success, res)
      ongoing_url_requests[filename] = false
      if res.killed_by_us then
        msg.verbose('Request to resolve url title ' .. filename .. ' timed out')
        return
      end
      if res.status == 0 then
        local json, err = utils.parse_json(res.stdout)
        if not err then
          local is_playlist = json['_type'] and json['_type'] == 'playlist'
          local title = (is_playlist and '[playlist]: ' or '') .. json['title']
          msg.verbose(filename .. " resolved to '" .. title .. "'")
          title_table[filename] = title
          refresh_UI()
        else
          msg.error("Failed parsing json, reason: "..(err or "unknown"))
        end
      else
        msg.error("Failed to resolve url title "..filename.." Error: "..(res.error or "unknown"))
      end
    end
  )

  mp.add_timeout(
    settings.resolve_title_timeout,
    function()
      mp.abort_async_command(req)
      ongoing_url_requests[filename] = false
    end
  )
end

function resolve_ffprobe_title(filename)
  local args = { "ffprobe", "-show_format", "-show_entries", "format=tags", "-loglevel", "quiet", filename }
  local req = mp.command_native_async(
    {
      name = "subprocess",
      args = args,
      playback_only = false,
      capture_stdout = true
    },
    function (success, res)
      ongoing_local_request = false
      local_fetching_throttler()
      if res.killed_by_us then
        msg.verbose('Request to resolve local title ' .. filename .. ' timed out')
        return
      end
      if res.status == 0 then
        local title = string.match(res.stdout, "title=([^\n\r]+)")
        if title then
          msg.verbose(filename .. " resolved to '" .. title .. "'")
          title_table[filename] = title
          refresh_UI()
        end
      else
        msg.error("Failed to resolve local title "..filename.." Error: "..(res.error or "unknown"))
      end
    end
  )
end

--script message handler
function handlemessage(msg, value, value2)
  if msg == "show" and value == "playlist" then
    if value2 ~= "toggle" then
      showplaylist(value2)
      return
    else
      toggle_playlist(showplaylist)
      return
    end
  end
  if msg == "show" and value == "playlist-nokeys" then
    if value2 ~= "toggle" then
      showplaylist_non_interactive(value2)
      return
    else
      toggle_playlist(showplaylist_non_interactive)
      return
    end
  end
  if msg == "show" and value == "filename" and strippedname and value2 then
    mp.commandv('show-text', strippedname, tonumber(value2)*1000 ) ; return
  end
  if msg == "show" and value == "filename" and strippedname then
    mp.commandv('show-text', strippedname ) ; return
  end
  if msg == "sort" then sortplaylist(value) ; return end
  if msg == "shuffle" then shuffleplaylist() ; return end
  if msg == "reverse" then reverseplaylist() ; return end
  if msg == "loadfiles" then playlist(value) ; return end
  if msg == "save" then save_playlist(value) ; return end
  if msg == "playlist-next" then playlist_next() ; return end
  if msg == "playlist-prev" then playlist_prev() ; return end
  if msg == "playlist-next-random" then playlist_random() ; return end
  if msg == "enable-interactive-save" then interactive_save = true end
  if msg == "close" then remove_keybinds() end
end

mp.register_script_message("playlistmanager", handlemessage)

bind_keys(settings.key_sortplaylist, "sortplaylist", function()
  sortplaylist()
  sort_mode = sort_mode + 1
  if sort_mode > #sort_modes then sort_mode = 1 end
end)
bind_keys(settings.key_shuffleplaylist, "shuffleplaylist", shuffleplaylist)
bind_keys(settings.key_reverseplaylist, "reverseplaylist", reverseplaylist)
bind_keys(settings.key_loadfiles, "loadfiles", playlist)
bind_keys(settings.key_saveplaylist, "saveplaylist", activate_playlist_save)
bind_keys(settings.key_showplaylist, "showplaylist", showplaylist)
bind_keys(
  settings.key_peek_at_playlist,
  "peek_at_playlist",
  handle_complex_playlist_toggle,
  { complex=true }
)

mp.register_event("start-file", on_start_file)
mp.register_event("file-loaded", on_file_loaded)
mp.register_event("end-file", on_end_file)
