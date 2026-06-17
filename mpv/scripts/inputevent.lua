-- InputEvent
-- https://github.com/natural-harmonia-gropius/input-event

local utils = require("mp.utils")
local options = require("mp.options")

local o = {
    configs = "input.conf",
}

local bind_map = {}

local event_pattern = {
    { to = "penta_click", from = "down,up,down,up,down,up,down,up,down,up", length = 10 },
    { to = "quatra_click", from = "down,up,down,up,down,up,down,up", length = 8 },
    { to = "triple_click", from = "down,up,down,up,down,up", length = 6 },
    { to = "double_click", from = "down,up,down,up", length = 4 },
    { to = "click", from = "down,up", length = 2 },
    { to = "press", from = "down", length = 1 },
    { to = "release", from = "up", length = 1 },
}

-- https://mpv.io/manual/master/#input-command-prefixes
local prefixes = { "osd-auto", "no-osd", "osd-bar", "osd-msg", "osd-msg-bar", "raw", "expand-properties", "repeatable",
    "async", "sync" }

-- https://mpv.io/manual/master/#list-of-input-commands
local commands = { "set", "cycle", "add", "multiply" }

function table:push(element)
    self[#self + 1] = element
    return self
end

function table:assign(source)
    for key, value in pairs(source) do
        self[key] = value
    end
    return self
end

function table:has(element)
    for _, value in ipairs(self) do
        if value == element then
            return true
        end
    end
    return false
end

function table:filter(filter)
    local nt = {}
    for index, value in ipairs(self) do
        if (filter(index, value)) then
            nt = table.push(nt, value)
        end
    end
    return nt
end

function table:remove(element)
    return table.filter(self, function(i, v) return v ~= element end)
end

function table:join(separator)
    local result = ""
    for i, v in ipairs(self) do
        local value = type(v) == "string" and v or tostring(v)
        local semi = i == #self and "" or separator
        result = result .. value .. semi
    end
    return result
end

function string:trim()
    return (self:gsub("^%s*(.-)%s*$", "%1"))
end

function string:replace(pattern, replacement)
    local result, n = self:gsub(pattern, replacement)
    return result
end

function string:split(separator)
    local fields = {}
    local separator = separator or ":"
    local pattern = string.format("([^%s]+)", separator)
    local copy = self:gsub(pattern, function(c) fields[#fields + 1] = c end)
    return fields
end

function debounce(func, wait)
    func = type(func) == "function" and func or function() end
    wait = type(wait) == "number" and wait / 1000 or 0

    local timer = nil
    local timer_end = function()
        timer:kill()
        timer = nil
        func()
    end

    return function()
        if timer then
            timer:kill()
        end
        timer = mp.add_timeout(wait, timer_end)
    end
end

function now()
    return mp.get_time() * 1000
end

function command(command)
    return mp.command(command)
end

function command_split(command)
    local separator = { ";" }
    local escape = { "\\" }
    local quotation = { '"', "'" }
    local quotation_stack = {}
    local result = {}
    local temp = ""

    for i = 1, #command do
        local char = command:sub(i, i)

        if table.has(separator, char) and #quotation_stack == 0 then
            result = table.push(result, temp)
            temp = ""
        elseif table.has(quotation, char) and not table.has(escape, temp:sub(#temp, #temp)) then
            temp = temp .. char
            if quotation_stack[#quotation_stack] == char then
                quotation_stack = table.filter(quotation_stack, function(i, v) return i ~= #quotation_stack end)
            else
                quotation_stack = table.push(quotation_stack, char)
            end
        else
            temp = temp .. char
        end
    end

    if #temp then
        result = table.push(result, temp)
    end

    return result
end

function command_invert(command)
    local invert = ""
    local command_list = command_split(command)
    for i, v in ipairs(command_list) do
        local trimed = v:trim()
        local subs = trimed:split("%s*")
        local prefix = ""
        local command = ""
        local property = ""

        for index, value in ipairs(subs) do
            if command == "" and table.has(prefixes, value) then
                prefix = prefix .. value .. " "
            elseif command == "" then
                command = value
            elseif property == "" then
                property = value
            end
        end

        local value = mp.get_property(property)
        local semi = i == #command_list and "" or ";"

        if table.has(commands, command) then
            invert = invert .. prefix .. "set " .. property .. " " .. value .. semi
        else
            mp.msg.warn("\"" .. trimed .. "\" doesn't support auto restore.")
        end
    end
    return invert
end

local InputEvent = {}

function InputEvent:new(key, on)
    local Instance = {}
    setmetatable(Instance, self);
    self.__index = self;

    Instance.key = key
    Instance.on = table.assign({ click = "" }, on)
    Instance.queue = {}
    Instance.queue_max = { length = 0 }
    Instance.duration = mp.get_property_number("input-doubleclick-time", 300)
    Instance.ignored = {}

    for _, event in ipairs(event_pattern) do
        if Instance.on[event.to] and event.length > 1 then
            Instance.queue_max = { event = event.to, length = event.length }
            break
        end
    end

    return Instance
end

function InputEvent:emit(event)
    if self.ignored[event] then
        if now() - self.ignored[event] < self.duration then
            return
        end

        self.ignored[event] = nil
    end

    if event == "press" and self.on["release"] == "ignore" then
        self.on["release-auto"] = command_invert(self.on["press"])
    end

    if event == "release" and self.on[event] == "ignore" then
        event = "release-auto"
    end

    if event == "repeat" and self.on[event] == "ignore" then
        event = "click"
    end

    local cmd = self.on[event]
    if not cmd or cmd == "" then
        return
    end

    local expand = mp.command_native({ 'expand-text', cmd })
    if #command_split(cmd) == #command_split(expand) then
        cmd = mp.command_native({ 'expand-text', cmd })
    else
        mp.msg.warn("Unsafe property-expansion: " .. cmd)
    end

    command(cmd)
end

function InputEvent:handler(event)
    if event == "press" then
        self:handler("down")
        self:handler("up")
        return
    end

    if event == "down" then
        self:ignore("repeat")
    end

    if event == "repeat" then
        self:emit(event)
        return
    end

    if event == "up" then
        if #self.queue == 0 then
            self:emit("release")
            return
        end

        if #self.queue + 1 == self.queue_max.length then
            self.queue = {}
            self:emit(self.queue_max.event)
            return
        end
    end

    self.queue = table.push(self.queue, event)
    self.exec_debounced()
end

function InputEvent:exec()
    if #self.queue == 0 then
        return
    end

    local separator = ","

    local queue_string = table.join(self.queue, separator)
    for _, v in ipairs(event_pattern) do
        if self.on[v.to] then
            queue_string = queue_string:replace(v.from, v.to)
        end
    end

    self.queue = queue_string:split(separator)
    for _, event in ipairs(self.queue) do
        self:emit(event)
    end

    self.queue = {}
end

function InputEvent:ignore(event, timeout)
    timeout = timeout or 0

    self.ignored[event] = now() + timeout
end

function InputEvent:bind()
    self.exec_debounced = debounce(function() self:exec() end, self.duration)
    mp.add_forced_key_binding(self.key, self.key, function(e) self:handler(e.event) end, { complex = true })
end

function InputEvent:unbind()
    mp.remove_key_binding(self.key)
end

function InputEvent:rebind(diff)
    if type(diff) == "table" then
        self = table.assign(self, diff)
    end

    self:unbind()
    self:bind()
end

function bind(key, on)
    key = #key == 1 and key or key:upper()

    if type(on) == "string" then
        on = utils.parse_json(on)
    end

    if bind_map[key] then
        on = table.assign(bind_map[key].on, on)
        bind_map[key]:unbind()
    end

    bind_map[key] = InputEvent:new(key, on)
    bind_map[key]:bind()
end

function unbind(key)
    local binding = bind_map[key]
    if binding then
        binding:unbind()
        bind_map[key] = nil
    end
end

function bind_from_conf(path)
    local meta, meta_error = utils.file_info(path)
    if not meta or not meta.is_file then
        return {}
    end

    local kv = {}
    for line in io.lines(path) do
        line = line:trim()
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local key, cmd, comment = line:match("%s*([%S]+)%s+(.-)%s+#%s*(.-)%s*$")
            if comment then
                local comments = comment:split("#")
                local events = table.filter(comments, function(i, v) return v:match("^@") end)
                if events and #events > 0 then
                    local event = events[1]:match("^@(.*)"):trim()
                    if event and event ~= "" then
                        if kv[key] == nil then
                            kv[key] = {}
                        end
                        kv[key][event] = cmd
                    end
                end
            end
        end
    end

    local parsed = {}
    for key, on in pairs(kv) do
        table.insert(parsed, { key = key, on = on })
    end

    return parsed
end

function bind_from_json(path)
    local meta, meta_error = utils.file_info(path)
    if not meta or not meta.is_file then
        return {}
    end

    local json_file = io.open(path, "r")
    if not json_file then
        return {}
    end
    local json = json_file:read("*all")
    json_file:close()

    local parsed = utils.parse_json(json)
    return parsed
end

function bind_from_options_configs()
    for index, value in ipairs(o.configs:split(",")) do
        local path = value:trim()
        if path == "input.conf" then
            local input_conf = mp.get_property_native("input-conf")
            path = input_conf == "" and "~~/input.conf" or input_conf
        end
        path = mp.command_native({ "expand-path", path })

        local parsed = {}
        local splited_filename = path:split(".")
        local extension = splited_filename[#splited_filename]
        if extension == "conf" then
            parsed = bind_from_conf(path)
        elseif extension == "json" then
            parsed = bind_from_json(path)
        end

        if #parsed ~= 0 then
            for _, v in ipairs(parsed) do
                if v.key and v.on then
                    unbind(v.key)
                    bind(v.key, v.on)
                else
                    mp.msg.error("Invalidated config: " .. path)
                end
            end
        end
    end
end

function on_options_configs_update(list)
    if (list.configs) then
        for key, value in pairs(bind_map) do
            unbind(key)
        end
        bind_from_options_configs()
    end
end

mp.observe_property("input-doubleclick-time", "native", function(_, new_duration)
    for _, binding in pairs(bind_map) do
        binding:rebind({ duration = new_duration })
    end
end)

mp.observe_property("focused", "native", function(_, focused)
    local binding = bind_map["MBTN_LEFT"]
    if not binding or not focused then return end
    binding:ignore("click", 100)
end)

mp.register_script_message("bind", bind)
mp.register_script_message("unbind", unbind)

options.read_options(o, _, on_options_configs_update)

bind_from_options_configs()
