local Elements = {_all = {}}

---@param element Element
function Elements:add(element)
	if not element.id then
		msg.error('attempt to add element without "id" property')
		return
	end

	if self:has(element.id) then Elements:remove(element.id) end

	self._all[#self._all + 1] = element
	self[element.id] = element

	-- Sort by render order
	table.sort(self._all, function(a, b) return a.render_order < b.render_order end)

	request_render()
end

function Elements:remove(idOrElement)
	if not idOrElement then return end
	local id = type(idOrElement) == 'table' and idOrElement.id or idOrElement
	local element = Elements[id]
	if element then
		if not element.destroyed then element:destroy() end
		element.enabled = false
		self._all = itable_delete_value(self._all, self[id])
		self[id] = nil
		request_render()
	end
end

function Elements:update_proximities()
	local curtain_render_order = Elements.curtain.opacity > 0 and Elements.curtain.render_order or 0
	local mouse_leave_elements = {}
	local mouse_enter_elements = {}

	-- Calculates proximities for all elements
	for _, element in self:ipairs() do
		if element.enabled then
			local previous_proximity_raw = element.proximity_raw

			-- If curtain is open, we disable all elements set to rendered below it
			if not element.ignores_curtain and element.render_order < curtain_render_order then
				element:reset_proximity()
			else
				element:update_proximity()
			end

			if element.proximity_raw == 0 then
				-- Mouse entered element area
				if previous_proximity_raw ~= 0 then
					mouse_enter_elements[#mouse_enter_elements + 1] = element
				end
			else
				-- Mouse left element area
				if previous_proximity_raw == 0 then
					mouse_leave_elements[#mouse_leave_elements + 1] = element
				end
			end
		end
	end

	-- Trigger `mouse_leave` and `mouse_enter` events
	for _, element in ipairs(mouse_leave_elements) do element:trigger('mouse_leave') end
	for _, element in ipairs(mouse_enter_elements) do element:trigger('mouse_enter') end
end

-- Toggles passed elements' min visibilities between 0 and 1.
---@param ids string[] IDs of elements to peek.
function Elements:toggle(ids)
	local has_invisible = itable_find(ids, function(id)
		return Elements[id] and Elements[id].enabled and Elements[id]:get_visibility() ~= 1
	end)

	self:set_min_visibility(has_invisible and 1 or 0, ids)

	-- Reset proximities when toggling off. Has to happen after `set_min_visibility`,
	-- as that is using proximity as a tween starting point.
	if not has_invisible then
		for _, id in ipairs(ids) do
			if Elements[id] then Elements[id]:reset_proximity() end
		end
	end
end

-- Set (animate) elements' min visibilities to passed value.
---@param visibility number 0-1 floating point.
---@param ids string[] IDs of elements to peek.
function Elements:set_min_visibility(visibility, ids)
	for _, id in ipairs(ids) do
		local element = Elements[id]
		if element then
			local from = math.max(0, element:get_visibility())
			element:tween_property('min_visibility', from, visibility)
		end
	end
end

-- Flash passed elements.
---@param ids string[] IDs of elements to peek.
function Elements:flash(ids)
	local elements = itable_filter(self._all, function(element) return itable_index_of(ids, element.id) ~= nil end)
	for _, element in ipairs(elements) do element:flash() end
end

---@param name string Event name.
function Elements:trigger(name, ...)
	for _, element in self:ipairs() do element:trigger(name, ...) end
end

-- Trigger two events, `name` and `global_name`, depending on element-cursor proximity.
-- Disabled elements don't receive these events.
---@param name string Event name.
function Elements:proximity_trigger(name, ...)
	for i = #self._all, 1, -1 do
		local element = self._all[i]
		if element.enabled then
			if element.proximity_raw == 0 then
				if element:trigger(name, ...) == 'stop_propagation' then break end
			end
			if element:trigger('global_' .. name, ...) == 'stop_propagation' then break end
		end
	end
end

-- Returns a property of an element with a passed `id` if it exists, with an optional fallback.
---@param id string
---@param prop string
---@param fallback any
function Elements:v(id, prop, fallback)
	if self[id] and self[id].enabled and self[id][prop] ~= nil then return self[id][prop] end
	return fallback
end

-- Calls a method on an element with passed `id` if it exists.
---@param id string
---@param method string
function Elements:maybe(id, method, ...)
	if self[id] then return self[id]:maybe(method, ...) end
end

function Elements:has(id) return self[id] ~= nil end
function Elements:ipairs() return ipairs(self._all) end

return Elements
