local Element = require('elements/Element')

---@class Curtain : Element
local Curtain = class(Element)

function Curtain:new() return Class.new(self) --[[@as Curtain]] end
function Curtain:init()
	Element.init(self, 'curtain', {render_order = 999})
	self.opacity = 0
	---@type string[]
	self.dependents = {}
end

---@param id string
function Curtain:register(id)
	self.dependents[#self.dependents + 1] = id
	if #self.dependents == 1 then self:tween_property('opacity', self.opacity, 1) end
end

---@param id string
function Curtain:unregister(id)
	self.dependents = itable_filter(self.dependents, function(item) return item ~= id end)
	if #self.dependents == 0 then self:tween_property('opacity', self.opacity, 0) end
end

function Curtain:render()
	if self.opacity == 0 or config.opacity.curtain == 0 then return end
	local ass = assdraw.ass_new()
	ass:rect(0, 0, display.width, display.height, {
		color = config.color.curtain, opacity = config.opacity.curtain * self.opacity,
	})
	return ass
end

return Curtain
