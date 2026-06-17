local Element = require('elements/Element')

---@alias Dragging { start_time: number; start_x: number; distance: number; speed_distance: number; start_speed: number; }

---@class Speed : Element
local Speed = class(Element)

---@param props? ElementProps
function Speed:new(props) return Class.new(self, props) --[[@as Speed]] end
function Speed:init(props)
	Element.init(self, 'speed', props)

	self.width = 0
	self.height = 0
	self.notches = 10
	self.notch_every = 0.1
	---@type number
	self.notch_spacing = nil
	---@type number
	self.font_size = nil
	---@type Dragging|nil
	self.dragging = nil
end

function Speed:on_coordinates()
	self.height, self.width = self.by - self.ay, self.bx - self.ax
	self.notch_spacing = self.width / (self.notches + 1)
	self.font_size = round(self.height * 0.48 * options.font_scale)
end
function Speed:on_options() self:on_coordinates() end

function Speed:speed_step(speed, up)
	if options.speed_step_is_factor then
		if up then
			return speed * options.speed_step
		else
			return speed * 1 / options.speed_step
		end
	else
		if up then
			return speed + options.speed_step
		else
			return speed - options.speed_step
		end
	end
end

function Speed:handle_cursor_down()
	self:tween_stop() -- Stop and cleanup possible ongoing animations
	self.dragging = {
		start_time = mp.get_time(),
		start_x = cursor.x,
		distance = 0,
		speed_distance = 0,
		start_speed = state.speed,
	}
end

function Speed:on_global_mouse_move()
	if not self.dragging then return end

	self.dragging.distance = cursor.x - self.dragging.start_x
	self.dragging.speed_distance = (-self.dragging.distance / self.notch_spacing * self.notch_every)

	local speed_current = state.speed
	local speed_drag_current = self.dragging.start_speed + self.dragging.speed_distance
	speed_drag_current = clamp(0.01, speed_drag_current, 100)
	local drag_dir_up = speed_drag_current > speed_current

	local speed_step_next = speed_current
	local speed_drag_diff = math.abs(speed_drag_current - speed_current)
	while math.abs(speed_step_next - speed_current) < speed_drag_diff do
		speed_step_next = self:speed_step(speed_step_next, drag_dir_up)
	end
	local speed_step_prev = self:speed_step(speed_step_next, not drag_dir_up)

	local speed_new = speed_step_prev
	local speed_next_diff = math.abs(speed_drag_current - speed_step_next)
	local speed_prev_diff = math.abs(speed_drag_current - speed_step_prev)
	if speed_next_diff < speed_prev_diff then
		speed_new = speed_step_next
	end

	if speed_new ~= speed_current then
		mp.set_property_native('speed', speed_new)
	end
end

function Speed:handle_cursor_up()
	self.dragging = nil
	request_render()
end

function Speed:on_global_mouse_leave()
	self.dragging = nil
	request_render()
end

function Speed:handle_wheel_up() mp.set_property_native('speed', self:speed_step(state.speed, true)) end
function Speed:handle_wheel_down() mp.set_property_native('speed', self:speed_step(state.speed, false)) end

function Speed:render()
	local visibility = self:get_visibility()
	local opacity = self.dragging and 1 or visibility

	if opacity <= 0 then return end

	cursor:zone('primary_down', self, function()
		self:handle_cursor_down()
		cursor:once('primary_up', function() self:handle_cursor_up() end)
	end)
	cursor:zone('secondary_down', self, function() mp.set_property_native('speed', 1) end)
	cursor:zone('wheel_down', self, function() self:handle_wheel_down() end)
	cursor:zone('wheel_up', self, function() self:handle_wheel_up() end)

	local ass = assdraw.ass_new()

	-- Background
	ass:rect(self.ax, self.ay, self.bx, self.by, {
		color = bg, radius = state.radius, opacity = opacity * config.opacity.speed,
	})

	-- Coordinates
	local ax, ay = self.ax, self.ay
	local bx, by = self.bx, ay + self.height
	local half_width = (self.width / 2)
	local half_x = ax + half_width

	-- Notches
	local speed_at_center = state.speed
	if self.dragging then
		speed_at_center = self.dragging.start_speed + self.dragging.speed_distance
		speed_at_center = clamp(0.01, speed_at_center, 100)
	end
	local nearest_notch_speed = round(speed_at_center / self.notch_every) * self.notch_every
	local nearest_notch_x = half_x + (((nearest_notch_speed - speed_at_center) / self.notch_every) * self.notch_spacing)
	local guide_size = math.floor(self.height / 7.5)
	local notch_by = by - guide_size
	local notch_ay_big = ay + round(self.font_size * 1.1)
	local notch_ay_medium = notch_ay_big + ((notch_by - notch_ay_big) * 0.2)
	local notch_ay_small = notch_ay_big + ((notch_by - notch_ay_big) * 0.4)
	local from_to_index = math.floor(self.notches / 2)

	for i = -from_to_index, from_to_index do
		local notch_speed = nearest_notch_speed + (i * self.notch_every)

		if notch_speed >= 0 and notch_speed <= 100 then
			local notch_x = nearest_notch_x + (i * self.notch_spacing)
			local notch_thickness = 1
			local notch_ay = notch_ay_small
			if (notch_speed % (self.notch_every * 10)) < 0.00000001 then
				notch_ay = notch_ay_big
				notch_thickness = 1.5
			elseif (notch_speed % (self.notch_every * 5)) < 0.00000001 then
				notch_ay = notch_ay_medium
			end

			ass:rect(notch_x - notch_thickness, notch_ay, notch_x + notch_thickness, notch_by, {
				color = fg,
				border = 1,
				border_color = bg,
				opacity = math.min(1.2 - (math.abs((notch_x - ax - half_width) / half_width)), 1) * opacity,
			})
		end
	end

	-- Center guide
	ass:new_event()
	ass:append('{\\rDefault\\an7\\blur0\\bord1\\shad0\\1c&H' .. fg .. '\\3c&H' .. bg .. '}')
	ass:opacity(opacity)
	ass:pos(0, 0)
	ass:draw_start()
	ass:move_to(half_x, by - 2 - guide_size)
	ass:line_to(half_x + guide_size, by - 2)
	ass:line_to(half_x - guide_size, by - 2)
	ass:draw_stop()

	-- Speed value
	local speed_text = (round(state.speed * 100) / 100) .. 'x'
	ass:txt(half_x, ay + (notch_ay_big - ay) / 2, 5, speed_text, {
		size = self.font_size,
		color = bgt,
		border = options.text_border * state.scale,
		border_color = bg,
		opacity = opacity,
	})

	return ass
end

return Speed
