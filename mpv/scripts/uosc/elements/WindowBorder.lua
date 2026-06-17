local Element = require('elements/Element')

---@class WindowBorder : Element
local WindowBorder = class(Element)

function WindowBorder:new() return Class.new(self) --[[@as WindowBorder]] end
function WindowBorder:init()
	Element.init(self, 'window_border', {render_order = 9999})
	self.size = 0
	self:decide_enabled()
end

function WindowBorder:decide_enabled()
	self.enabled = options.window_border_size > 0 and not state.fullormaxed and not state.border
	self.size = self.enabled and round(options.window_border_size * state.scale) or 0
end

function WindowBorder:on_prop_border() self:decide_enabled() end
function WindowBorder:on_prop_title_bar() self:decide_enabled() end
function WindowBorder:on_prop_fullormaxed() self:decide_enabled() end
function WindowBorder:on_options() self:decide_enabled() end

function WindowBorder:render()
	if self.size > 0 then
		local ass = assdraw.ass_new()
		local clip = '\\iclip(' .. self.size .. ',' .. self.size .. ',' ..
			(display.width - self.size) .. ',' .. (display.height - self.size) .. ')'
		ass:rect(0, 0, display.width + 1, display.height + 1, {
			color = bg, clip = clip, opacity = config.opacity.border,
		})
		return ass
	end
end

return WindowBorder
