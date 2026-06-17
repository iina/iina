local Element = require('elements/Element')

---@class Timeline : Element
local Timeline = class(Element)

function Timeline:new() return Class.new(self) --[[@as Timeline]] end
function Timeline:init()
	Element.init(self, 'timeline', {render_order = 5})
	---@type false|{pause: boolean, distance: number, last: {x: number, y: number}}
	self.pressed = false
	self.obstructed = false
	self.size = 0
	self.progress_size = 0
	self.font_size = 0
	self.top_border = 0
	self.line_width = 0
	self.progress_line_width = 0
	self.is_hovered = false
	self.has_thumbnail = false

	self:decide_progress_size()
	self:update_dimensions()

	-- Release any dragging when file gets unloaded
	self:register_mp_event('end-file', function() self.pressed = false end)
end

function Timeline:get_visibility()
	return math.max(Elements:maybe('controls', 'get_visibility') or 0, Element.get_visibility(self))
end

function Timeline:decide_enabled()
	local previous = self.enabled
	self.enabled = not self.obstructed and state.duration ~= nil and state.duration > 0 and state.time ~= nil
	if self.enabled ~= previous then Elements:trigger('timeline_enabled', self.enabled) end
end

function Timeline:get_effective_size()
	if Elements:v('speed', 'dragging') then return self.size end
	return self.progress_size + math.ceil((self.size - self.progress_size) * self:get_visibility())
end

function Timeline:get_is_hovered() return self.enabled and self.is_hovered end

function Timeline:update_dimensions()
	self.size = round(options.timeline_size * state.scale)
	self.top_border = round(options.timeline_border * state.scale)
	self.line_width = round(options.timeline_line_width * state.scale)
	self.progress_line_width = round(options.progress_line_width * state.scale)
	self.font_size = math.floor(math.min((self.size + 60 * state.scale) * 0.2, self.size * 0.96) * options.font_scale)
	local window_border_size = Elements:v('window_border', 'size', 0)
	self.ax = window_border_size
	self.ay = display.height - window_border_size - self.size - self.top_border
	self.bx = display.width - window_border_size
	self.by = display.height - window_border_size
	self.width = self.bx - self.ax
	self.chapter_size = math.max((self.by - self.ay) / 10, 3)
	self.chapter_size_hover = self.chapter_size * 2

	-- Disable if not enough space
	local available_space = display.height - window_border_size * 2 - Elements:v('top_bar', 'size', 0)
	self.obstructed = available_space < self.size + 10
	self:decide_enabled()
end

function Timeline:decide_progress_size()
	local show = options.progress == 'always'
		or (options.progress == 'fullscreen' and state.fullormaxed)
		or (options.progress == 'windowed' and not state.fullormaxed)
	self.progress_size = show and options.progress_size or 0
end

function Timeline:toggle_progress()
	local current = self.progress_size
	self:tween_property('progress_size', current, current > 0 and 0 or options.progress_size)
	request_render()
end

function Timeline:get_time_at_x(x)
	local line_width = (options.timeline_style == 'line' and self.line_width - 1 or 0)
	local time_width = self.width - line_width - 1
	local fax = (time_width) * state.time / state.duration
	local fbx = fax + line_width
	-- time starts 0.5 pixels in
	x = x - self.ax - 0.5
	if x > fbx then
		x = x - line_width
	elseif x > fax then
		x = fax
	end
	local progress = clamp(0, x / time_width, 1)
	return state.duration * progress
end

---@param fast? boolean
function Timeline:set_from_cursor(fast)
	if state.time and state.duration then
		mp.commandv('seek', self:get_time_at_x(cursor.x), fast and 'absolute+keyframes' or 'absolute+exact')
	end
end

function Timeline:clear_thumbnail()
	mp.commandv('script-message-to', 'thumbfast', 'clear')
	self.has_thumbnail = false
end

function Timeline:handle_cursor_down()
	self.pressed = {pause = state.pause, distance = 0, last = {x = cursor.x, y = cursor.y}}
	mp.set_property_native('pause', true)
	self:set_from_cursor()
end
function Timeline:on_prop_duration() self:decide_enabled() end
function Timeline:on_prop_time() self:decide_enabled() end
function Timeline:on_prop_border() self:update_dimensions() end
function Timeline:on_prop_title_bar() self:update_dimensions() end
function Timeline:on_prop_fullormaxed()
	self:decide_progress_size()
	self:update_dimensions()
end
function Timeline:on_display() self:update_dimensions() end
function Timeline:on_options()
	self:decide_progress_size()
	self:update_dimensions()
end
function Timeline:handle_cursor_up()
	if self.pressed then
		mp.set_property_native('pause', self.pressed.pause)
		self.pressed = false
	end
end
function Timeline:on_global_mouse_leave()
	self.pressed = false
end

function Timeline:on_global_mouse_move()
	if self.pressed then
		self.pressed.distance = self.pressed.distance + get_point_to_point_proximity(self.pressed.last, cursor)
		self.pressed.last.x, self.pressed.last.y = cursor.x, cursor.y
		if state.is_video and math.abs(cursor:get_velocity().x) / self.width * state.duration > 30 then
			self:set_from_cursor(true)
		else
			self:set_from_cursor()
		end
	end
end
function Timeline:handle_wheel_up() mp.commandv('seek', options.timeline_step) end
function Timeline:handle_wheel_down() mp.commandv('seek', -options.timeline_step) end

function Timeline:render()
	if self.size == 0 then return end

	local size = self:get_effective_size()
	local visibility = self:get_visibility()
	self.is_hovered = false

	if size < 1 then
		if self.has_thumbnail then self:clear_thumbnail() end
		return
	end

	if self.proximity_raw == 0 then
		self.is_hovered = true
	end
	if visibility > 0 then
		cursor:zone('primary_down', self, function()
			self:handle_cursor_down()
			cursor:once('primary_up', function() self:handle_cursor_up() end)
		end)
		cursor:zone('wheel_down', self, function() self:handle_wheel_down() end)
		cursor:zone('wheel_up', self, function() self:handle_wheel_up() end)
	end

	local ass = assdraw.ass_new()

	-- Text opacity rapidly drops to 0 just before it starts overflowing, or before it reaches self.progress_size
	local hide_text_below = math.max(self.font_size * 0.8, self.progress_size * 2)
	local hide_text_ramp = hide_text_below / 2
	local text_opacity = clamp(0, size - hide_text_below, hide_text_ramp) / hide_text_ramp

	local tooltip_gap = round(2 * state.scale)
	local timestamp_gap = tooltip_gap

	local spacing = math.max(math.floor((self.size - self.font_size) / 2.5), 4)
	local progress = state.time / state.duration
	local is_line = options.timeline_style == 'line'

	-- Foreground & Background bar coordinates
	local bax, bay, bbx, bby = self.ax, self.by - size - self.top_border, self.bx, self.by
	local fax, fay, fbx, fby = 0, bay + self.top_border, 0, bby
	local fcy = fay + (size / 2)

	local line_width = 0

	if is_line then
		local minimized_fraction = 1 - math.min((size - self.progress_size) / ((self.size - self.progress_size) / 8), 1)
		local progress_delta = self.progress_size > 0 and self.progress_line_width - self.line_width or 0
		line_width = self.line_width + (progress_delta * minimized_fraction)
		fax = bax + (self.width - line_width) * progress
		fbx = fax + line_width
		line_width = line_width - 1
	else
		fax, fbx = bax, bax + self.width * progress
	end

	local foreground_size = fby - fay
	local foreground_coordinates = round(fax) .. ',' .. fay .. ',' .. round(fbx) .. ',' .. fby -- for clipping

	-- time starts 0.5 pixels in
	local time_ax = bax + 0.5
	local time_width = self.width - line_width - 1

	-- time to x: calculates x coordinate so that it never lies inside of the line
	local function t2x(time)
		local x = time_ax + time_width * time / state.duration
		return time <= state.time and x or x + line_width
	end

	-- Background
	ass:new_event()
	ass:pos(0, 0)
	ass:append('{\\rDefault\\an7\\blur0\\bord0\\1c&H' .. bg .. '}')
	ass:opacity(config.opacity.timeline)
	ass:draw_start()
	ass:rect_cw(bax, bay, fax, bby) --left of progress
	ass:rect_cw(fbx, bay, bbx, bby) --right of progress
	ass:rect_cw(fax, bay, fbx, fay) --above progress
	ass:draw_stop()

	-- Progress
	ass:rect(fax, fay, fbx, fby, {opacity = config.opacity.position})

	-- Uncached ranges
	local buffered_playtime = nil
	if state.uncached_ranges then
		local opts = {size = 80, anchor_y = fby}
		local texture_char = visibility > 0 and 'b' or 'a'
		local offset = opts.size / (visibility > 0 and 24 or 28)
		for _, range in ipairs(state.uncached_ranges) do
			if not buffered_playtime and (range[1] > state.time or range[2] > state.time) then
				buffered_playtime = (range[1] - state.time) / (state.speed or 1)
			end
			if options.timeline_cache then
				local ax = range[1] < 0.5 and bax or math.floor(t2x(range[1]))
				local bx = range[2] > state.duration - 0.5 and bbx or math.ceil(t2x(range[2]))
				opts.color, opts.opacity, opts.anchor_x = 'ffffff', 0.4 - (0.2 * visibility), bax
				ass:texture(ax, fay, bx, fby, texture_char, opts)
				opts.color, opts.opacity, opts.anchor_x = '000000', 0.6 - (0.2 * visibility), bax + offset
				ass:texture(ax, fay, bx, fby, texture_char, opts)
			end
		end
	end

	-- Custom ranges
	for _, chapter_range in ipairs(state.chapter_ranges) do
		local rax = chapter_range.start < 0.1 and bax or t2x(chapter_range.start)
		local rbx = chapter_range['end'] > state.duration - 0.1 and bbx
			or t2x(math.min(chapter_range['end'], state.duration))
		ass:rect(rax, fay, rbx, fby, {color = chapter_range.color, opacity = chapter_range.opacity})
	end

	-- Chapters
	local hovered_chapter = nil
	if (config.opacity.chapters > 0 and (#state.chapters > 0 or state.ab_loop_a or state.ab_loop_b)) then
		local diamond_radius = math.min(math.max(1, foreground_size * 0.8), self.chapter_size)
		local diamond_radius_hovered = diamond_radius * 2
		local diamond_border = options.timeline_border and math.max(options.timeline_border, 1) or 1

		if diamond_radius > 0 then
			local function draw_chapter(time, radius)
				local chapter_x, chapter_y = t2x(time), fay - 1
				ass:new_event()
				ass:append(string.format(
					'{\\pos(0,0)\\rDefault\\an7\\blur0\\yshad0.01\\bord%f\\1c&H%s\\3c&H%s\\4c&H%s\\1a&H%X&\\3a&H00&\\4a&H00&}',
					diamond_border, fg, bg, bg, opacity_to_alpha(config.opacity.chapters)
				))
				ass:draw_start()
				ass:move_to(chapter_x - radius, chapter_y)
				ass:line_to(chapter_x, chapter_y - radius)
				ass:line_to(chapter_x + radius, chapter_y)
				ass:line_to(chapter_x, chapter_y + radius)
				ass:draw_stop()
			end

			if #state.chapters > 0 then
				-- Find hovered chapter indicator
				local closest_delta = math.huge

				if self.proximity_raw < diamond_radius_hovered then
					for i, chapter in ipairs(state.chapters) do
						local chapter_x, chapter_y = t2x(chapter.time), fay - 1
						local cursor_chapter_delta = math.sqrt((cursor.x - chapter_x) ^ 2 + (cursor.y - chapter_y) ^ 2)
						if cursor_chapter_delta <= diamond_radius_hovered and cursor_chapter_delta < closest_delta then
							hovered_chapter, closest_delta = chapter, cursor_chapter_delta
							self.is_hovered = true
						end
					end
				end

				for i, chapter in ipairs(state.chapters) do
					if chapter ~= hovered_chapter then draw_chapter(chapter.time, diamond_radius) end
					local circle = {point = {x = t2x(chapter.time), y = fay - 1}, r = diamond_radius_hovered}
					if visibility > 0 then
						cursor:zone('primary_down', circle, function()
							mp.commandv('seek', chapter.time, 'absolute+exact')
						end)
					end
				end

				-- Render hovered chapter above others
				if hovered_chapter then
					draw_chapter(hovered_chapter.time, diamond_radius_hovered)
					timestamp_gap = tooltip_gap + round(diamond_radius_hovered)
				else
					timestamp_gap = tooltip_gap + round(diamond_radius)
				end
			end

			-- A-B loop indicators
			local has_a, has_b = state.ab_loop_a and state.ab_loop_a >= 0, state.ab_loop_b and state.ab_loop_b > 0
			local ab_radius = round(math.min(math.max(8, foreground_size * 0.25), foreground_size))

			---@param time number
			---@param kind 'a'|'b'
			local function draw_ab_indicator(time, kind)
				local x = t2x(time)
				ass:new_event()
				ass:append(string.format(
					'{\\pos(0,0)\\rDefault\\an7\\blur0\\yshad0.01\\bord%f\\1c&H%s\\3c&H%s\\4c&H%s\\1a&H%X&\\3a&H00&\\4a&H00&}',
					diamond_border, fg, bg, bg, opacity_to_alpha(config.opacity.chapters)
				))
				ass:draw_start()
				ass:move_to(x, fby - ab_radius)
				if kind == 'b' then ass:line_to(x + 3, fby - ab_radius) end
				ass:line_to(x + (kind == 'a' and 0 or ab_radius), fby)
				ass:line_to(x - (kind == 'b' and 0 or ab_radius), fby)
				if kind == 'a' then ass:line_to(x - 3, fby - ab_radius) end
				ass:draw_stop()
			end

			if has_a then draw_ab_indicator(state.ab_loop_a, 'a') end
			if has_b then draw_ab_indicator(state.ab_loop_b, 'b') end
		end
	end

	local function draw_timeline_timestamp(x, y, align, timestamp, opts)
		opts.color, opts.border_color = fgt, fg
		opts.clip = '\\clip(' .. foreground_coordinates .. ')'
		local func = options.time_precision > 0 and ass.timestamp or ass.txt
		func(ass, x, y, align, timestamp, opts)
		opts.color, opts.border_color = bgt, bg
		opts.clip = '\\iclip(' .. foreground_coordinates .. ')'
		func(ass, x, y, align, timestamp, opts)
	end

	-- Time values
	if text_opacity > 0 then
		local time_opts = {size = self.font_size, opacity = text_opacity, border = 2 * state.scale}
		-- Upcoming cache time
		if buffered_playtime and options.buffered_time_threshold > 0
			and buffered_playtime < options.buffered_time_threshold then
			local margin = 5 * state.scale
			local x, align = fbx + margin, 4
			local cache_opts = {
				size = self.font_size * 0.8, opacity = text_opacity * 0.6, border = options.text_border * state.scale,
			}
			local human = round(math.max(buffered_playtime, 0)) .. 's'
			local width = text_width(human, cache_opts)
			local time_width = timestamp_width(state.time_human, time_opts)
			local time_width_end = timestamp_width(state.destination_time_human, time_opts)
			local min_x, max_x = bax + spacing + margin + time_width, bbx - spacing - margin - time_width_end
			if x < min_x then x = min_x elseif x + width > max_x then x, align = max_x, 6 end
			draw_timeline_timestamp(x, fcy, align, human, cache_opts)
		end

		-- Elapsed time
		if state.time_human then
			draw_timeline_timestamp(bax + spacing, fcy, 4, state.time_human, time_opts)
		end

		-- End time
		if state.destination_time_human then
			draw_timeline_timestamp(bbx - spacing, fcy, 6, state.destination_time_human, time_opts)
		end
	end

	-- Hovered time and chapter
	local rendered_thumbnail = false
	if (self.proximity_raw == 0 or self.pressed or hovered_chapter) and not Elements:v('speed', 'dragging') then
		local cursor_x = hovered_chapter and t2x(hovered_chapter.time) or cursor.x
		local hovered_seconds = hovered_chapter and hovered_chapter.time or self:get_time_at_x(cursor.x)

		-- Cursor line
		-- 0.5 to switch when the pixel is half filled in
		local color = ((fax - 0.5) < cursor_x and cursor_x < (fbx + 0.5)) and bg or fg
		local ax, ay, bx, by = cursor_x - 0.5, fay, cursor_x + 0.5, fby
		ass:rect(ax, ay, bx, by, {color = color, opacity = 0.33})
		local tooltip_anchor = {ax = ax, ay = ay - self.top_border, bx = bx, by = by}

		-- Timestamp
		local opts = {
			size = self.font_size, offset = timestamp_gap, margin = tooltip_gap, timestamp = options.time_precision > 0
		}
		local hovered_time_human = format_time(hovered_seconds, state.duration)
		opts.width_overwrite = timestamp_width(hovered_time_human, opts)
		tooltip_anchor = ass:tooltip(tooltip_anchor, hovered_time_human, opts)

		-- Thumbnail
		if not thumbnail.disabled
			and (not self.pressed or self.pressed.distance < 5)
			and thumbnail.width ~= 0
			and thumbnail.height ~= 0
		then
			local border = math.ceil(math.max(2, state.radius / 2) * state.scale)
			local thumb_x_margin, thumb_y_margin = border + tooltip_gap + bax, border + tooltip_gap
			local thumb_width, thumb_height = thumbnail.width, thumbnail.height
			local thumb_x = round(clamp(
				thumb_x_margin,
				cursor_x - thumb_width / 2,
				display.width - thumb_width - thumb_x_margin
			))
			local thumb_y = round(tooltip_anchor.ay - thumb_y_margin - thumb_height)
			local ax, ay = (thumb_x - border), (thumb_y - border)
			local bx, by = (thumb_x + thumb_width + border), (thumb_y + thumb_height + border)
			ass:rect(ax, ay, bx, by, {
				color = bg,
				border = 1,
				opacity = {main = config.opacity.thumbnail, border = 0.08 * config.opacity.thumbnail},
				border_color = fg,
				radius = state.radius,
			})
			mp.commandv('script-message-to', 'thumbfast', 'thumb', hovered_seconds, thumb_x, thumb_y)
			self.has_thumbnail, rendered_thumbnail = true, true
			tooltip_anchor.ay = ay
		end

		-- Chapter title
		if #state.chapters > 0 then
			local _, chapter = itable_find(state.chapters, function(c) return hovered_seconds >= c.time end,
				#state.chapters, 1)
			if chapter and not chapter.is_end_only then
				ass:tooltip(tooltip_anchor, chapter.title_wrapped, {
					size = self.font_size,
					offset = tooltip_gap,
					responsive = false,
					bold = true,
					width_overwrite = chapter.title_wrapped_width * self.font_size,
					lines = chapter.title_lines,
					margin = tooltip_gap,
				})
			end
		end
	end

	-- Clear thumbnail
	if not rendered_thumbnail and self.has_thumbnail then self:clear_thumbnail() end

	return ass
end

return Timeline
