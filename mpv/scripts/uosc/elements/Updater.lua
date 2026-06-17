local Element = require('elements/Element')
local dots = {'.', '..', '...'}

local function cleanup_output(output)
	return tostring(output):gsub('%c*\n%c*', '\n'):match('^[%s%c]*(.-)[%s%c]*$')
end

---@class Updater : Element
local Updater = class(Element)

function Updater:new() return Class.new(self) --[[@as Updater]] end
function Updater:init()
	Element.init(self, 'updater', {render_order = 1000})
	self.output = nil
	self.message = t('Updating uosc')
	self.state = 'pending' -- Matches icon name
	local config_dir = mp.command_native({'expand-path', '~~/'})

	Elements:maybe('curtain', 'register', self.id)

	local function handle_result(success, result, error)
		if success and result and result.status == 0 then
			self.state = 'done'
			self.message = t('uosc has been installed. Restart mpv for it to take effect.')
		else
			self.state = 'error'
			self.message = t('An error has occurred.') .. ' ' .. t('See above for clues.')
		end

		local output = (result.stdout or '') .. '\n' .. (error or result.stderr or '')
		if state.platform == 'darwin' then
			output =
				'Self-updater is known not to work on MacOS.\nIf you know about a solution, please make an issue and share it with us!.\n' ..
				output
		end

		self.output = ass_escape(cleanup_output(output))

		request_render()
	end

	local function update(args)
		local env = utils.get_env_list()
		env[#env + 1] = 'MPV_CONFIG_DIR=' .. config_dir

		mp.command_native_async({
			name = 'subprocess',
			capture_stderr = true,
			capture_stdout = true,
			playback_only = false,
			args = args,
			env = env,
		}, handle_result)
	end

	if state.platform == 'windows' then
		local url = 'https://raw.githubusercontent.com/tomasklaen/uosc/HEAD/installers/windows.ps1'
		update({'powershell', '-NoProfile', '-Command', 'irm ' .. url .. ' | iex'})
	else
		-- Detect missing dependencies. We can't just let the process run and
		-- report an error, as on snap packages there's no error. Everything
		-- either exits with 0, or no helpful output/error message.
		local missing = {}

		for _, name in ipairs({'curl', 'unzip'}) do
			local result = mp.command_native({
				name = 'subprocess',
				capture_stdout = true,
				playback_only = false,
				args = {'which', name},
			})
			local path = cleanup_output(result and result.stdout or '')
			if path == '' then
				missing[#missing + 1] = name
			end
		end

		if #missing > 0 then
			local stderr = 'Missing dependencies: ' .. table.concat(missing, ', ')
			if config_dir:match('/snap/') then
				stderr = stderr ..
					'\nThis is a known error for mpv snap packages.\nYou can still update uosc by entering the Linux install command from uosc\'s readme into your terminal, it just can\'t be done this way.\nIf you know about a solution, please make an issue and share it with us!'
			end
			handle_result(false, {stderr = stderr})
		else
			local url = 'https://raw.githubusercontent.com/tomasklaen/uosc/HEAD/installers/unix.sh'
			update({'/bin/bash', '-c', 'source <(curl -fsSL ' .. url .. ')'})
		end
	end
end

function Updater:destroy()
	Elements:maybe('curtain', 'unregister', self.id)
	Element.destroy(self)
end

function Updater:render()
	local ass = assdraw.ass_new()

	local text_size = math.min(20 * state.scale, display.height / 20)
	local icon_size = text_size * 2
	local center_x = round(display.width / 2)

	local color = fg
	if self.state == 'done' then
		color = config.color.success
	elseif self.state == 'error' then
		color = config.color.error
	end

	-- Divider
	local divider_width = round(math.min(500 * state.scale, display.width * 0.8))
	local divider_half, divider_border_half, divider_y = divider_width / 2, round(1 * state.scale), display.height * 0.65
	local divider_ay, divider_by = round(divider_y - divider_border_half), round(divider_y + divider_border_half)
	ass:rect(center_x - divider_half, divider_ay, center_x - icon_size, divider_by, {
		color = color, border = options.text_border * state.scale, border_color = bg, opacity = 0.5,
	})
	ass:rect(center_x + icon_size, divider_ay, center_x + divider_half, divider_by, {
		color = color, border = options.text_border * state.scale, border_color = bg, opacity = 0.5,
	})
	if self.state == 'pending' then
		ass:spinner(center_x, divider_y, icon_size, {
			color = fg, border = options.text_border * state.scale, border_color = bg,
		})
	else
		ass:icon(center_x, divider_y, icon_size * 0.8, self.state, {
			color = color, border = options.text_border * state.scale, border_color = bg,
		})
	end

	-- Output
	local output = self.output or dots[math.ceil((mp.get_time() % 1) * #dots)]
	ass:txt(center_x, divider_y - icon_size, 2, output, {
		size = text_size, color = fg, border = options.text_border * state.scale, border_color = bg,
	})

	-- Message
	ass:txt(center_x, divider_y + icon_size, 5, self.message, {
		size = text_size, bold = true, color = color, border = options.text_border * state.scale, border_color = bg,
	})

	-- Button
	if self.state ~= 'pending' then
		-- Background
		local button_y = divider_y + icon_size * 1.75
		local button_rect = {
			ax = round(center_x - icon_size / 2),
			ay = round(button_y),
			bx = round(center_x + icon_size / 2),
			by = round(button_y + icon_size),
		}
		local is_hovered = get_point_to_rectangle_proximity(cursor, button_rect) == 0
		ass:rect(button_rect.ax, button_rect.ay, button_rect.bx, button_rect.by, {
			color = fg,
			radius = state.radius,
			opacity = is_hovered and 1 or 0.5,
		})

		-- Icon
		local x = round(button_rect.ax + (button_rect.bx - button_rect.ax) / 2)
		local y = round(button_rect.ay + (button_rect.by - button_rect.ay) / 2)
		ass:icon(x, y, icon_size * 0.8, 'close', {color = bg})

		cursor:zone('primary_down', button_rect, function() self:destroy() end)
	end

	return ass
end

return Updater
