local Button = require('elements/Button')

---@alias CycleState {value: any; icon: string; active?: boolean}
---@alias CycleButtonProps {prop: string; states: CycleState[]; anchor_id?: string; tooltip?: string}

---@class CycleButton : Button
local CycleButton = class(Button)

---@param id string
---@param props CycleButtonProps
function CycleButton:new(id, props) return Class.new(self, id, props) --[[@as CycleButton]] end
---@param id string
---@param props CycleButtonProps
function CycleButton:init(id, props)
	local is_state_prop = itable_index_of({'shuffle'}, props.prop)
	self.prop = props.prop
	self.states = props.states

	Button.init(self, id, props)

	self.icon = self.states[1].icon
	self.active = self.states[1].active
	self.current_state_index = 1
	self.on_click = function()
		local new_state = self.states[self.current_state_index + 1] or self.states[1]
		local new_value = new_state.value
		if self.owner then
			mp.commandv('script-message-to', self.owner, 'set', self.prop, new_value)
		elseif is_state_prop then
			if itable_index_of({'yes', 'no'}, new_value) then new_value = new_value == 'yes' end
			set_state(self.prop, new_value)
		else
			mp.set_property(self.prop, new_value)
		end
	end

	local function handle_change(name, value)
		value = type(value) == 'boolean' and (value and 'yes' or 'no') or tostring(value or '')
		local index = itable_find(self.states, function(state) return state.value == value end)
		self.current_state_index = index or 1
		self.icon = self.states[self.current_state_index].icon
		self.active = self.states[self.current_state_index].active
		request_render()
	end

	local prop_parts = split(self.prop, '@')
	if #prop_parts == 2 then -- External prop with a script owner
		self.prop, self.owner = prop_parts[1], prop_parts[2]
		self['on_external_prop_' .. self.prop] = function(_, value) handle_change(self.prop, value) end
		handle_change(self.prop, external[self.prop])
	elseif is_state_prop then -- uosc's state props
		self['on_prop_' .. self.prop] = function(self, value) handle_change(self.prop, value) end
		handle_change(self.prop, state[self.prop])
	else
		self:observe_mp_property(self.prop, 'string', handle_change)
	end
end

return CycleButton
