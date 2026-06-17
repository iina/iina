local cursor = {
	x = math.huge,
	y = math.huge,
	hidden = true,
	hover_raw = false,
	-- Event handlers that are only fired on cursor, bound during render loop. Guidelines:
	-- - element activations (clicks) go to `primary_down` handler
	-- - `primary_up` is only for clearing dragging/swiping, and prevents autohide when bound
	---@type {[string]: {hitbox: Rect|{point: Point, r: number}; handler: fun(...)}[]}
	zone_handlers = {
		primary_down = {},
		primary_up = {},
		secondary_down = {},
		secondary_up = {},
		wheel_down = {},
		wheel_up = {},
		move = {},
	},
	handlers = {
		primary_down = {},
		primary_up = {},
		secondary_down = {},
		secondary_up = {},
		wheel_down = {},
		wheel_up = {},
		move = {},
	},
	first_real_mouse_move_received = false,
	history = CircularBuffer:new(10),
	-- Enables pointer key group captures needed by handlers (called at the end of each render)
	mbtn_left_enabled = nil,
	mbtn_left_dbl_enabled = nil,
	mbtn_right_enabled = nil,
	wheel_enabled = nil,
	autohide_fs_only = nil,
}

cursor.autohide_timer = mp.add_timeout(1, function() cursor:autohide() end)
cursor.autohide_timer:kill()
mp.observe_property('cursor-autohide', 'number', function(_, val)
	cursor.autohide_timer.timeout = (val or 1000) / 1000
end)

-- Called at the beginning of each render
function cursor:clear_zones()
	for _, handlers in pairs(self.zone_handlers) do
		itable_clear(handlers)
	end
end

---@param event string
function cursor:find_zone_handler(event)
	local zone_handlers = self.zone_handlers[event]
	for i = #zone_handlers, 1, -1 do
		local zone_handler = zone_handlers[i]
		local hitbox = zone_handler.hitbox
		if (hitbox.r and get_point_to_point_proximity(self, hitbox.point) <= hitbox.r) or
			(not hitbox.r and get_point_to_rectangle_proximity(self, hitbox) == 0) then
			return zone_handler.handler
		end
	end
end

function cursor:zone(event, hitbox, callback)
	local area_handlers = self.zone_handlers[event]
	area_handlers[#area_handlers + 1] = {hitbox = hitbox, handler = callback}
end

-- Binds a cursor event handler.
---@param event string
---@return fun() disposer Unbinds the event.
function cursor:on(event, callback)
	if self.handlers[event] and not itable_index_of(self.handlers[event], callback) then
		self.handlers[event][#self.handlers[event] + 1] = callback
		self:decide_keybinds()
	end
	return function() self:off(event, callback) end
end

-- Unbinds a cursor event handler.
---@param event string
function cursor:off(event, callback)
	if self.handlers[event] then
		local index = itable_index_of(self.handlers[event], callback)
		if index then
			table.remove(self.handlers[event], index)
			self:decide_keybinds()
		end
	end
end

-- Binds a cursor event handler to be called once.
---@param event string
function cursor:once(event, callback)
	local function callback_wrap()
		callback()
		self:off(event, callback_wrap)
	end
	return self:on(event, callback_wrap)
end

-- Trigger the event.
---@param event string
function cursor:trigger(event, ...)
	local zone_handler = self:find_zone_handler(event)
	local callbacks = self.handlers[event]
	if zone_handler or #callbacks > 0 then
		call_maybe(zone_handler, ...)
		for _, callback in ipairs(callbacks) do callback(...) end
	elseif (event == 'primary_down' or event == 'primary_up') then
		-- forward mbtn_left events if there was no handler
		local active = find_active_keybindings('MBTN_LEFT')
		if active then
			if active.owner then
				-- binding belongs to other script, so make it look like regular key event
				-- mouse bindings are simple, other keys would require repeat and pressed handling
				-- which can't be done with mp.set_key_bindings(), but is possible with mp.add_key_binding()
				local state = event == 'primary_up' and 'um' or 'dm'
				local name = active.cmd:sub(active.cmd:find('/') + 1, -1)
				mp.commandv('script-message-to', active.owner, 'key-binding', name, state, 'MBTN_LEFT')
			elseif event == 'primary_down' then
				-- input.conf binding
				mp.command(active.cmd)
			end
		end
	end
	self:queue_autohide() -- refresh cursor autohide timer
end

---Checks if there are any handlers for the current cursor position
---@param name string
function cursor:has_handler(name)
	return self:find_zone_handler(name) ~= nil or #self.handlers[name] > 0
end

---Checks if there are any handlers at all
---@param name string
function cursor:has_any_handler(name)
	return #self.zone_handlers[name] > 0 or #self.handlers[name] > 0
end

-- Enables or disables keybinding groups based on what event listeners are bound.
function cursor:decide_keybinds()
	local enable_mbtn_left = self:has_any_handler('primary_down') or self:has_any_handler('primary_up')
	local enable_mbtn_left_dbl = self:has_handler('primary_down') or self:has_handler('primary_up')
	local enable_mbtn_right = self:has_handler('secondary_down') or self:has_handler('secondary_up')
	local enable_wheel = self:has_handler('wheel_down') or self:has_handler('wheel_up')
	if enable_mbtn_left ~= self.mbtn_left_enabled then
		local flags = 'allow-vo-dragging+allow-hide-cursor'
		mp[(enable_mbtn_left and 'enable' or 'disable') .. '_key_bindings']('mbtn_left', flags)
		self.mbtn_left_enabled = enable_mbtn_left
	end
	if enable_mbtn_left_dbl ~= self.mbtn_left_dbl_enabled then
		mp[(enable_mbtn_left_dbl and 'enable' or 'disable') .. '_key_bindings']('mbtn_left_dbl')
		self.mbtn_left_dbl_enabled = enable_mbtn_left_dbl
		self:queue_autohide()
	end
	if enable_mbtn_right ~= self.mbtn_right_enabled then
		mp[(enable_mbtn_right and 'enable' or 'disable') .. '_key_bindings']('mbtn_right')
		self.mbtn_right_enabled = enable_mbtn_right
		self:queue_autohide()
	end
	if enable_wheel ~= self.wheel_enabled then
		mp[(enable_wheel and 'enable' or 'disable') .. '_key_bindings']('wheel')
		self.wheel_enabled = enable_wheel
		self:queue_autohide()
	end
end

function cursor:_find_history_sample()
	local time = mp.get_time()
	for _, e in self.history:iter_rev() do
		if time - e.time > 0.1 then
			return e
		end
	end
	return self.history:tail()
end

-- Returns a table with current velocities in in pixels per second.
---@return Point
function cursor:get_velocity()
	local snap = self:_find_history_sample()
	if snap then
		local x, y, time = self.x - snap.x, self.y - snap.y, mp.get_time()
		local time_diff = time - snap.time
		if time_diff > 0.001 then
			return {x = x / time_diff, y = y / time_diff}
		end
	end
	return {x = 0, y = 0}
end

---@param x integer
---@param y integer
function cursor:move(x, y)
	local old_x, old_y = self.x, self.y

	-- mpv reports initial mouse position on linux as (0, 0), which always
	-- displays the top bar, so we hardcode cursor position as infinity until
	-- we receive a first real mouse move event with coordinates other than 0,0.
	if not self.first_real_mouse_move_received then
		if x > 0 and y > 0 then
			self.first_real_mouse_move_received = true
		else
			x, y = math.huge, math.huge
		end
	end

	-- Add 0.5 to be in the middle of the pixel
	self.x, self.y = x + 0.5, y + 0.5

	if old_x ~= self.x or old_y ~= self.y then
		if self.x == math.huge or self.y == math.huge then
			self.hidden = true
			self.history:clear()

			-- Slowly fadeout elements that are currently visible
			for _, id in ipairs(config.cursor_leave_fadeout_elements) do
				local element = Elements[id]
				if element then
					local visibility = element:get_visibility()
					if visibility > 0 then
						element:tween_property('forced_visibility', visibility, 0, function()
							element.forced_visibility = nil
						end)
					end
				end
			end

			Elements:update_proximities()
			Elements:trigger('global_mouse_leave')
		else
			if self.hidden then
				-- Cancel potential fadeouts
				for _, id in ipairs(config.cursor_leave_fadeout_elements) do
					if Elements[id] then Elements[id]:tween_stop() end
				end

				self.hidden = false
				Elements:trigger('global_mouse_enter')
			end

			Elements:update_proximities()
			-- Update history
			self.history:insert({x = self.x, y = self.y, time = mp.get_time()})
		end

		Elements:proximity_trigger('mouse_move')
		self:queue_autohide()
	end

	self:trigger('move')

	request_render()
end

function cursor:leave() self:move(math.huge, math.huge) end

function cursor:is_autohide_allowed()
	return options.autohide and (not self.autohide_fs_only or state.fullscreen) and
		not (self.mbtn_left_dbl_enabled or self.mbtn_right_enabled or self.wheel_enabled) and
		not Menu:is_open()
end
mp.observe_property('cursor-autohide-fs-only', 'bool', function(_, val) cursor.autohide_fs_only = val end)

-- Cursor auto-hiding after period of inactivity.
function cursor:autohide()
	if self:is_autohide_allowed() then
		self:leave()
		self.autohide_timer:kill()
	end
end

function cursor:queue_autohide()
	if self:is_autohide_allowed() then
		self.autohide_timer:kill()
		self.autohide_timer:resume()
	end
end

-- Calculates distance in which cursor reaches rectangle if it continues moving on the same path.
-- Returns `nil` if cursor is not moving towards the rectangle.
---@param rect Rect
function cursor:direction_to_rectangle_distance(rect)
	local prev = self:_find_history_sample()
	if not prev then return false end
	local end_x, end_y = self.x + (self.x - prev.x) * 1e10, self.y + (self.y - prev.y) * 1e10
	return get_ray_to_rectangle_distance(self.x, self.y, end_x, end_y, rect)
end

function cursor:create_handler(event, cb)
	return function(...)
		call_maybe(cb, ...)
		self:trigger(event, ...)
	end
end

-- Movement
function handle_mouse_pos(_, mouse)
	if not mouse then return end
	if cursor.hover_raw and not mouse.hover then
		cursor:leave()
	else
		cursor:move(mouse.x, mouse.y)
	end
	cursor.hover_raw = mouse.hover
end
mp.observe_property('mouse-pos', 'native', handle_mouse_pos)

-- Key binding groups
mp.set_key_bindings({
	{
		'mbtn_left',
		cursor:create_handler('primary_up'),
		cursor:create_handler('primary_down', function(...)
			handle_mouse_pos(nil, mp.get_property_native('mouse-pos'))
		end),
	},
}, 'mbtn_left', 'force')
mp.set_key_bindings({
	{'mbtn_left_dbl', 'ignore'},
}, 'mbtn_left_dbl', 'force')
mp.set_key_bindings({
	{'mbtn_right', cursor:create_handler('secondary_up'), cursor:create_handler('secondary_down')},
}, 'mbtn_right', 'force')
mp.set_key_bindings({
	{'wheel_up', cursor:create_handler('wheel_up')},
	{'wheel_down', cursor:create_handler('wheel_down')},
}, 'wheel', 'force')

return cursor
