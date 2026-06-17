local Element = require('elements/Element')

---@alias TopBarButtonProps {icon: string; background: string; anchor_id?: string; command: string|fun()}

---@class TopBarButton : Element
local TopBarButton = class(Element)

---@param id string
---@param props TopBarButtonProps
function TopBarButton:new(id, props) return Class.new(self, id, props) --[[@as TopBarButton]] end
function TopBarButton:init(id, props)
	Element.init(self, id, props)
	self.anchor_id = 'top_bar'
	self.icon = props.icon
	self.background = props.background
	self.command = props.command
end

function TopBarButton:handle_cursor_down()
	mp.command(type(self.command) == 'function' and self.command() or self.command)
end

function TopBarButton:render()
	local visibility = self:get_visibility()
	if visibility <= 0 then return end
	local ass = assdraw.ass_new()

	-- Background on hover
	if self.proximity_raw == 0 then
		ass:rect(self.ax, self.ay, self.bx, self.by, {color = self.background, opacity = visibility})
	end
	cursor:zone('primary_down', self, function() self:handle_cursor_down() end)

	local width, height = self.bx - self.ax, self.by - self.ay
	local icon_size = math.min(width, height) * 0.5
	ass:icon(self.ax + width / 2, self.ay + height / 2, icon_size, self.icon, {
		opacity = visibility, border = options.text_border * state.scale,
	})

	return ass
end

--[[ TopBar ]]

---@class TopBar : Element
local TopBar = class(Element)

function TopBar:new() return Class.new(self) --[[@as TopBar]] end
function TopBar:init()
	Element.init(self, 'top_bar', {render_order = 4})
	self.size = 0
	self.icon_size, self.spacing, self.font_size, self.title_bx, self.title_by = 1, 1, 1, 1, 1
	self.show_alt_title = false
	self.main_title, self.alt_title = nil, nil

	local function get_maximized_command()
		if state.platform == 'windows' then
			return state.border
				and (state.fullscreen and 'set fullscreen no;cycle window-maximized' or 'cycle window-maximized')
				or 'set window-maximized no;cycle fullscreen'
		end
		return state.fullormaxed and 'set fullscreen no;set window-maximized no' or 'set window-maximized yes'
	end

	-- Order aligns from right to left
	self.buttons = {
		TopBarButton:new('tb_close', {
			icon = 'close', background = '2311e8', command = 'quit', render_order = self.render_order,
		}),
		TopBarButton:new('tb_max', {
			icon = 'crop_square',
			background = '222222',
			command = get_maximized_command,
			render_order = self.render_order,
		}),
		TopBarButton:new('tb_min', {
			icon = 'minimize',
			background = '222222',
			command = 'cycle window-minimized',
			render_order = self.render_order,
		}),
	}

	self:decide_titles()
end

function TopBar:destroy()
	for _, button in ipairs(self.buttons) do button:destroy() end
	Element.destroy(self)
end

function TopBar:decide_enabled()
	if options.top_bar == 'no-border' then
		self.enabled = not state.border or state.title_bar == false or state.fullscreen
	else
		self.enabled = options.top_bar == 'always'
	end
	self.enabled = self.enabled and (options.top_bar_controls or options.top_bar_title ~= 'no' or state.has_playlist)
	for _, element in ipairs(self.buttons) do
		element.enabled = self.enabled and options.top_bar_controls
	end
end

function TopBar:decide_titles()
	self.alt_title = state.alt_title ~= '' and state.alt_title or nil
	self.main_title = state.title ~= '' and state.title or nil

	if (self.main_title == 'No file') then
		self.main_title = t('No file')
	end

	-- Fall back to alt title if main is empty
	if not self.main_title then
		self.main_title, self.alt_title = self.alt_title, nil
	end

	-- Deduplicate the main and alt titles by checking if one completely
	-- contains the other, and using only the longer one.
	if self.main_title and self.alt_title and not self.show_alt_title then
		local longer_title, shorter_title
		if #self.main_title < #self.alt_title then
			longer_title, shorter_title = self.alt_title, self.main_title
		else
			longer_title, shorter_title = self.main_title, self.alt_title
		end

		local escaped_shorter_title = string.gsub(shorter_title --[[@as string]], '[%(%)%.%+%-%*%?%[%]%^%$%%]', '%%%1')
		if string.match(longer_title --[[@as string]], escaped_shorter_title) then
			self.main_title, self.alt_title = longer_title, nil
		end
	end
end

function TopBar:update_dimensions()
	self.size = round(options.top_bar_size * state.scale)
	self.icon_size = round(self.size * 0.5)
	self.spacing = math.ceil(self.size * 0.25)
	self.font_size = math.floor((self.size - (self.spacing * 2)) * options.font_scale)
	self.button_width = round(self.size * 1.15)
	local window_border_size = Elements:v('window_border', 'size', 0)
	self.ay = window_border_size
	self.bx = display.width - window_border_size
	self.by = self.size + window_border_size
	self.title_bx = self.bx - (options.top_bar_controls and (self.button_width * 3) or 0)
	self.ax = (options.top_bar_title ~= 'no' or state.has_playlist) and window_border_size or self.title_bx

	local button_bx = self.bx
	for _, element in pairs(self.buttons) do
		element.ax, element.bx = button_bx - self.button_width, button_bx
		element.ay, element.by = self.ay, self.by
		button_bx = button_bx - self.button_width
	end
end

function TopBar:toggle_title()
	if options.top_bar_alt_title_place ~= 'toggle' then return end
	self.show_alt_title = not self.show_alt_title
end

function TopBar:on_prop_title() self:decide_titles() end
function TopBar:on_prop_alt_title() self:decide_titles() end

function TopBar:on_prop_border()
	self:decide_enabled()
	self:update_dimensions()
end

function TopBar:on_prop_title_bar()
	self:decide_enabled()
	self:update_dimensions()
end

function TopBar:on_prop_fullscreen()
	self:decide_enabled()
	self:update_dimensions()
end

function TopBar:on_prop_maximized()
	self:decide_enabled()
	self:update_dimensions()
end

function TopBar:on_prop_has_playlist()
	self:decide_enabled()
	self:update_dimensions()
end

function TopBar:on_display() self:update_dimensions() end

function TopBar:on_options()
	self:decide_enabled()
	self:update_dimensions()
end

function TopBar:render()
	local visibility = self:get_visibility()
	if visibility <= 0 then return end
	local ass = assdraw.ass_new()

	-- Window title
	if state.title or state.has_playlist then
		local bg_margin = math.floor((self.size - self.font_size) / 4)
		local padding = self.font_size / 2
		local title_ax = self.ax + bg_margin
		local title_ay = self.ay + bg_margin
		local max_bx = self.title_bx - self.spacing

		-- Playlist position
		if state.has_playlist then
			local text = state.playlist_pos .. '' .. state.playlist_count
			local formatted_text = '{\\b1}' .. state.playlist_pos .. '{\\b0\\fs' .. self.font_size * 0.9 .. '}/'
				.. state.playlist_count
			local opts = {size = self.font_size, wrap = 2, color = fgt, opacity = visibility}
			local rect = {
				ax = title_ax,
				ay = title_ay,
				bx = round(title_ax + text_width(text, opts) + padding * 2),
				by = self.by - bg_margin,
			}
			local opacity = get_point_to_rectangle_proximity(cursor, rect) == 0
				and 1 or config.opacity.playlist_position
			if opacity > 0 then
				ass:rect(rect.ax, rect.ay, rect.bx, rect.by, {
					color = fg, opacity = visibility * opacity, radius = state.radius,
				})
			end
			ass:txt(rect.ax + (rect.bx - rect.ax) / 2, rect.ay + (rect.by - rect.ay) / 2, 5, formatted_text, opts)
			title_ax = rect.bx + bg_margin

			-- Click action
			cursor:zone('primary_down', rect, function() mp.command('script-binding uosc/playlist') end)
		end

		-- Skip rendering titles if there's not enough horizontal space
		if max_bx - title_ax > self.font_size * 3 and options.top_bar_title ~= 'no' then
			-- Main title
			local main_title = self.show_alt_title and self.alt_title or self.main_title
			if main_title then
				local opts = {
					size = self.font_size,
					wrap = 2,
					color = bgt,
					opacity = visibility,
					border = options.text_border * state.scale,
					border_color = bg,
					clip = string.format('\\clip(%d, %d, %d, %d)', self.ax, self.ay, max_bx, self.by),
				}
				local bx = round(math.min(max_bx, title_ax + text_width(main_title, opts) + padding * 2))
				local by = self.by - bg_margin
				local title_rect = {ax = title_ax, ay = title_ay, bx = bx, by = by}

				if options.top_bar_alt_title_place == 'toggle' then
					cursor:zone('primary_down', title_rect, function() self:toggle_title() end)
				end

				ass:rect(title_rect.ax, title_rect.ay, title_rect.bx, title_rect.by, {
					color = bg, opacity = visibility * config.opacity.title, radius = state.radius,
				})
				ass:txt(title_ax + padding, self.ay + (self.size / 2), 4, main_title, opts)
				title_ay = by + 1
			end

			-- Alt title
			if self.alt_title and options.top_bar_alt_title_place == 'below' then
				local font_size = self.font_size * 0.9
				local height = font_size * 1.3
				local by = title_ay + height
				local opts = {
					size = font_size,
					wrap = 2,
					color = bgt,
					border = options.text_border * state.scale,
					border_color = bg,
					opacity = visibility,
				}
				local bx = round(math.min(max_bx, title_ax + text_width(self.alt_title, opts) + padding * 2))
				opts.clip = string.format('\\clip(%d, %d, %d, %d)', title_ax, title_ay, bx, by)
				ass:rect(title_ax, title_ay, bx, by, {
					color = bg, opacity = visibility * config.opacity.title, radius = state.radius,
				})
				ass:txt(title_ax + padding, title_ay + height / 2, 4, self.alt_title, opts)
				title_ay = by + 1
			end

			-- Subtitle: current chapter
			if state.current_chapter then
				local font_size = self.font_size * 0.8
				local height = font_size * 1.3
				local text = '└ ' .. state.current_chapter.index .. ': ' .. state.current_chapter.title
				local opts = {
					size = font_size,
					italic = true,
					wrap = 2,
					color = bgt,
					border = options.text_border * state.scale,
					border_color = bg,
					opacity = visibility * 0.8,
				}
				local rect = {
					ax = title_ax,
					ay = title_ay,
					bx = round(math.min(max_bx, title_ax + text_width(text, opts) + padding * 2)),
					by = title_ay + height,
				}
				opts.clip = string.format('\\clip(%d, %d, %d, %d)', title_ax, title_ay, rect.bx, rect.by)
				ass:rect(rect.ax, rect.ay, rect.bx, rect.by, {
					color = bg, opacity = visibility * config.opacity.title, radius = state.radius,
				})
				ass:txt(rect.ax + padding, rect.ay + height / 2, 4, text, opts)
				title_ay = rect.by + 1

				-- Click action
				cursor:zone('primary_down', rect, function() mp.command('script-binding uosc/chapters') end)
			end
		end
		self.title_by = title_ay - 1
	else
		self.title_by = self.ay
	end

	return ass
end

return TopBar
