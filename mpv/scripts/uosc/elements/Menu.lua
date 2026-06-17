local Element = require('elements/Element')

-- Menu data structure accepted by `Menu:open(menu)`.
---@alias MenuData {id?: string; type?: string; title?: string; hint?: string; search_style?: 'on_demand' | 'palette' | 'disabled'; keep_open?: boolean; bold?: boolean; italic?: boolean; muted?: boolean; separator?: boolean; align?: 'left'|'center'|'right'; items?: MenuDataItem[]; selected_index?: integer; on_search?: string|string[]|fun(search_text: string); on_paste?: string|string[]|fun(search_text: string); search_debounce?: number|string; search_submenus?: boolean; search_suggestion?: string}
---@alias MenuDataItem MenuDataValue|MenuData
---@alias MenuDataValue {title?: string; hint?: string; icon?: string; value: any; active?: boolean; keep_open?: boolean; selectable?: boolean; bold?: boolean; italic?: boolean; muted?: boolean; separator?: boolean; align?: 'left'|'center'|'right'}
---@alias MenuOptions {mouse_nav?: boolean; on_open?: fun(); on_close?: fun(); on_back?: fun(); on_move_item?: fun(from_index: integer, to_index: integer, submenu_path: integer[]); on_delete_item?: fun(index: integer, submenu_path: integer[])}

-- Internal data structure created from `Menu`.
---@alias MenuStack {id?: string; type?: string; title?: string; hint?: string; search_style?: 'on_demand' | 'palette' | 'disabled', selected_index?: number; keep_open?: boolean; bold?: boolean; italic?: boolean; muted?: boolean; separator?: boolean; align?: 'left'|'center'|'right'; items: MenuStackItem[]; on_search?: string|string[]|fun(search_text: string); on_paste?: string|string[]|fun(search_text: string); search_debounce?: number|string; search_submenus?: boolean; search_suggestion?: string; parent_menu?: MenuStack; submenu_path: integer[]; active?: boolean; width: number; height: number; top: number; scroll_y: number; scroll_height: number; title_width: number; hint_width: number; max_width: number; is_root?: boolean; fling?: Fling, search?: Search, ass_safe_title?: string}
---@alias MenuStackItem MenuStackValue|MenuStack
---@alias MenuStackValue {title?: string; hint?: string; icon?: string; value: any; active?: boolean; keep_open?: boolean; selectable?: boolean; bold?: boolean; italic?: boolean; muted?: boolean; separator?: boolean; align?: 'left'|'center'|'right'; title_width: number; hint_width: number}
---@alias Fling {y: number, distance: number, time: number, easing: fun(x: number), duration: number, update_cursor?: boolean}
---@alias Search {query: string; timeout: unknown; min_top: number; max_width: number; source: {width: number; top: number; scroll_y: number; selected_index?: integer; items?: MenuDataItem[]}}

---@alias Modifiers {shift?: boolean, ctrl?: boolean, alt?: boolean}
---@alias MenuCallbackMeta {modifiers: Modifiers}
---@alias MenuCallback fun(value: any, meta: MenuCallbackMeta)

---@class Menu : Element
local Menu = class(Element)

---@param data MenuData
---@param callback MenuCallback
---@param opts? MenuOptions
function Menu:open(data, callback, opts)
	local open_menu = self:is_open()
	if open_menu then
		open_menu.is_being_replaced = true
		open_menu:close(true)
	end
	return Menu:new(data, callback, opts)
end

---@param menu_type? string
---@return Menu|nil
function Menu:is_open(menu_type)
	return Elements.menu and (not menu_type or Elements.menu.type == menu_type) and Elements.menu or nil
end

---@param immediate? boolean Close immediately without fadeout animation.
---@param callback? fun() Called after the animation (if any) ends and element is removed and destroyed.
---@overload fun(callback: fun())
function Menu:close(immediate, callback)
	if type(immediate) ~= 'boolean' then callback = immediate end

	local menu = self == Menu and Elements.menu or self

	if menu and not menu.destroyed then
		if menu.is_closing then
			menu:tween_stop()
			return
		end

		local function close()
			Elements:remove('menu')
			menu.is_closing, menu.stack, menu.current, menu.all, menu.by_id = false, nil, nil, {}, {}
			menu:disable_key_bindings()
			Elements:update_proximities()
			cursor:queue_autohide()
			if callback then callback() end
			request_render()
		end

		menu.is_closing = true

		if immediate then
			close()
		else
			menu:fadeout(close)
		end
	end
end

---@param data MenuData
---@param callback MenuCallback
---@param opts? MenuOptions
---@return Menu
function Menu:new(data, callback, opts) return Class.new(self, data, callback, opts) --[[@as Menu]] end
---@param data MenuData
---@param callback MenuCallback
---@param opts? MenuOptions
function Menu:init(data, callback, opts)
	Element.init(self, 'menu', {render_order = 1001})

	-----@type fun()
	self.callback = callback
	self.opts = opts or {}
	self.offset_x = 0 -- Used for submenu transition animation.
	self.mouse_nav = self.opts.mouse_nav -- Stops pre-selecting items
	---@type Modifiers
	self.modifiers = {}
	self.item_height = nil
	self.min_width = nil
	self.item_spacing = 1
	self.item_padding = nil
	self.separator_size = nil
	self.padding = nil
	self.gap = nil
	self.font_size = nil
	self.font_size_hint = nil
	self.scroll_step = nil -- Item height + item spacing.
	self.scroll_height = nil -- Items + spacings - container height.
	self.opacity = 0 -- Used to fade in/out.
	self.type = data.type
	---@type MenuStack Root MenuStack.
	self.root = nil
	---@type MenuStack Current MenuStack.
	self.current = nil
	---@type MenuStack[] All menus in a flat array.
	self.all = nil
	---@type table<string, MenuStack> Map of submenus by their ids, such as `'Tools > Aspect ratio'`.
	self.by_id = {}
	self.key_bindings = {}
	self.key_bindings_search = {} -- temporary key bindings for search
	self.type_to_search = options.menu_type_to_search
	self.is_being_replaced = false
	self.is_closing, self.is_closed = false, false
	self.drag_last_y = nil
	self.is_dragging = false

	if utils.shared_script_property_set then
		utils.shared_script_property_set('uosc-menu-type', self.type or 'undefined')
	end
	mp.set_property_native('user-data/uosc/menu/type', self.type or 'undefined')
	self:update(data)

	for _, menu in ipairs(self.all) do self:scroll_to_index(menu.selected_index, menu) end
	if self.mouse_nav then self.current.selected_index = nil end

	self:tween_property('opacity', 0, 1)
	self:enable_key_bindings()
	Elements:maybe('curtain', 'register', self.id)
	if self.opts.on_open then self.opts.on_open() end
end

function Menu:destroy()
	Element.destroy(self)
	self:disable_key_bindings()
	self.is_closed = true
	if not self.is_being_replaced then Elements:maybe('curtain', 'unregister', self.id) end
	if utils.shared_script_property_set then
		utils.shared_script_property_set('uosc-menu-type', nil)
	end
	mp.set_property_native('user-data/uosc/menu/type', nil)
	if self.opts.on_close then self.opts.on_close() end
end

---@param data MenuData
function Menu:update(data)
	local new_root = {is_root = true, submenu_path = {}}
	local new_all = {}
	local new_menus = {} -- menus that didn't exist before this `update()`
	local new_by_id = {}
	local menus_to_serialize = {{new_root, data}}
	local old_current_id = self.current and self.current.id
	local menu_props_to_copy = {
		'title', 'hint', 'keep_open', 'search_style', 'search_submenus', 'search_suggestion', 'on_search', 'on_paste',
	}
	local item_props_to_copy = itable_join(menu_props_to_copy, {
		'icon', 'active', 'bold', 'italic', 'muted', 'value', 'separator', 'selectable', 'align',
	})

	table_assign_props(new_root, data, itable_join({'type'}, menu_props_to_copy))

	local i = 0
	while i < #menus_to_serialize do
		i = i + 1
		local menu, menu_data = menus_to_serialize[i][1], menus_to_serialize[i][2]
		local parent_id = menu.parent_menu and not menu.parent_menu.is_root and menu.parent_menu.id
		if menu_data.id then
			menu.id = menu_data.id
		elseif not menu.is_root then
			menu.id = (parent_id and parent_id .. ' > ' or '') .. (menu_data.title or i)
		else
			menu.id = 'main'
		end
		menu.icon = 'chevron_right'

		-- Normalize `search_debounce`
		if type(menu_data.search_debounce) == 'number' then
			menu.search_debounce = math.max(0, menu_data.search_debounce)
		elseif menu_data.search_debounce == 'submit' then
			menu.search_debounce = 'submit'
		else
			menu.search_debounce = menu.on_search and 300 or 0
		end

		-- Update items
		local first_active_index = nil
		menu.items = {
			{title = t('Empty'), value = 'ignore', italic = 'true', muted = 'true', selectable = false, align = 'center'},
		}

		for i, item_data in ipairs(menu_data.items or {}) do
			if item_data.active and not first_active_index then first_active_index = i end

			local item = {}
			table_assign_props(item, item_data, item_props_to_copy)
			if item.keep_open == nil then item.keep_open = menu.keep_open end

			-- Submenu
			if item_data.items then
				item.parent_menu = menu
				item.submenu_path = itable_join(menu.submenu_path, {i})
				menus_to_serialize[#menus_to_serialize + 1] = {item, item_data}
			end

			menu.items[i] = item
		end

		if menu.is_root then menu.selected_index = menu_data.selected_index or first_active_index end

		-- Retain old state
		local old_menu = self.by_id[menu.id]
		if old_menu then
			table_assign_props(menu, old_menu, {'selected_index', 'scroll_y', 'fling', 'search'})
		else
			new_menus[#new_menus + 1] = menu
		end

		new_all[#new_all + 1] = menu
		new_by_id[menu.id] = menu
	end

	self.root, self.all, self.by_id = new_root, new_all, new_by_id
	self.current = self.by_id[old_current_id] or self.root

	self:update_content_dimensions()
	self:reset_navigation()

	-- Ensure palette menus have active searches, and clean empty searches from menus that lost the `palette` flag
	local update_dimensions_again = false
	for _, menu in ipairs(self.all) do
		local is_palette = menu.search_style == 'palette'
		if not menu.search and (is_palette or (menu.search_suggestion and itable_index_of(new_menus, menu))) then
			update_dimensions_again = true
			self:search_init(menu)
		elseif not is_palette and menu.search and menu.search.query == '' then
			update_dimensions_again = true
			menu.search = nil
		end
	end
	-- We update before _and_ after because search_inits need the initial un-searched
	-- menu's position and scroll state to save on the `search.source` table.
	if update_dimensions_again then
		self:update_content_dimensions()
		self:reset_navigation()
	end
	-- Apply search suggestions
	for _, menu in ipairs(new_menus) do
		if menu.search_suggestion then menu.search.query = menu.search_suggestion end
	end
	for _, menu in ipairs(self.all) do
		if menu.search then
			-- the menu items are new objects and the search needs to contain those
			menu.search.source.items = not menu.on_search and menu.items or nil
			-- Only internal searches are immediately submitted
			if not menu.on_search then self:search_internal(menu, true) end
		end

		if menu.selected_index then self:select_by_offset(0, menu) end
	end

	self:search_ensure_key_bindings()
end

---@param items MenuDataItem[]
function Menu:update_items(items)
	local data = table_assign({}, self.root)
	data.items = items
	self:update(data)
end

function Menu:update_content_dimensions()
	self.item_height = round(options.menu_item_height * state.scale)
	self.min_width = round(options.menu_min_width * state.scale)
	self.separator_size = round(1 * state.scale)
	self.scrollbar_size = round(2 * state.scale)
	self.padding = round(options.menu_padding * state.scale)
	self.gap = round(2 * state.scale)
	self.font_size = round(self.item_height * 0.48 * options.font_scale)
	self.font_size_hint = self.font_size - 1
	self.item_padding = round((self.item_height - self.font_size) * 0.6)
	self.scroll_step = self.item_height + self.item_spacing

	local title_opts = {size = self.font_size, italic = false, bold = false}
	local hint_opts = {size = self.font_size_hint}

	for _, menu in ipairs(self.all) do
		title_opts.bold, title_opts.italic = true, false
		local max_width = text_width(menu.title, title_opts) + 2 * self.padding + 2 * self.item_padding

		-- Estimate width of a widest item
		for _, item in ipairs(menu.items) do
			local icon_width = item.icon and self.font_size or 0
			item.title_width = text_width(item.title, title_opts)
			item.hint_width = text_width(item.hint, hint_opts)
			local spacings_in_item = 1 + (item.title_width > 0 and 1 or 0)
				+ (item.hint_width > 0 and 1 or 0) + (icon_width > 0 and 1 or 0)
			local estimated_width = item.title_width + item.hint_width + icon_width
				+ (self.item_padding * spacings_in_item)
			if estimated_width > max_width then max_width = estimated_width end
		end

		menu.max_width = max_width + 2 * self.padding
	end

	self:update_dimensions()
end

function Menu:update_dimensions()
	-- Coordinates and sizes are of the scrollable area. Title is rendered
	-- above it, so we need to account for that in max_height and ay position.
	-- This is a debt from an era where we had different cursor event handling,
	-- and dumb titles with no search inputs. It could use a refactor.
	local margin = round(self.item_height / 2)
	local width_available, height_available = display.width - margin * 2, display.height - margin * 2
	local min_width = math.min(self.min_width, width_available)

	for _, menu in ipairs(self.all) do
		local width = math.max(menu.search and menu.search.max_width or 0, menu.max_width)
		menu.width = round(clamp(min_width, width, width_available))
		local title_height = (menu.is_root and menu.title or menu.search) and self.scroll_step + self.padding or 0
		local max_height = height_available - title_height
		local content_height = self.scroll_step * #menu.items
		menu.height = math.min(content_height - self.item_spacing, max_height)
		menu.top = clamp(
			title_height + margin,
			menu.search and math.min(menu.search.min_top, menu.search.source.top) or height_available,
			round((height_available - menu.height + title_height) / 2)
		)
		if menu.search then
			menu.search.min_top = math.min(menu.search.min_top, menu.top)
			menu.search.max_width = math.max(menu.search.max_width, menu.width)
		end
		menu.scroll_height = math.max(content_height - menu.height - self.item_spacing, 0)
		self:set_scroll_to(menu.scroll_y, menu) -- clamps scroll_y to scroll limits
	end

	self:update_coordinates()
end

-- Updates element coordinates to match currently open (sub)menu.
function Menu:update_coordinates()
	local ax = round((display.width - self.current.width) / 2) + self.offset_x
	self:set_coordinates(ax, self.current.top, ax + self.current.width, self.current.top + self.current.height)
end

function Menu:reset_navigation()
	local menu = self.current

	-- Reset indexes and scroll
	self:set_scroll_to(menu.scroll_y) -- clamps scroll_y to scroll limits
	if menu.items and #menu.items > 0 then
		-- Normalize existing selected_index always, and force it only in keyboard navigation
		if not self.mouse_nav then
			self:select_by_offset(0)
		end
	else
		self:select_index(nil)
	end

	-- Walk up the parent menu chain and activate items that lead to current menu
	local parent = menu.parent_menu
	while parent do
		parent.selected_index = itable_index_of(parent.items, menu)
		menu, parent = parent, parent.parent_menu
	end

	request_render()
end

function Menu:set_offset_x(offset)
	local delta = offset - self.offset_x
	self.offset_x = offset
	self:set_coordinates(self.ax + delta, self.ay, self.bx + delta, self.by)
end

function Menu:fadeout(callback) self:tween_property('opacity', 1, 0, callback) end

function Menu:get_first_active_index(menu)
	menu = menu or self.current
	for index, item in ipairs(self.current.items) do
		if item.active then return index end
	end
end

---@param pos? number
---@param menu? MenuStack
function Menu:set_scroll_to(pos, menu)
	menu = menu or self.current
	menu.scroll_y = clamp(0, pos or 0, menu.scroll_height)
	request_render()
end

---@param delta? number
---@param menu? MenuStack
function Menu:set_scroll_by(delta, menu)
	menu = menu or self.current
	self:set_scroll_to(menu.scroll_y + delta, menu)
end

---@param pos? number
---@param menu? MenuStack
---@param fling_options? table
function Menu:scroll_to(pos, menu, fling_options)
	menu = menu or self.current
	menu.fling = {
		y = menu.scroll_y,
		distance = clamp(-menu.scroll_y, pos - menu.scroll_y, menu.scroll_height - menu.scroll_y),
		time = mp.get_time(),
		duration = 0.1,
		easing = ease_out_sext,
	}
	if fling_options then table_assign(menu.fling, fling_options) end
	request_render()
end

---@param delta? number
---@param menu? MenuStack
---@param fling_options? Fling
function Menu:scroll_by(delta, menu, fling_options)
	menu = menu or self.current
	self:scroll_to((menu.fling and (menu.fling.y + menu.fling.distance) or menu.scroll_y) + delta, menu, fling_options)
end

---@param index? integer
---@param menu? MenuStack
---@param immediate? boolean
function Menu:scroll_to_index(index, menu, immediate)
	menu = menu or self.current
	if (index and index >= 1 and index <= #menu.items) then
		local position = round((self.scroll_step * (index - 1)) - ((menu.height - self.scroll_step) / 2))
		if immediate then
			self:set_scroll_to(position, menu)
		else
			self:scroll_to(position, menu)
		end
	end
end

---@param index? integer
---@param menu? MenuStack
function Menu:select_index(index, menu)
	menu = menu or self.current
	menu.selected_index = (index and index >= 1 and index <= #menu.items) and index or nil
	request_render()
end

---@param value? any
---@param menu? MenuStack
function Menu:select_value(value, menu)
	menu = menu or self.current
	local index = itable_find(menu.items, function(item) return item.value == value end)
	self:select_index(index)
end

---@param menu? MenuStack
function Menu:deactivate_items(menu)
	menu = menu or self.current
	for _, item in ipairs(menu.items) do item.active = false end
	request_render()
end

---@param index? integer
---@param menu? MenuStack
function Menu:activate_index(index, menu)
	menu = menu or self.current
	if index and index >= 1 and index <= #menu.items then menu.items[index].active = true end
	request_render()
end

---@param index? integer
---@param menu? MenuStack
function Menu:activate_one_index(index, menu)
	self:deactivate_items(menu)
	self:activate_index(index, menu)
end

---@param value? any
---@param menu? MenuStack
function Menu:activate_value(value, menu)
	menu = menu or self.current
	local index = itable_find(menu.items, function(item) return item.value == value end)
	self:activate_index(index, menu)
end

---@param value? any
---@param menu? MenuStack
function Menu:activate_one_value(value, menu)
	menu = menu or self.current
	local index = itable_find(menu.items, function(item) return item.value == value end)
	self:activate_one_index(index, menu)
end

---@param menu MenuStack One of menus in `self.all`.
function Menu:activate_menu(menu)
	if itable_index_of(self.all, menu) then
		self.current = menu
		self:update_coordinates()
		self:reset_navigation()
		self:search_ensure_key_bindings()
		request_render()
	else
		msg.error('Attempt to open a menu not in `self.all` list.')
	end
end

---@param id string
function Menu:activate_submenu(id)
	local submenu = self.by_id[id]
	if submenu then
		self:activate_menu(submenu)
		local menu = self.current
		local parent = menu.parent_menu
		while parent do
			parent.selected_index = itable_index_of(parent.items, menu)
			self:scroll_to_index(parent.selected_index, parent)
			menu, parent = parent, parent.parent_menu
		end
	else
		msg.error(string.format('Requested submenu id "%s" doesn\'t exist', id))
	end
end

---@param index? integer
---@param menu? MenuStack
function Menu:delete_index(index, menu)
	menu = menu or self.current
	if (index and index >= 1 and index <= #menu.items) then
		table.remove(menu.items, index)
		self:update_content_dimensions()
		self:scroll_to_index(menu.selected_index, menu)
	end
end

---@param value? any
---@param menu? MenuStack
function Menu:delete_value(value, menu)
	menu = menu or self.current
	local index = itable_find(menu.items, function(item) return item.value == value end)
	self:delete_index(index)
end

---@param menu MenuStack One of menus in `self.all`.
---@param x number `x` coordinate to slide from.
function Menu:slide_in_menu(menu, x)
	local current = self.current
	current.selected_index = nil
	self:activate_menu(menu)
	self:tween(-(display.width / 2 - menu.width / 2 - x), 0, function(offset) self:set_offset_x(offset) end)
	self.opacity = 1 -- in case tween above canceled fade in animation
end

function Menu:back()
	if self.opts.on_back then
		self.opts.on_back()
		if self.is_closed then return end
	end

	local current = self.current
	local parent = current.parent_menu

	if parent then
		self:slide_in_menu(parent, display.width / 2 - current.width / 2 - parent.width / 2 + self.offset_x)
	else
		self:close()
	end
end

---@param opts? {keep_open?: boolean, preselect_first_item?: boolean}
function Menu:open_selected_item(opts)
	opts = opts or {}
	local menu = self.current
	if menu.selected_index then
		local item = menu.items[menu.selected_index]
		-- Is submenu
		if item.items then
			if opts.preselect_first_item then
				item.selected_index = #item.items > 0 and 1 or nil
			end
			self:activate_menu(item)
			self:tween(self.offset_x + menu.width / 2, 0, function(offset) self:set_offset_x(offset) end)
			self.opacity = 1 -- in case tween above canceled fade in animation
		else
			self.callback(item.value, {modifiers = self.modifiers or {}})
			if not item.keep_open and not opts.keep_open then self:close() end
		end
	end
end

function Menu:open_selected_item_soft() self:open_selected_item({keep_open = true}) end
function Menu:open_selected_item_preselect() self:open_selected_item({preselect_first_item = true}) end

---@param index integer
function Menu:move_selected_item_to(index)
	local from, callback = self.current.selected_index, self.opts.on_move_item
	if callback and from and from ~= index and index >= 1 and index <= #self.current.items then
		callback(from, index, self.current.submenu_path)
		self.current.selected_index = index
		self:scroll_to_index(index, self.current, true)
	end
end

function Menu:move_selected_item_up()
	if self.current.selected_index then self:move_selected_item_to(self.current.selected_index - 1) end
end

function Menu:move_selected_item_down()
	if self.current.selected_index then self:move_selected_item_to(self.current.selected_index + 1) end
end

function Menu:delete_selected_item()
	local index, callback = self.current.selected_index, self.opts.on_delete_item
	if callback and index then callback(index, self.current.submenu_path) end
end

function Menu:on_display() self:update_dimensions() end
function Menu:on_prop_fullormaxed() self:update_content_dimensions() end
function Menu:on_options() self:update_content_dimensions() end

function Menu:handle_cursor_down()
	if self.proximity_raw == 0 then
		self.drag_last_y = cursor.y
		self.current.fling = nil
	else
		self:close()
	end
end

function Menu:handle_cursor_up()
	if self.proximity_raw == 0 and self.drag_last_y and not self.is_dragging then
		self:open_selected_item({preselect_first_item = false, keep_open = self.modifiers and self.modifiers.shift})
	end
	if self.is_dragging then
		local distance = cursor:get_velocity().y / -3
		if math.abs(distance) > 50 then
			self.current.fling = {
				y = self.current.scroll_y,
				distance = distance,
				time = cursor.history:head().time,
				easing = ease_out_quart,
				duration = 0.5,
				update_cursor = true,
			}
			request_render()
		end
	end
	self.is_dragging = false
	self.drag_last_y = nil
end

function Menu:on_global_mouse_move()
	self.mouse_nav = true
	if self.drag_last_y then
		self.is_dragging = self.is_dragging or math.abs(cursor.y - self.drag_last_y) >= 10
		local distance = self.drag_last_y - cursor.y
		if distance ~= 0 then self:set_scroll_by(distance) end
		if self.is_dragging then self.drag_last_y = cursor.y end
	end
	request_render()
end

function Menu:handle_wheel_up() self:scroll_by(self.scroll_step * -3, nil, {update_cursor = true}) end
function Menu:handle_wheel_down() self:scroll_by(self.scroll_step * 3, nil, {update_cursor = true}) end

---@param offset integer
---@param menu? MenuStack
function Menu:select_by_offset(offset, menu)
	menu = menu or self.current
	local index = clamp(1, (menu.selected_index or offset >= 0 and 0 or #menu.items + 1) + offset, #menu.items)
	local prev_index = itable_find(menu.items, function(item) return item.selectable ~= false end, index, 1)
	local next_index = itable_find(menu.items, function(item) return item.selectable ~= false end, index)
	if prev_index and next_index then
		if offset == 0 then
			menu.selected_index = index - prev_index <= next_index - index and prev_index or next_index
		elseif offset > 0 then
			menu.selected_index = next_index
		else
			menu.selected_index = prev_index
		end
	else
		menu.selected_index = prev_index or next_index or nil
	end
	request_render()
end

---@param offset integer
---@param immediate? boolean
function Menu:navigate_by_offset(offset, immediate)
	self:select_by_offset(offset)
	if self.current.selected_index then self:scroll_to_index(self.current.selected_index, self.current, immediate) end
end

function Menu:prev()
	self:navigate_by_offset(-1, true)
end

function Menu:next()
	self:navigate_by_offset(1, true)
end

function Menu:on_pgup()
	local items_per_page = round((self.current.height / self.scroll_step) * 0.4)
	self:navigate_by_offset(-items_per_page)
end

function Menu:on_pgdwn()
	local items_per_page = round((self.current.height / self.scroll_step) * 0.4)
	self:navigate_by_offset(items_per_page)
end

function Menu:on_home()
	self:navigate_by_offset(-math.huge)
end

function Menu:on_end()
	self:navigate_by_offset(math.huge)
end

function Menu:paste()
	local menu = self.current
	local payload = get_clipboard()
	if not payload then return end
	if menu.search then
		self:search_query_update(menu.search.query .. payload)
	elseif menu.on_paste then
		local paste_type = type(menu.on_paste)
		if paste_type == 'string' then
			mp.command(menu.on_paste .. ' ' .. payload)
		elseif paste_type == 'table' then
			local command = itable_join({}, menu.on_paste)
			command[#command + 1] = payload
			mp.command_native(command)
		else
			menu.on_paste(payload)
		end
	elseif menu.search_style ~= 'disabled' then
		self:search_start(menu)
		self:search_query_update(payload, menu)
	end
end

---@param menu MenuStack
---@param no_select_first? boolean
function Menu:search_internal(menu, no_select_first)
	local query = menu.search.query:lower()
	if query == '' then
		-- Reset menu state to what it was before search
		for key, value in pairs(menu.search.source) do menu[key] = value end
	else
		-- Inherit `search_submenus` from parent menus
		local search_submenus, parent_menu = menu.search_submenus, menu.parent_menu
		while not search_submenus and parent_menu do
			search_submenus, parent_menu = parent_menu.search_submenus, parent_menu.parent_menu
		end
		menu.items = search_items(menu.search.source.items, query, search_submenus)
		-- Select 1st item in search results
		menu.scroll_y = 0
		if not no_select_first then self:select_index(1, menu) end
	end
	self:update_content_dimensions()
end

---@param items MenuStackItem[]
---@param query string
---@param recursive? boolean
---@param prefix? string
---@return MenuStackItem[]
function search_items(items, query, recursive, prefix)
	local result = {}
	local concat = table.concat
	for _, item in ipairs(items) do
		if item.selectable ~= false then
			local prefixed_title = prefix and prefix .. ' / ' .. (item.title or '') or item.title
			if item.items and recursive then
				itable_append(result, search_items(item.items, query, recursive, prefixed_title))
			else
				local title = item.title and item.title:lower()
				local hint = item.hint and item.hint:lower()
				local initials_title = title and concat(initials(title))
				local romanization = need_romanization()
				if romanization then
					ligature_conv_title = title and char_conv(title, true)
					initials_conv_title = title and concat(initials(char_conv(title, false)))
				end
				if title and title:find(query, 1, true) or
					title and romanization and ligature_conv_title:find(query, 1, true) or
					hint and hint:find(query, 1, true) or
					title and initials_title:find(query, 1, true) or
					title and romanization and initials_conv_title:find(query, 1, true) or
					hint and concat(initials(hint)):find(query, 1, true) then
					item = table_assign({}, item)
					item.title = prefixed_title
					item.ass_safe_title = nil
					result[#result + 1] = item
				end
			end
		end
	end
	return result
end

---@param menu? MenuStack
function Menu:search_submit(menu)
	menu = menu or self.current
	if not menu.search then return end
	if menu.on_search then
		local search_type = type(menu.on_search)
		if search_type == 'string' then
			mp.command(menu.on_search .. ' ' .. menu.search.query)
		elseif search_type == 'table' then
			local command = itable_join({}, menu.on_search)
			command[#command + 1] = menu.search.query
			mp.command_native(command)
		else
			menu.on_search(menu.search.query)
		end
	else
		self:search_internal(menu)
	end
end

---@param query string
---@param menu? MenuStack
function Menu:search_query_update(query, menu)
	menu = menu or self.current
	menu.search.query = query
	if menu.search_debounce ~= 'submit' then
		if menu.search.timeout then
			menu.search.timeout:kill()
			menu.search.timeout:resume()
		else
			self:search_submit(menu)
		end
	end
	request_render()
end

---@param event? string
---@param word_mode? boolean Delete by words.
function Menu:search_backspace(event, word_mode)
	local pos, old_query = #self.current.search.query, self.current.search.query
	local is_palette = self.current.search_style == 'palette'
	if word_mode then
		local word_pat, other_pat = '[^%c%s%p]+$', '[%c%s%p]+$'
		local init_pat = old_query:sub(#old_query):match(word_pat) and word_pat or other_pat
		-- First we match all same type consecutive chars at the end
		local tail = old_query:match(init_pat) or ''
		-- If there's only one, we extend the tail with opposite type chars
		if tail and #tail == 1 then
			tail = tail .. old_query:sub(1, #old_query - #tail):match(init_pat == word_pat and other_pat or word_pat)
		end
		pos = pos - #tail
	else
		-- The while loop is for skipping utf8 continuation bytes
		while pos > 1 and old_query:byte(pos) >= 0x80 and old_query:byte(pos) <= 0xbf do
			pos = pos - 1
		end
		pos = pos - 1
	end
	local new_query = old_query:sub(1, pos)
	if new_query ~= old_query and (is_palette or not self.type_to_search or pos > 0) then
		self:search_query_update(new_query)
	elseif not is_palette and self.type_to_search then
		self:search_stop()
	elseif is_palette and event ~= 'repeat' then
		self:back()
	end
end

function Menu:search_text_input(info)
	local menu = self.current
	if not menu.search and menu.search_style == 'disabled' then return end
	if info.event ~= 'up' then
		local key_text = info.key_text
		if not key_text then
			-- might be KP0 to KP9 or KP_DEC
			key_text = info.key_name:match('KP_?(.+)')
			if not key_text then return end
			if key_text == 'DEC' then key_text = '.' end
		end
		if not menu.search then self:search_start() end
		self:search_query_update(menu.search.query .. key_text)
	end
end

---@param menu? MenuStack
function Menu:search_stop(menu)
	menu = menu or self.current
	self:search_query_update('', menu)
	menu.search = nil
	self:search_ensure_key_bindings()
	self:update_dimensions()
	self:reset_navigation()
end

---@param menu? MenuStack
function Menu:search_init(menu)
	menu = menu or self.current
	if menu.search then return end
	local timeout
	if menu.search_debounce ~= 'submit' and menu.search_debounce > 0 then
		timeout = mp.add_timeout(menu.search_debounce / 1000, self:create_action(function()
			self:search_submit(menu)
		end))
		timeout:kill()
	end
	menu.search = {
		query = '',
		timeout = timeout,
		min_top = menu.top,
		max_width = menu.width,
		source = {
			width = menu.width,
			top = menu.top,
			scroll_y = menu.scroll_y,
			selected_index = menu.selected_index,
			items = not menu.on_search and menu.items or nil,
		},
	}
end

---@param menu? MenuStack
function Menu:search_start(menu)
	if (menu or self.current).search_style == 'disabled' then return end
	self:search_init(menu)
	self:search_ensure_key_bindings()
	self:update_dimensions()
end

---@param menu? MenuStack
function Menu:search_clear_query(menu)
	menu = menu or self.current
	if not self.current.search_style == 'palette' and self.type_to_search then
		self:search_stop(menu)
	else
		self:search_query_update('', menu)
	end
end

function Menu:key_bs(info)
	if info.event ~= 'up' then
		if self.current.search then
			if self.modifiers.shift then
				self:search_clear_query()
			else
				self:search_backspace(info.event, self.modifiers.ctrl)
			end
		elseif info.event ~= 'repeat' then
			self:back()
		end
	end
end

function Menu:key_ctrl_enter()
	if self.current.search then
		self:search_submit()
	else
		self:open_selected_item_preselect()
	end
end

function Menu:key_left()
	if self.current.search then -- control cursor when it's implemented
	else
		self:back()
	end
end

function Menu:key_right()
	if self.current.search then -- control cursor when it's implemented
	else
		self:open_selected_item_preselect()
	end
end

function Menu:search_enable_key_bindings()
	if #self.key_bindings_search ~= 0 then return end
	local flags = {repeatable = true, complex = true}
	local add_key_binding = self.type_to_search and self.add_key_binding or self.search_add_key_binding
	add_key_binding(self, 'any_unicode', 'menu-search', self:create_key_action('search_text_input'), flags)
	-- KP0 to KP9 and KP_DEC are not included in any_unicode
	-- despite typically producing characters, they don't have a info.key_text
	add_key_binding(self, 'kp_dec', 'menu-search-kp-dec', self:create_key_action('search_text_input'), flags)
	for i = 0, 9 do
		add_key_binding(self, 'kp' .. i, 'menu-search-kp' .. i, self:create_key_action('search_text_input'), flags)
	end
end

function Menu:search_ensure_key_bindings()
	if self.type_to_search then return end
	if self.current.search then
		self:search_enable_key_bindings()
	else
		self:search_disable_key_bindings()
	end
end

function Menu:search_disable_key_bindings()
	for _, name in ipairs(self.key_bindings_search) do mp.remove_key_binding(name) end
	self.key_bindings_search = {}
end

function Menu:search_add_key_binding(key, name, fn, flags)
	self.key_bindings_search[#self.key_bindings_search + 1] = name
	mp.add_forced_key_binding(key, name, fn, flags)
end

function Menu:add_key_binding(key, name, fn, flags)
	self.key_bindings[#self.key_bindings + 1] = name
	mp.add_forced_key_binding(key, name, fn, flags)
end

function Menu:enable_key_bindings()
	-- The `mp.set_key_bindings()` method would be easier here, but that
	-- doesn't support 'repeatable' flag, so we are stuck with this monster.
	self:add_key_binding('up', 'menu-prev1', self:create_key_action('prev'), 'repeatable')
	self:add_key_binding('down', 'menu-next1', self:create_key_action('next'), 'repeatable')
	self:add_key_binding('ctrl+up', 'menu-move-up', self:create_key_action('move_selected_item_up'), 'repeatable')
	self:add_key_binding('ctrl+down', 'menu-move-down', self:create_key_action('move_selected_item_down'), 'repeatable')
	self:add_key_binding('left', 'menu-back1', self:create_key_action('key_left'))
	self:add_key_binding('right', 'menu-select1', self:create_key_action('key_right'))
	self:add_key_binding('shift+right', 'menu-select-soft1',
		self:create_key_action('open_selected_item_soft', {shift = true}))
	self:add_key_binding('shift+mbtn_left', 'menu-select3', self:create_modified_mbtn_left_handler({shift = true}))
	self:add_key_binding('ctrl+mbtn_left', 'menu-select4', self:create_modified_mbtn_left_handler({ctrl = true}))
	self:add_key_binding('alt+mbtn_left', 'menu-select4', self:create_modified_mbtn_left_handler({alt = true}))
	self:add_key_binding('mbtn_back', 'menu-back-alt3', self:create_key_action('back'))
	self:add_key_binding('bs', 'menu-back-alt4', self:create_key_action('key_bs'), {repeatable = true, complex = true})
	self:add_key_binding('shift+bs', 'menu-clear-query', self:create_key_action('key_bs', {shift = true}),
		{repeatable = true, complex = true})
	self:add_key_binding('ctrl+bs', 'menu-delete-word', self:create_key_action('key_bs', {ctrl = true}),
		{repeatable = true, complex = true})
	self:add_key_binding('enter', 'menu-select-alt3', self:create_key_action('open_selected_item_preselect'))
	self:add_key_binding('kp_enter', 'menu-select-alt4', self:create_key_action('open_selected_item_preselect'))
	self:add_key_binding('ctrl+enter', 'menu-select-ctrl1', self:create_key_action('key_ctrl_enter', {ctrl = true}))
	self:add_key_binding('alt+enter', 'menu-select-alt1',
		self:create_key_action('open_selected_item_preselect', {alt = true}))
	self:add_key_binding('ctrl+kp_enter', 'menu-select-ctrl2',
		self:create_key_action('open_selected_item_preselect', {ctrl = true}))
	self:add_key_binding('alt+kp_enter', 'menu-select-alt2',
		self:create_key_action('open_selected_item_preselect', {alt = true}))
	self:add_key_binding('shift+enter', 'menu-select-alt5',
		self:create_key_action('open_selected_item_soft', {shift = true}))
	self:add_key_binding('shift+kp_enter', 'menu-select-alt6',
		self:create_key_action('open_selected_item_soft', {shift = true}))
	self:add_key_binding('esc', 'menu-close', self:create_key_action('close'))
	self:add_key_binding('pgup', 'menu-page-up', self:create_key_action('on_pgup'), 'repeatable')
	self:add_key_binding('pgdwn', 'menu-page-down', self:create_key_action('on_pgdwn'), 'repeatable')
	self:add_key_binding('home', 'menu-home', self:create_key_action('on_home'))
	self:add_key_binding('end', 'menu-end', self:create_key_action('on_end'))
	self:add_key_binding('del', 'menu-delete-item', self:create_key_action('delete_selected_item'))
	self:add_key_binding('ctrl+v', 'menu-paste', self:create_key_action('paste'))
	if self.type_to_search then
		self:search_enable_key_bindings()
	else
		self:add_key_binding('/', 'menu-search1', self:create_key_action('search_start'))
		self:add_key_binding('ctrl+f', 'menu-search2', self:create_key_action('search_start'))
	end
end

function Menu:disable_key_bindings()
	self:search_disable_key_bindings()
	for _, name in ipairs(self.key_bindings) do mp.remove_key_binding(name) end
	self.key_bindings = {}
end

-- Check if menu is not closed or closing.
function Menu:is_alive() return not self.is_closing and not self.is_closed end

-- Wraps a function so that it won't run if menu is closing or closed.
---@param fn function()
function Menu:create_action(fn)
	return function(...)
		if self:is_alive() then fn(...) end
	end
end

---@param modifiers Modifiers
function Menu:create_modified_mbtn_left_handler(modifiers)
	return self:create_action(function()
		self.mouse_nav = true
		self.modifiers = modifiers or {}
		self:handle_cursor_down()
		self:handle_cursor_up()
		self.modifiers = {}
	end)
end

---@param name string
---@param modifiers? Modifiers
function Menu:create_key_action(name, modifiers)
	return self:create_action(function(...)
		self.mouse_nav = false
		self.modifiers = modifiers or {}
		self:maybe(name, ...)
		self.modifiers = {}
	end)
end

function Menu:render()
	for _, menu in ipairs(self.all) do
		if menu.fling then
			local time_delta = state.render_last_time - menu.fling.time
			local progress = menu.fling.easing(math.min(time_delta / menu.fling.duration, 1))
			self:set_scroll_to(round(menu.fling.y + menu.fling.distance * progress), menu)
			if progress < 1 then request_render() else menu.fling = nil end
		end
	end

	local display_rect = {ax = 0, ay = 0, bx = display.width, by = display.height}
	cursor:zone('primary_down', display_rect, self:create_action(function() self:handle_cursor_down() end))
	cursor:zone('primary_up', display_rect, self:create_action(function() self:handle_cursor_up() end))
	cursor:zone('wheel_down', self, function() self:handle_wheel_down() end)
	cursor:zone('wheel_up', self, function() self:handle_wheel_up() end)

	local ass = assdraw.ass_new()
	local spacing = self.item_padding
	local icon_size = self.font_size

	---@param menu MenuStack
	---@param x number
	---@param pos number Horizontal position index. 0 = current menu, <0 parent menus, >1 submenu.
	local function draw_menu(menu, x, pos)
		local is_current, is_parent, is_submenu = pos == 0, pos < 0, pos > 0
		local menu_opacity = (pos == 0 and 1 or config.opacity.submenu ^ math.abs(pos)) * self.opacity
		local ax, ay, bx, by = x, menu.top, x + menu.width, menu.top + menu.height
		local draw_title = menu.is_root and menu.title or menu.search
		local scroll_clip = '\\clip(0,' .. ay .. ',' .. display.width .. ',' .. by .. ')'
		local start_index = math.floor(menu.scroll_y / self.scroll_step) + 1
		local end_index = math.ceil((menu.scroll_y + menu.height) / self.scroll_step)
		local menu_rect = {
			ax = ax,
			ay = ay - (draw_title and self.scroll_step + self.padding or 0) - self.padding,
			bx = bx,
			by = by + self.padding,
		}
		local blur_selected_index = is_current and self.mouse_nav

		-- Background
		ass:rect(menu_rect.ax, menu_rect.ay, menu_rect.bx, menu_rect.by, {
			color = bg,
			opacity = menu_opacity * config.opacity.menu,
			radius = state.radius > 0 and state.radius + self.padding or 0,
		})

		if is_parent then
			cursor:zone('primary_down', menu_rect, self:create_action(function() self:slide_in_menu(menu, x) end))
		end

		-- Draw submenu if selected
		local submenu_rect, current_item = nil, is_current and menu.selected_index and menu.items[menu.selected_index]
		local submenu_is_hovered = false
		if current_item and current_item.items then
			submenu_rect = draw_menu(current_item, menu_rect.bx + self.gap, 1)
			cursor:zone('primary_down', submenu_rect, self:create_action(function()
				self:open_selected_item({preselect_first_item = false})
			end))
		end

		for index = start_index, end_index, 1 do
			local item = menu.items[index]

			if not item then break end

			local item_ay = ay - menu.scroll_y + self.scroll_step * (index - 1)
			local item_by = item_ay + self.item_height
			local item_center_y = item_ay + (self.item_height / 2)
			local item_clip = (item_ay < ay or item_by > by) and scroll_clip or nil
			local content_ax, content_bx = ax + self.padding + spacing, bx - self.padding - spacing
			local is_selected = menu.selected_index == index

			-- Select hovered item
			if is_current and self.mouse_nav and item.selectable ~= false then
				if submenu_rect and cursor:direction_to_rectangle_distance(submenu_rect) then
					blur_selected_index = false
				else
					local item_rect_hitbox = {
						ax = menu_rect.ax + self.padding,
						ay = item_ay,
						bx = menu_rect.bx + (item.items and self.gap or -self.padding), -- to bridge the gap with cursor
						by = item_by,
					}
					if submenu_is_hovered or get_point_to_rectangle_proximity(cursor, item_rect_hitbox) == 0 then
						blur_selected_index = false
						menu.selected_index = index
						if not is_selected then request_render() end
					end
				end
			end

			local has_background = is_selected or item.active
			local next_item = menu.items[index + 1]
			local next_is_active = next_item and next_item.active
			local next_has_background = menu.selected_index == index + 1 or next_is_active
			local font_color = item.active and fgt or bgt

			-- Separator
			if item_by < by and ((not has_background and not next_has_background) or item.separator) then
				local separator_ay, separator_by = item_by, item_by + self.separator_size
				if has_background then
					separator_ay, separator_by = separator_ay + self.separator_size, separator_by + self.separator_size
				elseif next_has_background then
					separator_ay, separator_by = separator_ay - self.separator_size, separator_by - self.separator_size
				end
				ass:rect(ax + spacing, separator_ay, bx - spacing, separator_by, {
					color = fg, opacity = menu_opacity * (item.separator and 0.13 or 0.04),
				})
			end

			-- Background
			local highlight_opacity = 0 + (item.active and 0.8 or 0) + (is_selected and 0.15 or 0)
			if not is_submenu and highlight_opacity > 0 then
				ass:rect(ax + self.padding, item_ay, bx - self.padding, item_by, {
					radius = state.radius,
					color = fg,
					opacity = highlight_opacity * menu_opacity,
					clip = item_clip,
				})
			end

			-- Icon
			if item.icon then
				local x = (not item.title and not item.hint and item.align == 'center')
					and menu_rect.ax + (menu_rect.bx - menu_rect.ax) / 2
					or content_bx - (icon_size / 2)
				if item.icon == 'spinner' then
					ass:spinner(x, item_center_y, icon_size * 1.5, {color = font_color, opacity = menu_opacity * 0.8})
				else
					ass:icon(x, item_center_y, icon_size * 1.5, item.icon, {
						color = font_color, opacity = menu_opacity, clip = item_clip,
					})
				end
				content_bx = content_bx - icon_size - spacing
			end

			local title_cut_x = content_bx
			if item.hint_width > 0 then
				-- controls title & hint clipping proportional to the ratio of their widths
				-- both title and hint get at least 50% of the width, unless they are smaller then that
				local width = content_bx - content_ax - spacing
				local title_min = math.min(item.title_width, width * 0.5)
				local hint_min = math.min(item.hint_width, width * 0.5)
				local title_ratio = item.title_width / (item.title_width + item.hint_width)
				title_cut_x = round(content_ax + clamp(title_min, width * title_ratio, width - hint_min))
			end

			-- Hint
			if item.hint then
				item.ass_safe_hint = item.ass_safe_hint or ass_escape(item.hint)
				local clip = '\\clip(' .. title_cut_x + spacing .. ',' ..
					math.max(item_ay, ay) .. ',' .. bx .. ',' .. math.min(item_by, by) .. ')'
				ass:txt(content_bx, item_center_y, 6, item.ass_safe_hint, {
					size = self.font_size_hint, color = font_color, wrap = 2, opacity = 0.5 * menu_opacity, clip = clip,
				})
			end

			-- Title
			if item.title then
				item.ass_safe_title = item.ass_safe_title or ass_escape(item.title)
				local clip = '\\clip(' .. ax .. ',' .. math.max(item_ay, ay) .. ','
					.. title_cut_x .. ',' .. math.min(item_by, by) .. ')'
				local title_x, align = content_ax, 4
				if item.align == 'right' then
					title_x, align = title_cut_x, 6
				elseif item.align == 'center' then
					title_x, align = content_ax + (title_cut_x - content_ax) / 2, 5
				end
				ass:txt(title_x, item_center_y, align, item.ass_safe_title, {
					size = self.font_size,
					color = font_color,
					italic = item.italic,
					bold = item.bold,
					wrap = 2,
					opacity = menu_opacity * (item.muted and 0.5 or 1),
					clip = clip,
				})
			end
		end

		-- Menu title
		if draw_title then
			local requires_submit = menu.search_debounce == 'submit'
			local rect = {
				ax = ax + spacing / 2 + self.padding,
				ay = ay - self.scroll_step - self.padding * 2,
				bx = bx - spacing / 2 - self.padding,
				by = math.min(by, ay - self.padding),
			}
			rect.cx, rect.cy = rect.ax + (rect.bx - rect.ax) / 2, rect.ay + (rect.by - rect.ay) / 2 -- centers

			if menu.title and not menu.ass_safe_title then
				menu.ass_safe_title = ass_escape(menu.title)
			end

			-- Bottom border
			ass:rect(ax, rect.by - self.separator_size, bx, rect.by, {color = fg, opacity = menu_opacity * 0.2})

			-- Do nothing when user clicks title
			if is_current then
				cursor:zone('primary_down', rect, function() end)
			end

			-- Title
			if menu.search then
				-- Icon
				local icon_size, icon_opacity = self.font_size * 1.3, menu_opacity * (requires_submit and 0.5 or 1)
				local icon_rect = {ax = rect.ax, ay = rect.ay, bx = ax + icon_size + spacing * 1.5, by = rect.by}

				if is_current and requires_submit then
					cursor:zone('primary_down', icon_rect, function() self:search_submit() end)
					if get_point_to_rectangle_proximity(cursor, icon_rect) == 0 then
						icon_opacity = menu_opacity
					end
				end

				ass:icon(rect.ax + icon_size / 2, rect.cy, icon_size, 'search', {
					color = fg,
					opacity = icon_opacity,
					clip = '\\clip(' ..
						icon_rect.ax .. ',' .. icon_rect.ay .. ',' .. icon_rect.bx .. ',' .. icon_rect.by .. ')',
				})

				-- Query/Placeholder
				if menu.search.query ~= '' then
					-- Add a ZWNBSP suffix to prevent libass from trimming trailing spaces
					local query = ass_escape(menu.search.query) .. '\239\187\191'
					ass:txt(rect.bx, rect.cy, 6, query, {
						size = self.font_size,
						color = bgt,
						wrap = 2,
						opacity = menu_opacity,
						clip = '\\clip(' .. icon_rect.bx .. ',' .. rect.ay .. ',' .. rect.bx .. ',' .. rect.by .. ')',
					})
				else
					local placeholder = (menu.search_style == 'palette' and menu.ass_safe_title)
						and menu.ass_safe_title
						or (requires_submit and t('type & ctrl+enter to search') or t('type to search'))
					ass:txt(rect.bx, rect.cy, 6, placeholder, {
						size = self.font_size,
						italic = true,
						color = bgt,
						wrap = 2,
						opacity = menu_opacity * 0.4,
						clip = '\\clip(' .. rect.ax .. ',' .. rect.ay .. ',' .. rect.bx .. ',' .. rect.by .. ')',
					})
				end

				-- Cursor
				local font_size_half, cursor_thickness = round(self.font_size / 2), round(self.font_size / 14)
				local cursor_ax, cursor_bx = rect.bx + 1, rect.bx + 1 + cursor_thickness
				ass:rect(cursor_ax, rect.cy - font_size_half, cursor_bx, rect.cy + font_size_half, {
					color = fg,
					opacity = menu_opacity * 0.5,
					clip = '\\clip(' .. cursor_ax .. ',' .. rect.ay .. ',' .. cursor_bx .. ',' .. rect.by .. ')',
				})
			else
				ass:txt(rect.cx, rect.cy, 5, menu.ass_safe_title, {
					size = self.font_size,
					bold = true,
					color = bgt,
					wrap = 2,
					opacity = menu_opacity,
					clip = '\\clip(' .. rect.ax .. ',' .. rect.ay .. ',' .. rect.bx .. ',' .. rect.by .. ')',
				})
			end
		end

		-- Scrollbar
		if menu.scroll_height > 0 then
			local groove_height = menu.height - 2
			local thumb_height = math.max((menu.height / (menu.scroll_height + menu.height)) * groove_height, 40)
			local thumb_y = ay + 1 + ((menu.scroll_y / menu.scroll_height) * (groove_height - thumb_height))
			local sax = bx - round(self.scrollbar_size / 2)
			local sbx = sax + self.scrollbar_size
			ass:rect(sax, thumb_y, sbx, thumb_y + thumb_height, {color = fg, opacity = menu_opacity * 0.8})
		end

		-- We are in mouse nav and cursor isn't hovering any item
		if blur_selected_index then
			menu.selected_index = nil
		end

		return menu_rect
	end

	-- Main menu
	draw_menu(self.current, self.ax, 0)

	-- Parent menus
	local parent_menu = self.current.parent_menu
	local parent_offset_x, parent_horizontal_index = self.ax, -1

	while parent_menu do
		parent_offset_x = parent_offset_x - parent_menu.width - self.gap
		draw_menu(parent_menu, parent_offset_x, parent_horizontal_index)
		parent_horizontal_index = parent_horizontal_index - 1
		parent_menu = parent_menu.parent_menu
	end

	return ass
end

return Menu
