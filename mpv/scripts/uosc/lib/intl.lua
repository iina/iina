local intl_dir = mp.get_script_directory() .. '/intl/'
local locale = {}
local cache = {}

-- https://learn.microsoft.com/en-us/windows/apps/publish/publish-your-app/supported-languages?pivots=store-installer-msix#list-of-supported-languages
function get_languages()
	local languages = {}

	for _, lang in ipairs(comma_split(options.languages)) do
		if (lang == 'slang') then
			local slang = mp.get_property_native('slang')
			if slang then
				itable_append(languages, slang)
			end
		else
			languages[#languages +1] = lang
		end
	end

	return languages
end

---@param path string
function get_locale_from_json(path)
	local expand_path = mp.command_native({'expand-path', path})

	local meta, meta_error = utils.file_info(expand_path)
	if not meta or not meta.is_file then
		return nil
	end

	local json_file = io.open(expand_path, 'r')
	if not json_file then
		return nil
	end

	local json = json_file:read('*all')
	json_file:close()

	local json_table = utils.parse_json(json)
	return json_table
end

---@param text string
function t(text, a)
	if not text then return '' end
	local key = text
	if a then key = key .. '|' .. a end
	if cache[key] then return cache[key] end
	cache[key] = string.format(locale[text] or text, a or '')
	return cache[key]
end

-- Load locales
local languages = get_languages()

for i = #languages, 1, -1 do
	lang = languages[i]
	if (lang:match('.json$')) then
		table_assign(locale, get_locale_from_json(lang))
	elseif (lang == 'en') then
		locale = {}
	else
		table_assign(locale, get_locale_from_json(intl_dir .. lang:lower() .. '.json'))
	end
end

return {t = t}
