---@param data MenuData
---@param opts? {submenu?: string; mouse_nav?: boolean; on_close?: string | string[]}
function open_command_menu(data, opts)
	local function run_command(command)
		if type(command) == 'string' then
			mp.command(command)
		else
			---@diagnostic disable-next-line: deprecated
			mp.commandv(unpack(command))
		end
	end
	---@type MenuOptions
	local menu_opts = {}
	if opts then
		menu_opts.mouse_nav = opts.mouse_nav
		if opts.on_close then menu_opts.on_close = function() run_command(opts.on_close) end end
	end
	local menu = Menu:open(data, run_command, menu_opts)
	if opts and opts.submenu then menu:activate_submenu(opts.submenu) end
	return menu
end

---@param opts? {submenu?: string; mouse_nav?: boolean; on_close?: string | string[]}
function toggle_menu_with_items(opts)
	if Menu:is_open('menu') then
		Menu:close()
	else
		open_command_menu({type = 'menu', items = get_menu_items(), search_submenus = true}, opts)
	end
end

---@param opts {type: string; title: string; list_prop: string; active_prop?: string; serializer: fun(list: any, active: any): MenuDataItem[]; on_select: fun(value: any); on_paste: fun(payload: string); on_move_item?: fun(from_index: integer, to_index: integer, submenu_path: integer[]); on_delete_item?: fun(index: integer, submenu_path: integer[])}
function create_self_updating_menu_opener(opts)
	return function()
		if Menu:is_open(opts.type) then
			Menu:close()
			return
		end
		local list = mp.get_property_native(opts.list_prop)
		local active = opts.active_prop and mp.get_property_native(opts.active_prop) or nil
		local menu

		local function update() menu:update_items(opts.serializer(list, active)) end

		local ignore_initial_list = true
		local function handle_list_prop_change(name, value)
			if ignore_initial_list then
				ignore_initial_list = false
			else
				list = value
				update()
			end
		end

		local ignore_initial_active = true
		local function handle_active_prop_change(name, value)
			if ignore_initial_active then
				ignore_initial_active = false
			else
				active = value
				update()
			end
		end

		local initial_items, selected_index = opts.serializer(list, active)

		-- Items and active_index are set in the handle_prop_change callback, since adding
		-- a property observer triggers its handler immediately, we just let that initialize the items.
		menu = Menu:open(
			{
				type = opts.type,
				title = opts.title,
				items = initial_items,
				selected_index = selected_index,
				on_paste = opts.on_paste,
			},
			opts.on_select, {
				on_open = function()
					mp.observe_property(opts.list_prop, 'native', handle_list_prop_change)
					if opts.active_prop then
						mp.observe_property(opts.active_prop, 'native', handle_active_prop_change)
					end
				end,
				on_close = function()
					mp.unobserve_property(handle_list_prop_change)
					mp.unobserve_property(handle_active_prop_change)
				end,
				on_move_item = opts.on_move_item,
				on_delete_item = opts.on_delete_item,
			})
	end
end

function create_select_tracklist_type_menu_opener(menu_title, track_type, track_prop, load_command, download_command)
	local function serialize_tracklist(tracklist)
		local items = {}

		if download_command then
			items[#items + 1] = {
				title = t('Download'), bold = true, italic = true, hint = t('search online'), value = '{download}',
			}
		end
		if load_command then
			items[#items + 1] = {
				title = t('Load'), bold = true, italic = true, hint = t('open file'), value = '{load}',
			}
		end
		if #items > 0 then
			items[#items].separator = true
		end

		local first_item_index = #items + 1
		local active_index = nil
		local disabled_item = nil

		-- Add option to disable a subtitle track. This works for all tracks,
		-- but why would anyone want to disable audio or video? Better to not
		-- let people mistakenly select what is unwanted 99.999% of the time.
		-- If I'm mistaken and there is an active need for this, feel free to
		-- open an issue.
		if track_type == 'sub' then
			disabled_item = {title = t('Disabled'), italic = true, muted = true, hint = '—', value = nil, active = true}
			items[#items + 1] = disabled_item
		end

		for _, track in ipairs(tracklist) do
			if track.type == track_type then
				local hint_values = {}
				local function h(value) hint_values[#hint_values + 1] = value end

				if track.lang then h(track.lang:upper()) end
				if track['demux-h'] then
					h(track['demux-w'] and (track['demux-w'] .. 'x' .. track['demux-h']) or (track['demux-h'] .. 'p'))
				end
				if track['demux-fps'] then h(string.format('%.5gfps', track['demux-fps'])) end
				h(track.codec)
				if track['audio-channels'] then
					h(track['audio-channels'] == 1
						and t('%s channel', track['audio-channels'])
						or t('%s channels', track['audio-channels']))
				end
				if track['demux-samplerate'] then h(string.format('%.3gkHz', track['demux-samplerate'] / 1000)) end
				if track.forced then h(t('forced')) end
				if track.default then h(t('default')) end
				if track.external then h(t('external')) end

				items[#items + 1] = {
					title = (track.title and track.title or t('Track %s', track.id)),
					hint = table.concat(hint_values, ', '),
					value = track.id,
					active = track.selected,
				}

				if track.selected then
					if disabled_item then disabled_item.active = false end
					active_index = #items
				end
			end
		end

		return items, active_index or first_item_index
	end

	local function handle_select(value)
		if value == '{download}' then
			mp.command(download_command)
		elseif value == '{load}' then
			mp.command(load_command)
		else
			mp.commandv('set', track_prop, value and value or 'no')

			-- If subtitle track was selected, assume the user also wants to see it
			if value and track_type == 'sub' then
				mp.commandv('set', 'sub-visibility', 'yes')
			end
		end
	end

	return create_self_updating_menu_opener({
		title = menu_title,
		type = track_type,
		list_prop = 'track-list',
		serializer = serialize_tracklist,
		on_select = handle_select,
		on_paste = function(path) load_track(track_type, path) end,
	})
end

---@alias NavigationMenuOptions {type: string, title?: string, allowed_types?: string[], active_path?: string, selected_path?: string; on_open?: fun(); on_close?: fun()}

-- Opens a file navigation menu with items inside `directory_path`.
---@param directory_path string
---@param handle_select fun(path: string): nil
---@param opts NavigationMenuOptions
function open_file_navigation_menu(directory_path, handle_select, opts)
	directory = serialize_path(normalize_path(directory_path))
	opts = opts or {}

	if not directory then
		msg.error('Couldn\'t serialize path "' .. directory_path .. '.')
		return
	end

	local files, directories = read_directory(directory.path, {
		types = opts.allowed_types,
		hidden = options.show_hidden_files,
	})
	local is_root = not directory.dirname
	local path_separator = path_separator(directory.path)

	if not files or not directories then return end

	sort_filenames(directories)
	sort_filenames(files)

	-- Pre-populate items with parent directory selector if not at root
	-- Each item value is a serialized path table it points to.
	local items = {}

	if is_root then
		if state.platform == 'windows' then
			items[#items + 1] = {title = '..', hint = t('Drives'), value = '{drives}', separator = true}
		end
	else
		items[#items + 1] = {title = '..', hint = t('parent dir'), value = directory.dirname, separator = true}
	end

	local back_path = items[#items] and items[#items].value
	local selected_index = #items + 1

	for _, dir in ipairs(directories) do
		items[#items + 1] = {title = dir, value = join_path(directory.path, dir), hint = path_separator}
	end

	for _, file in ipairs(files) do
		items[#items + 1] = {title = file, value = join_path(directory.path, file)}
	end

	for index, item in ipairs(items) do
		if not item.value.is_to_parent and opts.active_path == item.value then
			item.active = true
			if not opts.selected_path then selected_index = index end
		end

		if opts.selected_path == item.value then selected_index = index end
	end

	---@type MenuCallback
	local function open_path(path, meta)
		local is_drives = path == '{drives}'
		local is_to_parent = is_drives or #path < #directory_path
		local inheritable_options = {
			type = opts.type, title = opts.title, allowed_types = opts.allowed_types, active_path = opts.active_path,
		}

		if is_drives then
			open_drives_menu(function(drive_path)
				open_file_navigation_menu(drive_path, handle_select, inheritable_options)
			end, {
				type = inheritable_options.type,
				title = inheritable_options.title,
				selected_path = directory.path,
				on_open = opts.on_open,
				on_close = opts.on_close,
			})
			return
		end

		local info, error = utils.file_info(path)

		if not info then
			msg.error('Can\'t retrieve path info for "' .. path .. '". Error: ' .. (error or ''))
			return
		end

		if info.is_dir and not meta.modifiers.alt then
			--  Preselect directory we are coming from
			if is_to_parent then
				inheritable_options.selected_path = directory.path
			end

			open_file_navigation_menu(path, handle_select, inheritable_options)
		else
			handle_select(path)
		end
	end

	local function handle_back()
		if back_path then open_path(back_path, {modifiers = {}}) end
	end

	local menu_data = {
		type = opts.type,
		title = opts.title or directory.basename .. path_separator,
		items = items,
		selected_index = selected_index,
	}
	local menu_options = {on_open = opts.on_open, on_close = opts.on_close, on_back = handle_back}

	return Menu:open(menu_data, open_path, menu_options)
end

-- Opens a file navigation menu with Windows drives as items.
---@param handle_select fun(path: string): nil
---@param opts? NavigationMenuOptions
function open_drives_menu(handle_select, opts)
	opts = opts or {}
	local process = mp.command_native({
		name = 'subprocess',
		capture_stdout = true,
		playback_only = false,
		args = {'wmic', 'logicaldisk', 'get', 'name', '/value'},
	})
	local items, selected_index = {}, 1

	if process.status == 0 then
		for _, value in ipairs(split(process.stdout, '\n')) do
			local drive = string.match(value, 'Name=([A-Z]:)')
			if drive then
				local drive_path = normalize_path(drive)
				items[#items + 1] = {
					title = drive, hint = t('drive'), value = drive_path, active = opts.active_path == drive_path,
				}
				if opts.selected_path == drive_path then selected_index = #items end
			end
		end
	else
		msg.error(process.stderr)
	end

	return Menu:open(
		{type = opts.type, title = opts.title or t('Drives'), items = items, selected_index = selected_index},
		handle_select
	)
end

-- On demand menu items loading
do
	local items = nil
	function get_menu_items()
		if items then return items end

		local input_conf_property = mp.get_property_native('input-conf')
		local input_conf_iterator
		if input_conf_property:sub(1, 9) == 'memory://' then
			-- mpv.net v7
			local input_conf_lines = split(input_conf_property:sub(10), '\n')
			local i = 0
			input_conf_iterator = function()
				i = i + 1
				return input_conf_lines[i]
			end
		else
			local input_conf = input_conf_property == '' and '~~/input.conf' or input_conf_property
			local input_conf_path = mp.command_native({'expand-path', input_conf})
			local input_conf_meta, meta_error = utils.file_info(input_conf_path)

			-- File doesn't exist
			if not input_conf_meta or not input_conf_meta.is_file then
				items = create_default_menu_items()
				return items
			end

			input_conf_iterator = io.lines(input_conf_path)
		end

		local main_menu = {items = {}, items_by_command = {}}
		local by_id = {}

		for line in input_conf_iterator do
			local key, command, comment = string.match(line, '%s*([%S]+)%s+(.-)%s+#%s*(.-)%s*$')
			local title = ''

			if comment then
				local comments = split(comment, '#')
				local titles = itable_filter(comments, function(v, i) return v:match('^!') or v:match('^menu:') end)
				if titles and #titles > 0 then
					title = titles[1]:match('^!%s*(.*)%s*') or titles[1]:match('^menu:%s*(.*)%s*')
				end
			end

			if title ~= '' then
				local is_dummy = key:sub(1, 1) == '#'
				local submenu_id = ''
				local target_menu = main_menu
				local title_parts = split(title or '', ' *> *')

				for index, title_part in ipairs(#title_parts > 0 and title_parts or {''}) do
					if index < #title_parts then
						submenu_id = submenu_id .. title_part

						if not by_id[submenu_id] then
							local items = {}
							by_id[submenu_id] = {items = items, items_by_command = {}}
							target_menu.items[#target_menu.items + 1] = {title = title_part, items = items}
						end

						target_menu = by_id[submenu_id]
					else
						if command == 'ignore' then break end
						-- If command is already in menu, just append the key to it
						if key ~= '#' and command ~= '' and target_menu.items_by_command[command] then
							local hint = target_menu.items_by_command[command].hint
							target_menu.items_by_command[command].hint = hint and hint .. ', ' .. key or key
						else
							-- Separator
							if title_part:sub(1, 3) == '---' then
								local last_item = target_menu.items[#target_menu.items]
								if last_item then last_item.separator = true end
							else
								local item = {
									title = title_part,
									hint = not is_dummy and key or nil,
									value = command,
								}
								if command == '' then
									item.selectable = false
									item.muted = true
									item.italic = true
								else
									target_menu.items_by_command[command] = item
								end
								target_menu.items[#target_menu.items + 1] = item
							end
						end
					end
				end
			end
		end

		items = #main_menu.items > 0 and main_menu.items or create_default_menu_items()
		return items
	end
end

-- Adapted from `stats.lua`
function get_keybinds_items()
	local items = {}
	local active = find_active_keybindings()

	-- Convert to menu items
	for _, bind in pairs(active) do
		items[#items + 1] = {title = bind.cmd, hint = bind.key, value = bind.cmd}
	end

	-- Sort
	table.sort(items, function(a, b) return a.title < b.title end)

	return #items > 0 and items or {
		{
			title = t('%s are empty', '`input-bindings`'),
			selectable = false,
			align = 'center',
			italic = true,
			muted = true,
		},
	}
end

function open_stream_quality_menu()
	if Menu:is_open('stream-quality') then
		Menu:close()
		return
	end

	local ytdl_format = mp.get_property_native('ytdl-format')
	local items = {}

	for _, height in ipairs(config.stream_quality_options) do
		local format = 'bestvideo[height<=?' .. height .. ']+bestaudio/best[height<=?' .. height .. ']'
		items[#items + 1] = {title = height .. 'p', value = format, active = format == ytdl_format}
	end

	Menu:open({type = 'stream-quality', title = t('Stream quality'), items = items}, function(format)
		mp.set_property('ytdl-format', format)

		-- Reload the video to apply new format
		-- This is taken from https://github.com/jgreco/mpv-youtube-quality
		-- which is in turn taken from https://github.com/4e6/mpv-reload/
		local duration = mp.get_property_native('duration')
		local time_pos = mp.get_property('time-pos')

		mp.command('playlist-play-index current')

		-- Tries to determine live stream vs. pre-recorded VOD. VOD has non-zero
		-- duration property. When reloading VOD, to keep the current time position
		-- we should provide offset from the start. Stream doesn't have fixed start.
		-- Decent choice would be to reload stream from it's current 'live' position.
		-- That's the reason we don't pass the offset when reloading streams.
		if duration and duration > 0 then
			local function seeker()
				mp.commandv('seek', time_pos, 'absolute')
				mp.unregister_event(seeker)
			end
			mp.register_event('file-loaded', seeker)
		end
	end)
end

function open_open_file_menu()
	if Menu:is_open('open-file') then
		Menu:close()
		return
	end

	local directory
	local active_file

	if state.path == nil or is_protocol(state.path) then
		local serialized = serialize_path(get_default_directory())
		if serialized then
			directory = serialized.path
			active_file = nil
		end
	else
		local serialized = serialize_path(state.path)
		if serialized then
			directory = serialized.dirname
			active_file = serialized.path
		end
	end

	if not directory then
		msg.error('Couldn\'t serialize path "' .. state.path .. '".')
		return
	end

	-- Update active file in directory navigation menu
	local menu = nil
	local function handle_file_loaded()
		if menu and menu:is_alive() then
			menu:activate_one_value(normalize_path(mp.get_property_native('path')))
		end
	end

	menu = open_file_navigation_menu(
		directory,
		function(path) mp.commandv('loadfile', path) end,
		{
			type = 'open-file',
			allowed_types = config.types.media,
			active_path = active_file,
			on_open = function() mp.register_event('file-loaded', handle_file_loaded) end,
			on_close = function() mp.unregister_event(handle_file_loaded) end,
		}
	)
end

---@param opts {name: 'subtitles'|'audio'|'video'; prop: 'sub'|'audio'|'video'; allowed_types: string[]}
function create_track_loader_menu_opener(opts)
	local menu_type = 'load-' .. opts.name
	local title = ({
		subtitles = t('Load subtitles'),
		audio = t('Load audio'),
		video = t('Load video'),
	})[opts.name]

	return function()
		if Menu:is_open(menu_type) then
			Menu:close()
			return
		end

		local path = state.path
		if path then
			if is_protocol(path) then
				path = false
			else
				local serialized_path = serialize_path(path)
				path = serialized_path ~= nil and serialized_path.dirname or false
			end
		end
		if not path then
			path = get_default_directory()
		end

		local function handle_select(path) load_track(opts.prop, path) end

		open_file_navigation_menu(path, handle_select, {
			type = menu_type, title = title, allowed_types = opts.allowed_types,
		})
	end
end

function open_subtitle_downloader()
	local menu_type = 'download-subtitles'
	---@type Menu
	local menu

	if Menu:is_open(menu_type) then
		Menu:close()
		return
	end

	local search_suggestion, file_path = '', nil
	local destination_directory = mp.command_native({'expand-path', '~~/subtitles'})
	local credentials = {'--api-key', config.open_subtitles_api_key, '--agent', config.open_subtitles_agent}

	if state.path then
		if is_protocol(state.path) then
			if not is_protocol(state.title) then search_suggestion = state.title end
		else
			local serialized_path = serialize_path(state.path)
			if serialized_path then
				search_suggestion = serialized_path.filename
				file_path = state.path
				destination_directory = serialized_path.dirname
			end
		end
	end

	local handle_select, handle_search

	-- Ensures response is valid, and returns its payload, or handles error reporting,
	-- and returns `nil`, indicating the consumer should abort response handling.
	local function ensure_response_data(success, result, error, check)
		local data
		if success and result and result.status == 0 then
			data = utils.parse_json(result.stdout)
			if not data or not check(data) then
				data = (data and data.error == true) and data or {
					error = true,
					message = t('invalid response json (see console for details)'),
					message_verbose = 'invalid response json: ' .. utils.to_string(result.stdout),
				}
			end
		else
			data = {
				error = true,
				message = error or t('process exited with code %s (see console for details)', result.status),
				message_verbose = result.stdout .. result.stderr,
			}
		end

		if data.error then
			local message, message_verbose = data.message or t('unknown error'), data.message_verbose or data.message
			if message_verbose then msg.error(message_verbose) end
			menu:update_items({
				{
					title = message,
					hint = t('error'),
					muted = true,
					italic = true,
					selectable = false,
				},
			})
			return
		end

		return data
	end

	---@param data {kind: 'file', id: number}|{kind: 'page', query: string, page: number}
	handle_select = function(data)
		if data.kind == 'page' then
			handle_search(data.query, data.page)
			return
		end

		menu = Menu:open({
			type = menu_type .. '-result',
			search_style = 'disabled',
			items = {{icon = 'spinner', align = 'center', selectable = false, muted = true}},
		}, function() end)

		local args = itable_join({config.ziggy_path, 'download-subtitles'}, credentials, {
			'--file-id', tostring(data.id),
			'--destination', destination_directory,
		})

		mp.command_native_async({
			name = 'subprocess',
			capture_stderr = true,
			capture_stdout = true,
			playback_only = false,
			args = args,
		}, function(success, result, error)
			if not menu:is_alive() then return end

			local data = ensure_response_data(success, result, error, function(data)
				return type(data.file) == 'string'
			end)

			if not data then return end

			load_track('sub', data.file)

			menu:update_items({
				{
					title = t('Subtitles loaded & enabled'),
					bold = true,
					icon = 'check',
					selectable = false,
				},
				{
					title = t('Remaining downloads today: %s', data.remaining .. '/' .. data.total),
					italic = true,
					muted = true,
					icon = 'file_download',
					selectable = false,
				},
				{
					title = t('Resets in: %s', data.reset_time),
					italic = true,
					muted = true,
					icon = 'schedule',
					selectable = false,
				},
			})
		end)
	end

	---@param query string
	---@param page number|nil
	handle_search = function(query, page)
		if not menu:is_alive() then return end
		page = math.max(1, type(page) == 'number' and round(page) or 1)

		menu:update_items({{icon = 'spinner', align = 'center', selectable = false, muted = true}})

		local args = itable_join({config.ziggy_path, 'search-subtitles'}, credentials)

		local languages = itable_filter(get_languages(), function(lang) return lang:match('.json$') == nil end)
		args[#args + 1] = '--languages'
		args[#args + 1] = table.concat(table_keys(create_set(languages)), ',') -- deduplicates stuff like `en,eng,en`

		args[#args + 1] = '--page'
		args[#args + 1] = tostring(page)

		if file_path then
			args[#args + 1] = '--hash'
			args[#args + 1] = file_path
		end

		if query and #query > 0 then
			args[#args + 1] = '--query'
			args[#args + 1] = query
		end

		mp.command_native_async({
			name = 'subprocess',
			capture_stderr = true,
			capture_stdout = true,
			playback_only = false,
			args = args,
		}, function(success, result, error)
			if not menu:is_alive() then return end

			local data = ensure_response_data(success, result, error, function(data)
				return type(data.data) == 'table' and data.page and data.total_pages
			end)

			if not data then return end

			local subs = itable_filter(data.data, function(sub)
				return sub and sub.attributes and sub.attributes.release and type(sub.attributes.files) == 'table' and
					#sub.attributes.files > 0
			end)
			local items = itable_map(subs, function(sub)
				local hints = {sub.attributes.language}
				if sub.attributes.foreign_parts_only then hints[#hints + 1] = t('foreign parts only') end
				if sub.attributes.hearing_impaired then hints[#hints + 1] = t('hearing impaired') end
				return {
					title = sub.attributes.release,
					hint = table.concat(hints, ', '),
					value = {kind = 'file', id = sub.attributes.files[1].file_id},
					keep_open = true,
				}
			end)

			if #items == 0 then
				items = {
					{title = t('no results'), align = 'center', muted = true, italic = true, selectable = false},
				}
			end

			if data.page > 1 then
				items[#items + 1] = {
					title = t('Previous page'),
					align = 'center',
					bold = true,
					italic = true,
					icon = 'navigate_before',
					keep_open = true,
					value = {kind = 'page', query = query, page = data.page - 1},
				}
			end

			if data.page < data.total_pages then
				items[#items + 1] = {
					title = t('Next page'),
					align = 'center',
					bold = true,
					italic = true,
					icon = 'navigate_next',
					keep_open = true,
					value = {kind = 'page', query = query, page = data.page + 1},
				}
			end

			menu:update_items(items)
		end)
	end

	local initial_items = {
		{title = t('%s to search', 'ctrl+enter'), align = 'center', muted = true, italic = true, selectable = false},
	}

	menu = Menu:open(
		{
			type = menu_type,
			title = t('enter query'),
			items = initial_items,
			palette = true,
			on_search = handle_search,
			search_debounce = 'submit',
			search_suggestion = search_suggestion,
		},
		handle_select
	)
end
