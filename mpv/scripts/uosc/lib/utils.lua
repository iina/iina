--[[ UI specific utilities that might or might not depend on its state or options ]]

---@alias Point {x: number; y: number}
---@alias Rect {ax: number, ay: number, bx: number, by: number}

--- In place sorting of filenames
---@param filenames string[]

----- winapi start -----
-- in windows system, we can use the sorting function provided by the win32 API
-- see https://learn.microsoft.com/en-us/windows/win32/api/shlwapi/nf-shlwapi-strcmplogicalw
-- this function was taken from https://github.com/mpvnet-player/mpv.net/issues/575#issuecomment-1817413401
local winapi = {}

if state.platform == 'windows' then
	-- is_ffi_loaded is false usually means the mpv builds without luajit
	local is_ffi_loaded, ffi = pcall(require, 'ffi')

	if is_ffi_loaded then
		winapi = {
			ffi = ffi,
			C = ffi.C,
			CP_UTF8 = 65001,
			shlwapi = ffi.load('shlwapi'),
		}

		-- ffi code from https://github.com/po5/thumbfast, Mozilla Public License Version 2.0
		ffi.cdef[[
			int __stdcall MultiByteToWideChar(unsigned int CodePage, unsigned long dwFlags, const char *lpMultiByteStr,
			int cbMultiByte, wchar_t *lpWideCharStr, int cchWideChar);
			int __stdcall StrCmpLogicalW(wchar_t *psz1, wchar_t *psz2);
		]]

		winapi.utf8_to_wide = function(utf8_str)
			if utf8_str then
				local utf16_len = winapi.C.MultiByteToWideChar(winapi.CP_UTF8, 0, utf8_str, -1, nil, 0)

				if utf16_len > 0 then
					local utf16_str = winapi.ffi.new('wchar_t[?]', utf16_len)

					if winapi.C.MultiByteToWideChar(winapi.CP_UTF8, 0, utf8_str, -1, utf16_str, utf16_len) > 0 then
						return utf16_str
					end
				end
			end

			return ''
		end
	end
end
----- winapi end -----

function sort_filenames_windows(filenames)
	table.sort(filenames, function(a, b)
		local a_wide = winapi.utf8_to_wide(a)
		local b_wide = winapi.utf8_to_wide(b)
		return winapi.shlwapi.StrCmpLogicalW(a_wide, b_wide) == -1
	end)

	return filenames
end

function sort_filenames_lua(filenames)
	-- alphanum sorting for humans in Lua
	-- http://notebook.kulchenko.com/algorithms/alphanumeric-natural-sorting-for-humans-in-lua
	local function padnum(n, d)
		return #d > 0 and ('%03d%s%.12f'):format(#n, n, tonumber(d) / (10 ^ #d))
			or ('%03d%s'):format(#n, n)
	end

	local tuples = {}
	for i, f in ipairs(filenames) do
		tuples[i] = {f:lower():gsub('0*(%d+)%.?(%d*)', padnum), f}
	end
	table.sort(tuples, function(a, b)
		return a[1] == b[1] and #b[2] < #a[2] or a[1] < b[1]
	end)
	for i, tuple in ipairs(tuples) do filenames[i] = tuple[2] end
	return filenames
end

function sort_filenames(filenames)
	local is_ffi_loaded = pcall(require, 'ffi')
	if state.platform == 'windows' and is_ffi_loaded then
		sort_filenames_windows(filenames)
	else
		sort_filenames_lua(filenames)
	end
end

-- Creates in-between frames to animate value from `from` to `to` numbers.
---@param from number
---@param to number|fun():number
---@param setter fun(value: number)
---@param duration_or_callback? number|fun() Duration in milliseconds or a callback function.
---@param callback? fun() Called either on animation end, or when animation is killed.
function tween(from, to, setter, duration_or_callback, callback)
	local duration = duration_or_callback
	if type(duration_or_callback) == 'function' then callback = duration_or_callback end
	if type(duration) ~= 'number' then duration = options.animation_duration end

	local current, done, timeout = from, false, nil
	local get_to = type(to) == 'function' and to or function() return to --[[@as number]] end
	local distance = math.abs(get_to() - current)
	local cutoff = distance * 0.01
	local target_ticks = (math.max(duration, 1) / (state.render_delay * 1000))
	local decay = 1 - ((cutoff / distance) ^ (1 / target_ticks))

	local function finish()
		if not done then
			setter(get_to())
			done = true
			timeout:kill()
			if callback then callback() end
			request_render()
		end
	end

	local function tick()
		local to = get_to()
		current = current + ((to - current) * decay)
		local is_end = math.abs(to - current) <= cutoff
		if is_end then
			finish()
		else
			setter(current)
			timeout:resume()
			request_render()
		end
	end

	timeout = mp.add_timeout(state.render_delay, tick)
	if cutoff > 0 then tick() else finish() end

	return finish
end

---@param point Point
---@param rect Rect
function get_point_to_rectangle_proximity(point, rect)
	local dx = math.max(rect.ax - point.x, 0, point.x - rect.bx)
	local dy = math.max(rect.ay - point.y, 0, point.y - rect.by)
	return math.sqrt(dx * dx + dy * dy)
end

---@param point_a Point
---@param point_b Point
function get_point_to_point_proximity(point_a, point_b)
	local dx, dy = point_a.x - point_b.x, point_a.y - point_b.y
	return math.sqrt(dx * dx + dy * dy)
end

---@param lax number
---@param lay number
---@param lbx number
---@param lby number
---@param max number
---@param may number
---@param mbx number
---@param mby number
function get_line_to_line_intersection(lax, lay, lbx, lby, max, may, mbx, mby)
	-- Calculate the direction of the lines
	local uA = ((mbx - max) * (lay - may) - (mby - may) * (lax - max)) /
		((mby - may) * (lbx - lax) - (mbx - max) * (lby - lay))
	local uB = ((lbx - lax) * (lay - may) - (lby - lay) * (lax - max)) /
		((mby - may) * (lbx - lax) - (mbx - max) * (lby - lay))

	-- If uA and uB are between 0-1, lines are colliding
	if uA >= 0 and uA <= 1 and uB >= 0 and uB <= 1 then
		return lax + (uA * (lbx - lax)), lay + (uA * (lby - lay))
	end

	return nil, nil
end

-- Returns distance from the start of a finite ray assumed to be at (rax, ray)
-- coordinates to a line.
---@param rax number
---@param ray number
---@param rbx number
---@param rby number
---@param lax number
---@param lay number
---@param lbx number
---@param lby number
function get_ray_to_line_distance(rax, ray, rbx, rby, lax, lay, lbx, lby)
	local x, y = get_line_to_line_intersection(rax, ray, rbx, rby, lax, lay, lbx, lby)
	if x then
		return math.sqrt((rax - x) ^ 2 + (ray - y) ^ 2)
	end
	return nil
end

-- Returns distance from the start of a finite ray assumed to be at (ax, ay)
-- coordinates to a rectangle. Returns `0` if ray originates inside rectangle.
---@param  ax number
---@param  ay number
---@param  bx number
---@param  by number
---@param  rect Rect
---@return number|nil
function get_ray_to_rectangle_distance(ax, ay, bx, by, rect)
	-- Is inside
	if ax >= rect.ax and ax <= rect.bx and ay >= rect.ay and ay <= rect.by then
		return 0
	end

	local closest = nil

	local function updateDistance(distance)
		if distance and (not closest or distance < closest) then closest = distance end
	end

	updateDistance(get_ray_to_line_distance(ax, ay, bx, by, rect.ax, rect.ay, rect.bx, rect.ay))
	updateDistance(get_ray_to_line_distance(ax, ay, bx, by, rect.bx, rect.ay, rect.bx, rect.by))
	updateDistance(get_ray_to_line_distance(ax, ay, bx, by, rect.ax, rect.by, rect.bx, rect.by))
	updateDistance(get_ray_to_line_distance(ax, ay, bx, by, rect.ax, rect.ay, rect.ax, rect.by))

	return closest
end

-- Call function with args if it exists
function call_maybe(fn, ...)
	if type(fn) == 'function' then fn(...) end
end

-- Extracts the properties used by property expansion of that string.
---@param str string
---@param res { [string] : boolean } | nil
---@return { [string] : boolean }
function get_expansion_props(str, res)
	res = res or {}
	for str in str:gmatch('%$(%b{})') do
		local name, str = str:match('^{[?!]?=?([^:]+):?(.*)}$')
		if name then
			local s = name:find('==') or nil
			if s then name = name:sub(0, s - 1) end
			res[name] = true
			if str and str ~= '' then get_expansion_props(str, res) end
		end
	end
	return res
end

-- Escape a string for verbatim display on the OSD.
---@param str string
function ass_escape(str)
	-- There is no escape for '\' in ASS (I think?) but '\' is used verbatim if
	-- it isn't followed by a recognized character, so add a zero-width
	-- non-breaking space
	str = str:gsub('\\', '\\\239\187\191')
	str = str:gsub('{', '\\{')
	str = str:gsub('}', '\\}')
	-- Precede newlines with a ZWNBSP to prevent ASS's weird collapsing of
	-- consecutive newlines
	str = str:gsub('\n', '\239\187\191\\N')
	-- Turn leading spaces into hard spaces to prevent ASS from stripping them
	str = str:gsub('\\N ', '\\N\\h')
	str = str:gsub('^ ', '\\h')
	return str
end

---@param seconds number
---@param max_seconds number|nil Trims unnecessary `00:` if time is not expected to reach it.
---@return string
function format_time(seconds, max_seconds)
	local human = mp.format_time(seconds)
	if options.time_precision > 0 then
		local formatted = string.format('%.' .. options.time_precision .. 'f', math.abs(seconds) % 1)
		human = human .. '.' .. string.sub(formatted, 3)
	end
	if max_seconds then
		local trim_length = (max_seconds < 60 and 7 or (max_seconds < 3600 and 4 or 0))
		if trim_length > 0 then
			local has_minus = seconds < 0
			human = string.sub(human, trim_length + (has_minus and 1 or 0))
			if has_minus then human = '-' .. human end
		end
	end
	return human
end

---@param opacity number 0-1
function opacity_to_alpha(opacity)
	return 255 - math.ceil(255 * opacity)
end

path_separator = (function()
	local os_separator = state.platform == 'windows' and '\\' or '/'

	-- Get appropriate path separator for the given path.
	---@param path string
	---@return string
	return function(path)
		return path:sub(1, 2) == '\\\\' and '\\' or os_separator
	end
end)()

-- Joins paths with the OS aware path separator or UNC separator.
---@param p1 string
---@param p2 string
---@return string
function join_path(p1, p2)
	local p1, separator = trim_trailing_separator(p1)
	-- Prevents joining drive letters with a redundant separator (`C:\\foo`),
	-- as `trim_trailing_separator()` doesn't trim separators from drive letters.
	return p1:sub(#p1) == separator and p1 .. p2 or p1 .. separator .. p2
end

-- Check if path is absolute.
---@param path string
---@return boolean
function is_absolute(path)
	if path:sub(1, 2) == '\\\\' then
		return true
	elseif state.platform == 'windows' then
		return path:find('^%a+:') ~= nil
	else
		return path:sub(1, 1) == '/'
	end
end

-- Ensure path is absolute.
---@param path string
---@return string
function ensure_absolute(path)
	if is_absolute(path) then return path end
	return join_path(state.cwd, path)
end

-- Remove trailing slashes/backslashes.
---@param path string
---@return string path, string trimmed_separator_type
function trim_trailing_separator(path)
	local separator = path_separator(path)
	path = trim_end(path, separator)
	if state.platform == 'windows' then
		-- Drive letters on windows need trailing backslash
		if path:sub(#path) == ':' then path = path .. '\\' end
	else
		if path == '' then path = '/' end
	end
	return path, separator
end

-- Ensures path is absolute, remove trailing slashes/backslashes.
-- Lightweight version of normalize_path for performance critical parts.
---@param path string
---@return string
function normalize_path_lite(path)
	if not path or is_protocol(path) then return path end
	path = trim_trailing_separator(ensure_absolute(path))
	return path
end

-- Ensures path is absolute, remove trailing slashes/backslashes, normalization of path separators and deduplication.
---@param path string
---@return string
function normalize_path(path)
	if not path or is_protocol(path) then return path end

	path = ensure_absolute(path)
	local is_unc = path:sub(1, 2) == '\\\\'
	if state.platform == 'windows' or is_unc then path = path:gsub('/', '\\') end
	path = trim_trailing_separator(path)

	--Deduplication of path separators
	if is_unc then
		path = path:gsub('(.\\)\\+', '%1')
	elseif state.platform == 'windows' then
		path = path:gsub('\\\\+', '\\')
	else
		path = path:gsub('//+', '/')
	end

	return path
end

-- Check if path is a protocol, such as `http://...`.
---@param path string
function is_protocol(path)
	return type(path) == 'string' and (path:find('^%a[%w.+-]-://') ~= nil or path:find('^%a[%w.+-]-:%?') ~= nil)
end

---@param path string
---@param extensions string[] Lowercase extensions without the dot.
function has_any_extension(path, extensions)
	local path_last_dot_index = string_last_index_of(path, '.')
	if not path_last_dot_index then return false end
	local path_extension = path:sub(path_last_dot_index + 1):lower()
	for _, extension in ipairs(extensions) do
		if path_extension == extension then return true end
	end
	return false
end

---@return string
function get_default_directory()
	return mp.command_native({'expand-path', options.default_directory})
end

-- Serializes path into its semantic parts.
---@param path string
---@return nil|{path: string; is_root: boolean; dirname?: string; basename: string; filename: string; extension?: string;}
function serialize_path(path)
	if not path or is_protocol(path) then return end

	local normal_path = normalize_path_lite(path)
	local dirname, basename = utils.split_path(normal_path)
	if basename == '' then basename, dirname = dirname:sub(1, #dirname - 1), nil end
	local dot_i = string_last_index_of(basename, '.')

	return {
		path = normal_path,
		is_root = dirname == nil,
		dirname = dirname,
		basename = basename,
		filename = dot_i and basename:sub(1, dot_i - 1) or basename,
		extension = dot_i and basename:sub(dot_i + 1) or nil,
	}
end

-- Reads items in directory and splits it into directories and files tables.
---@param path string
---@param opts? {types?: string[], hidden?: boolean}
---@return string[]|nil files
---@return string[]|nil directories
function read_directory(path, opts)
	opts = opts or {}
	local items, error = utils.readdir(path, 'all')

	if not items then
		msg.error('Reading files from "' .. path .. '" failed: ' .. error)
		return nil, nil
	end

	local files, directories = {}, {}

	for _, item in ipairs(items) do
		if item ~= '.' and item ~= '..' and (opts.hidden or item:sub(1, 1) ~= '.') then
			local info = utils.file_info(join_path(path, item))
			if info then
				if info.is_file then
					if not opts.types or has_any_extension(item, opts.types) then
						files[#files + 1] = item
					end
				else
					directories[#directories + 1] = item
				end
			end
		end
	end

	return files, directories
end

-- Returns full absolute paths of files in the same directory as `file_path`,
-- and index of the current file in the table.
-- Returned table will always contain `file_path`, regardless of `allowed_types`.
---@param file_path string
---@param opts? {types?: string[], hidden?: boolean}
function get_adjacent_files(file_path, opts)
	opts = opts or {}
	local current_meta = serialize_path(file_path)
	if not current_meta then return end
	local files = read_directory(current_meta.dirname, {hidden = opts.hidden})
	if not files then return end
	sort_filenames(files)
	local current_file_index
	local paths = {}
	for _, file in ipairs(files) do
		local is_current_file = current_meta.basename == file
		if is_current_file or not opts.types or has_any_extension(file, opts.types) then
			paths[#paths + 1] = join_path(current_meta.dirname, file)
			if is_current_file then current_file_index = #paths end
		end
	end
	if not current_file_index then return end
	return paths, current_file_index
end

-- Navigates in a list, using delta or, when `state.shuffle` is enabled,
-- randomness to determine the next item. Loops around if `loop-playlist` is enabled.
---@param paths table
---@param current_index number
---@param delta number 1 or -1 for forward or backward
function decide_navigation_in_list(paths, current_index, delta)
	if #paths < 2 then return end
	delta = delta < 0 and -1 or 1

	-- Shuffle looks at the played files history trimmed to 80% length of the paths
	-- and removes all paths in it from the potential shuffle pool. This guarantees
	-- no path repetition until at least 80% of the playlist has been exhausted.
	if state.shuffle then
		state.shuffle_history = state.shuffle_history or {
			pos = #state.history,
			paths = itable_slice(state.history),
		}
		state.shuffle_history.pos = state.shuffle_history.pos + delta
		local history_path = state.shuffle_history.paths[state.shuffle_history.pos]
		local next_index = history_path and itable_index_of(paths, history_path)
		if next_index then
			return next_index, history_path
		end
		if delta < 0 then
			state.shuffle_history.pos = state.shuffle_history.pos - delta
		else
			state.shuffle_history.pos = math.min(state.shuffle_history.pos, #state.shuffle_history.paths + 1)
		end

		local trimmed_history = itable_slice(state.history, -math.floor(#paths * 0.8))
		local shuffle_pool = {}

		for index, value in ipairs(paths) do
			if not itable_has(trimmed_history, value) then
				shuffle_pool[#shuffle_pool + 1] = index
			end
		end

		math.randomseed(os.time())
		local next_index = shuffle_pool[math.random(#shuffle_pool)]
		local next_path = paths[next_index]
		table.insert(state.shuffle_history.paths, state.shuffle_history.pos, next_path)
		return next_index, next_path
	end

	local new_index = current_index + delta
	if mp.get_property_native('loop-playlist') then
		if new_index > #paths then
			new_index = new_index % #paths
		elseif new_index < 1 then
			new_index = #paths - new_index
		end
	elseif new_index < 1 or new_index > #paths then
		return
	end

	return new_index, paths[new_index]
end

---@param delta number
function navigate_directory(delta)
	if not state.path or is_protocol(state.path) then return false end
	local paths, current_index = get_adjacent_files(state.path, {
		types = config.types.autoload,
		hidden = options.show_hidden_files,
	})
	if paths and current_index then
		local _, path = decide_navigation_in_list(paths, current_index, delta)
		if path then
			mp.commandv('loadfile', path)
			return true
		end
	end
	return false
end

---@param delta number
function navigate_playlist(delta)
	local playlist, pos = mp.get_property_native('playlist'), mp.get_property_native('playlist-pos-1')
	if playlist and #playlist > 1 and pos then
		local paths = itable_map(playlist, function(item) return normalize_path(item.filename) end)
		local index = decide_navigation_in_list(paths, pos, delta)
		if index then
			mp.commandv('playlist-play-index', index - 1)
			return true
		end
	end
	return false
end

---@param delta number
function navigate_item(delta)
	if state.has_playlist then return navigate_playlist(delta) else return navigate_directory(delta) end
end

-- Can't use `os.remove()` as it fails on paths with unicode characters.
-- Returns `result, error`, result is table of:
-- `status:number(<0=error), stdout, stderr, error_string, killed_by_us:boolean`
---@param path string
function delete_file(path)
	if state.platform == 'windows' then
		if options.use_trash then
			local ps_code = [[
				Add-Type -AssemblyName Microsoft.VisualBasic
				[Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile('__path__', 'OnlyErrorDialogs', 'SendToRecycleBin')
			]]

			local escaped_path = string.gsub(path, "'", "''")
			escaped_path = string.gsub(escaped_path, '’', '’’')
			escaped_path = string.gsub(escaped_path, '%%', '%%%%')
			ps_code = string.gsub(ps_code, '__path__', escaped_path)
			args = {'powershell', '-NoProfile', '-Command', ps_code}
		else
			args = {'cmd', '/C', 'del', path}
		end
	else
		if options.use_trash then
			--On Linux and Macos the app trash-cli/trash must be installed first.
			args = {'trash', path}
		else
			args = {'rm', path}
		end
	end
	return mp.command_native({
		name = 'subprocess',
		args = args,
		playback_only = false,
		capture_stdout = true,
		capture_stderr = true,
	})
end

function delete_file_navigate(delta)
	local path, playlist_pos = state.path, state.playlist_pos
	local is_local_file = path and not is_protocol(path)

	if navigate_item(delta) then
		if state.has_playlist then
			mp.commandv('playlist-remove', playlist_pos - 1)
		end
	else
		mp.command('stop')
	end

	if is_local_file then
		if Menu:is_open('open-file') then
			Elements:maybe('menu', 'delete_value', path)
		end
		delete_file(path)
	end
end

function serialize_chapter_ranges(normalized_chapters)
	local ranges = {}
	local simple_ranges = {
		{
			name = 'openings',
			patterns = {
				'^op ', '^op$', ' op$',
				'^opening$', ' opening$',
			},
			requires_next_chapter = true,
		},
		{
			name = 'intros',
			patterns = {
				'^intro$', ' intro$',
				'^avant$', '^prologue$',
			},
			requires_next_chapter = true,
		},
		{
			name = 'endings',
			patterns = {
				'^ed ', '^ed$', ' ed$',
				'^ending ', '^ending$', ' ending$',
			},
		},
		{
			name = 'outros',
			patterns = {
				'^outro$', ' outro$',
				'^closing$', '^closing ',
				'^preview$', '^pv$',
			},
		},
	}
	local sponsor_ranges = {}

	-- Extend with alt patterns
	for _, meta in ipairs(simple_ranges) do
		local alt_patterns = config.chapter_ranges[meta.name] and config.chapter_ranges[meta.name].patterns
		if alt_patterns then meta.patterns = itable_join(meta.patterns, alt_patterns) end
	end

	-- Clone chapters
	local chapters = {}
	for i, normalized in ipairs(normalized_chapters) do chapters[i] = table_assign({}, normalized) end

	for i, chapter in ipairs(chapters) do
		-- Simple ranges
		for _, meta in ipairs(simple_ranges) do
			if config.chapter_ranges[meta.name] then
				local match = itable_find(meta.patterns, function(p) return chapter.lowercase_title:find(p) end)
				if match then
					local next_chapter = chapters[i + 1]
					if next_chapter or not meta.requires_next_chapter then
						ranges[#ranges + 1] = table_assign({
							start = chapter.time,
							['end'] = next_chapter and next_chapter.time or math.huge,
						}, config.chapter_ranges[meta.name])
					end
				end
			end
		end

		-- Sponsor blocks
		if config.chapter_ranges.ads then
			local id = chapter.lowercase_title:match('segment start *%(([%w]%w-)%)')
			if id then -- ad range from sponsorblock
				for j = i + 1, #chapters, 1 do
					local end_chapter = chapters[j]
					local end_match = end_chapter.lowercase_title:match('segment end *%(' .. id .. '%)')
					if end_match then
						local range = table_assign({
							start_chapter = chapter,
							end_chapter = end_chapter,
							start = chapter.time,
							['end'] = end_chapter.time,
						}, config.chapter_ranges.ads)
						ranges[#ranges + 1], sponsor_ranges[#sponsor_ranges + 1] = range, range
						end_chapter.is_end_only = true
						break
					end
				end -- single chapter for ad
			elseif not chapter.is_end_only and
				(chapter.lowercase_title:find('%[sponsorblock%]:') or chapter.lowercase_title:find('^sponsors?')) then
				local next_chapter = chapters[i + 1]
				ranges[#ranges + 1] = table_assign({
					start = chapter.time,
					['end'] = next_chapter and next_chapter.time or math.huge,
				}, config.chapter_ranges.ads)
			end
		end
	end

	-- Fix overlapping sponsor block segments
	for index, range in ipairs(sponsor_ranges) do
		local next_range = sponsor_ranges[index + 1]
		if next_range then
			local delta = next_range.start - range['end']
			if delta < 0 then
				local mid_point = range['end'] + delta / 2
				range['end'], range.end_chapter.time = mid_point - 0.01, mid_point - 0.01
				next_range.start, next_range.start_chapter.time = mid_point, mid_point
			end
		end
	end
	table.sort(chapters, function(a, b) return a.time < b.time end)

	return chapters, ranges
end

-- Ensures chapters are in chronological order
function normalize_chapters(chapters)
	if not chapters then return {} end
	-- Ensure chronological order
	table.sort(chapters, function(a, b) return a.time < b.time end)
	-- Ensure titles
	for index, chapter in ipairs(chapters) do
		local chapter_number = chapter.title and string.match(chapter.title, '^Chapter (%d+)$')
		if chapter_number then
			chapter.title = t('Chapter %s', tonumber(chapter_number))
		end
		chapter.title = chapter.title ~= '(unnamed)' and chapter.title ~= '' and chapter.title or t('Chapter %s', index)
		chapter.lowercase_title = chapter.title:lower()
	end
	return chapters
end

function serialize_chapters(chapters)
	chapters = normalize_chapters(chapters)
	if not chapters then return end
	--- timeline font size isn't accessible here, so normalize to size 1 and then scale during rendering
	local opts = {size = 1, bold = true}
	for index, chapter in ipairs(chapters) do
		chapter.index = index
		chapter.title_wrapped, chapter.title_lines = wrap_text(chapter.title, opts, 25)
		chapter.title_wrapped_width = text_width(chapter.title_wrapped, opts)
		chapter.title_wrapped = ass_escape(chapter.title_wrapped)
	end
	return chapters
end

---Find all active key bindings or the active key binding for key
---@param key string|nil
---@return {[string]: table}|table
function find_active_keybindings(key)
	local bindings = mp.get_property_native('input-bindings', {})
	local active = {} -- map: key-name -> bind-info
	for _, bind in pairs(bindings) do
		if bind.owner ~= 'uosc' and bind.priority >= 0 and (not key or bind.key == key) and (
				not active[bind.key]
				or (active[bind.key].is_weak and not bind.is_weak)
				or (bind.is_weak == active[bind.key].is_weak and bind.priority > active[bind.key].priority)
			)
		then
			active[bind.key] = bind
		end
	end
	return not key and active or active[key]
end

---@param type 'sub'|'audio'|'video'
---@param path string
function load_track(type, path)
	mp.commandv(type .. '-add', path, 'cached')
	-- If subtitle track was loaded, assume the user also wants to see it
	if type == 'sub' then
		mp.commandv('set', 'sub-visibility', 'yes')
	end
end

---@return string|nil
function get_clipboard()
	local result = mp.command_native({
		name = 'subprocess',
		capture_stderr = true,
		capture_stdout = true,
		playback_only = false,
		args = {config.ziggy_path, 'get-clipboard'},
	})

	local function print_error(message)
		msg.error('Getting clipboard data failed. Error: ' .. message)
	end

	if result.status == 0 then
		local data = utils.parse_json(result.stdout)
		if data and data.payload then
			return data.payload
		else
			print_error(data and (data.error and data.message or 'unknown error') or 'couldn\'t parse json')
		end
	else
		print_error('exit code ' .. result.status .. ': ' .. result.stdout .. result.stderr)
	end
end

--[[ RENDERING ]]

function render()
	if not display.initialized then return end
	state.render_last_time = mp.get_time()

	cursor:clear_zones()

	-- Actual rendering
	local ass = assdraw.ass_new()

	-- Idle indicator
	if state.is_idle and not Manager.disabled.idle_indicator then
		local smaller_side = math.min(display.width, display.height)
		local center_x, center_y, icon_size = display.width / 2, display.height / 2, math.max(smaller_side / 4, 56)
		ass:icon(center_x, center_y - icon_size / 4, icon_size, 'not_started', {
			color = fg, opacity = config.opacity.idle_indicator,
		})
		ass:txt(center_x, center_y + icon_size / 2, 8, t('Drop files or URLs to play here'), {
			size = icon_size / 4, color = fg, opacity = config.opacity.idle_indicator,
		})
	end

	-- Audio indicator
	if state.is_audio and not state.has_image and not Manager.disabled.audio_indicator
		and not (state.pause and options.pause_indicator == 'static') then
		local smaller_side = math.min(display.width, display.height)
		ass:icon(display.width / 2, display.height / 2, smaller_side / 4, 'graphic_eq', {
			color = fg, opacity = config.opacity.audio_indicator,
		})
	end

	-- Elements
	for _, element in Elements:ipairs() do
		if element.enabled then
			local result = element:maybe('render')
			if result then
				ass:new_event()
				ass:merge(result)
			end
		end
	end

	cursor:decide_keybinds()

	-- submit
	if osd.res_x == display.width and osd.res_y == display.height and osd.data == ass.text then
		return
	end

	osd.res_x = display.width
	osd.res_y = display.height
	osd.data = ass.text
	osd.z = 2000
	osd:update()

	update_margins()
end

-- Request that render() is called.
-- The render is then either executed immediately, or rate-limited if it was
-- called a small time ago.
state.render_timer = mp.add_timeout(0, render)
state.render_timer:kill()
function request_render()
	if state.render_timer:is_enabled() then return end
	local timeout = math.max(0, state.render_delay - (mp.get_time() - state.render_last_time))
	state.render_timer.timeout = timeout
	state.render_timer:resume()
end
