local Element = require('elements/Element')

---@class PauseIndicator : Element
local PauseIndicator = class(Element)

function PauseIndicator:new() return Class.new(self) --[[@as PauseIndicator]] end
function PauseIndicator:init()
	Element.init(self, 'pause_indicator', {render_order = 3})
	self.ignores_curtain = true
	self.paused = state.pause
	self.opacity = 0
	self.fadeout = false
	self:init_options()
end

function PauseIndicator:init_options()
	self.base_icon_opacity = options.pause_indicator == 'flash' and 1 or 0.8
	self.type = options.pause_indicator
	self:on_prop_pause()
end

function PauseIndicator:flash()
	-- Can't wait for pause property event listener to set this, because when this is used inside a binding like:
	-- cycle pause; script-binding uosc/flash-pause-indicator
	-- The pause event is not fired fast enough, and indicator starts rendering with old icon.
	self.paused = mp.get_property_native('pause')
	self.fadeout, self.opacity = false, 1
	self:tween_property('opacity', 1, 0, 300)
end

-- Decides whether static indicator should be visible or not.
function PauseIndicator:decide()
	self.paused = mp.get_property_native('pause') -- see flash() for why this line is necessary
	self.fadeout, self.opacity = self.paused, self.paused and 1 or 0
	request_render()

	-- Workaround for an mpv race condition bug during pause on windows builds, which causes osd updates to be ignored.
	-- .03 was still loosing renders, .04 was fine, but to be safe I added 10ms more
	mp.add_timeout(.05, function() osd:update() end)
end

function PauseIndicator:on_prop_pause()
	if Elements:v('timeline', 'pressed') then return end
	if options.pause_indicator == 'flash' then
		if self.paused ~= state.pause then self:flash() end
	elseif options.pause_indicator == 'static' then
		self:decide()
	end
end

function PauseIndicator:on_options()
	self:init_options()
	if self.type == 'flash' then self.opacity = 0 end
end

function PauseIndicator:render()
	if self.opacity == 0 then return end

	local ass = assdraw.ass_new()

	-- Background fadeout
	if self.fadeout then
		ass:rect(0, 0, display.width, display.height, {color = bg, opacity = self.opacity * 0.3})
	end

	-- Icon
	local size = round(math.min(display.width, display.height) * (self.fadeout and 0.20 or 0.15))
	size = size + size * (1 - self.opacity)

	if self.paused then
		ass:icon(display.width / 2, display.height / 2, size, 'pause',
			{border = 1, opacity = self.base_icon_opacity * self.opacity}
		)
	else
		ass:icon(display.width / 2, display.height / 2, size * 1.2, 'play_arrow',
			{border = 1, opacity = self.base_icon_opacity * self.opacity}
		)
	end

	return ass
end

return PauseIndicator
