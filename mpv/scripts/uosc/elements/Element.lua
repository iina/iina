---@alias ElementProps {enabled?: boolean; render_order?: number; ax?: number; ay?: number; bx?: number; by?: number; ignores_curtain?: boolean; anchor_id?: string;}

-- Base class all elements inherit from.
---@class Element : Class
local Element = class()

---@param id string
---@param props? ElementProps
function Element:init(id, props)
	self.id = id
	self.render_order = 1
	-- `false` means element won't be rendered, or receive events
	self.enabled = true
	-- Element coordinates
	self.ax, self.ay, self.bx, self.by = 0, 0, 0, 0
	-- Relative proximity from `0` - mouse outside `proximity_max` range, to `1` - mouse within `proximity_min` range.
	self.proximity = 0
	-- Raw proximity in pixels.
	self.proximity_raw = math.huge
	---@type number `0-1` factor to force min visibility. Used for toggling element's permanent visibility.
	self.min_visibility = 0
	---@type number `0-1` factor to force a visibility value. Used for flashing, fading out, and other animations
	self.forced_visibility = nil
	---@type boolean Show this element even when curtain is visible.
	self.ignores_curtain = false
	---@type nil|string ID of an element from which this one should inherit visibility.
	self.anchor_id = nil
	---@type fun()[] Disposer functions called when element is destroyed.
	self._disposers = {}

	if props then table_assign(self, props) end

	-- Flash timer
	self._flash_out_timer = mp.add_timeout(options.flash_duration / 1000, function()
		local function getTo() return self.proximity end
		local function onTweenEnd() self.forced_visibility = nil end
		if self.enabled then
			self:tween_property('forced_visibility', 1, getTo, onTweenEnd)
		else
			onTweenEnd()
		end
	end)
	self._flash_out_timer:kill()

	Elements:add(self)
end

function Element:destroy()
	for _, disposer in ipairs(self._disposers) do disposer() end
	self.destroyed = true
	Elements:remove(self)
end

function Element:reset_proximity() self.proximity, self.proximity_raw = 0, math.huge end

---@param ax number
---@param ay number
---@param bx number
---@param by number
function Element:set_coordinates(ax, ay, bx, by)
	self.ax, self.ay, self.bx, self.by = ax, ay, bx, by
	Elements:update_proximities()
	self:maybe('on_coordinates')
end

function Element:update_proximity()
	if cursor.hidden then
		self:reset_proximity()
	else
		local range = options.proximity_out - options.proximity_in
		self.proximity_raw = get_point_to_rectangle_proximity(cursor, self)
		self.proximity = 1 - (clamp(0, self.proximity_raw - options.proximity_in, range) / range)
	end
end

function Element:is_persistent()
	local persist = config[self.id .. '_persistency']
	return persist and (
		(persist.audio and state.is_audio)
		or (
			persist.paused and state.pause
			and (not Elements.timeline or not Elements.timeline.pressed or Elements.timeline.pressed.pause)
		)
		or (persist.video and state.is_video)
		or (persist.image and state.is_image)
		or (persist.idle and state.is_idle)
		or (persist.windowed and not state.fullormaxed)
		or (persist.fullscreen and state.fullormaxed)
	)
end

-- Decide elements visibility based on proximity and various other factors
function Element:get_visibility()
	-- Hide when curtain is visible, unless this elements ignores it
	local min_order = (Elements.curtain.opacity > 0 and not self.ignores_curtain) and Elements.curtain.render_order or 0
	if self.render_order < min_order then return 0 end

	-- Persistency
	if self:is_persistent() then return 1 end

	-- Forced visibility
	if self.forced_visibility then return math.max(self.forced_visibility, self.min_visibility) end

	-- Anchor inheritance
	-- If anchor returns -1, it means all attached elements should force hide.
	local anchor = self.anchor_id and Elements[self.anchor_id]
	local anchor_visibility = anchor and anchor:get_visibility() or 0

	return anchor_visibility == -1 and 0 or math.max(self.proximity, anchor_visibility, self.min_visibility)
end

-- Call method if it exists
function Element:maybe(name, ...)
	if self[name] then return self[name](self, ...) end
end

-- Attach a tweening animation to this element
---@param from number
---@param to number|fun():number
---@param setter fun(value: number)
---@param duration_or_callback? number|fun() Duration in milliseconds or a callback function.
---@param callback? fun() Called either on animation end, or when animation is killed.
function Element:tween(from, to, setter, duration_or_callback, callback)
	self:tween_stop()
	self._kill_tween = self.enabled and tween(
		from, to, setter, duration_or_callback,
		function()
			self._kill_tween = nil
			if callback then callback() end
		end
	)
end

function Element:is_tweening() return self and self._kill_tween end
function Element:tween_stop() self:maybe('_kill_tween') end

-- Animate an element property between 2 values.
---@param prop string
---@param from number
---@param to number|fun():number
---@param duration_or_callback? number|fun() Duration in milliseconds or a callback function.
---@param callback? fun() Called either on animation end, or when animation is killed.
function Element:tween_property(prop, from, to, duration_or_callback, callback)
	self:tween(from, to, function(value) self[prop] = value end, duration_or_callback, callback)
end

---@param name string
function Element:trigger(name, ...)
	local result = self:maybe('on_' .. name, ...)
	request_render()
	return result
end

-- Briefly flashes the element for `options.flash_duration` milliseconds.
-- Useful to visualize changes of volume and timeline when changed via hotkeys.
function Element:flash()
	if self.enabled and options.flash_duration > 0 and (self.proximity < 1 or self._flash_out_timer:is_enabled()) then
		self:tween_stop()
		self.forced_visibility = 1
		request_render()
		self._flash_out_timer.timeout = options.flash_duration / 1000
		self._flash_out_timer:kill()
		self._flash_out_timer:resume()
	end
end

-- Register disposer to be called when element is destroyed.
---@param disposer fun()
function Element:register_disposer(disposer)
	if not itable_index_of(self._disposers, disposer) then
		self._disposers[#self._disposers + 1] = disposer
	end
end

-- Automatically registers disposer for the passed callback.
---@param event string
---@param callback fun()
function Element:register_mp_event(event, callback)
	mp.register_event(event, callback)
	self:register_disposer(function() mp.unregister_event(callback) end)
end

-- Automatically registers disposer for the observer.
---@param name string
---@param type_or_callback string|fun(name: string, value: any)
---@param callback_maybe nil|fun(name: string, value: any)
function Element:observe_mp_property(name, type_or_callback, callback_maybe)
	local callback = type(type_or_callback) == 'function' and type_or_callback or callback_maybe
	local prop_type = type(type_or_callback) == 'string' and type_or_callback or 'native'
	mp.observe_property(name, prop_type, callback)
	self:register_disposer(function() mp.unobserve_property(callback) end)
end

return Element
