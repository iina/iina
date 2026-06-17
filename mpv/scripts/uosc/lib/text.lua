-- https://en.wikipedia.org/wiki/Unicode_block
---@alias CodePointRange {[1]: integer; [2]: integer}

---@type CodePointRange[]
local zero_width_blocks = {
	{0x0000,  0x001F}, -- C0
	{0x007F,  0x009F}, -- Delete + C1
	{0x034F,  0x034F}, -- combining grapheme joiner
	{0x061C,  0x061C}, -- Arabic Letter	Strong
	{0x200B,  0x200F}, -- {zero-width space, zero-width non-joiner, zero-width joiner, left-to-right mark, right-to-left mark}
	{0x2028,  0x202E}, -- {line separator, paragraph separator, Left-to-Right Embedding, Right-to-Left Embedding, Pop Directional Format, Left-to-Right Override, Right-to-Left Override}
	{0x2060,  0x2060}, -- word joiner
	{0x2066,  0x2069}, -- {Left-to-Right Isolate, Right-to-Left Isolate, First Strong Isolate, Pop Directional Isolate}
	{0xFEFF,  0xFEFF}, -- zero-width non-breaking space
	-- Some other characters can also be combined https://en.wikipedia.org/wiki/Combining_character
	{0x0300,  0x036F}, -- Combining Diacritical Marks	 0 BMP	Inherited
	{0x1AB0,  0x1AFF}, -- Combining Diacritical Marks Extended	 0 BMP	Inherited
	{0x1DC0,  0x1DFF}, -- Combining Diacritical Marks Supplement	 0 BMP	Inherited
	{0x20D0,  0x20FF}, -- Combining Diacritical Marks for Symbols	 0 BMP	Inherited
	{0xFE20,  0xFE2F}, -- Combining Half Marks	 0 BMP	Cyrillic (2 characters), Inherited (14 characters)
	-- Egyptian Hieroglyph Format Controls and Shorthand format Controls
	{0x13430, 0x1345F}, -- Egyptian Hieroglyph Format Controls	 1 SMP	Egyptian Hieroglyphs
	{0x1BCA0, 0x1BCAF}, -- Shorthand Format Controls	 1 SMP	Common
	-- not sure how to deal with those https://en.wikipedia.org/wiki/Spacing_Modifier_Letters
	{0x02B0,  0x02FF}, -- Spacing Modifier Letters	 0 BMP	Bopomofo (2 characters), Latin (14 characters), Common (64 characters)
}

-- All characters have the same width as the first one
---@type CodePointRange[]
local same_width_blocks = {
	{0x3400,  0x4DBF}, -- CJK Unified Ideographs Extension A	 0 BMP	Han
	{0x4E00,  0x9FFF}, -- CJK Unified Ideographs	 0 BMP	Han
	{0x20000, 0x2A6DF}, -- CJK Unified Ideographs Extension B	 2 SIP	Han
	{0x2A700, 0x2B73F}, -- CJK Unified Ideographs Extension C	 2 SIP	Han
	{0x2B740, 0x2B81F}, -- CJK Unified Ideographs Extension D	 2 SIP	Han
	{0x2B820, 0x2CEAF}, -- CJK Unified Ideographs Extension E	 2 SIP	Han
	{0x2CEB0, 0x2EBEF}, -- CJK Unified Ideographs Extension F	 2 SIP	Han
	{0x2F800, 0x2FA1F}, -- CJK Compatibility Ideographs Supplement	 2 SIP	Han
	{0x30000, 0x3134F}, -- CJK Unified Ideographs Extension G	 3 TIP	Han
	{0x31350, 0x323AF}, -- CJK Unified Ideographs Extension H	 3 TIP	Han
}

local width_length_ratio = 0.5

---@type integer, integer
local osd_width, osd_height = 100, 100

---Get byte count of utf-8 character at index i in str
---@param str string
---@param i integer?
---@return integer
local function utf8_char_bytes(str, i)
	local char_byte = str:byte(i)
	local max_bytes = #str - i + 1
	if char_byte < 0xC0 then
		return math.min(max_bytes, 1)
	elseif char_byte < 0xE0 then
		return math.min(max_bytes, 2)
	elseif char_byte < 0xF0 then
		return math.min(max_bytes, 3)
	elseif char_byte < 0xF8 then
		return math.min(max_bytes, 4)
	else
		return math.min(max_bytes, 1)
	end
end

---Creates an iterator for an utf-8 encoded string
---Iterates over utf-8 characters instead of bytes
---@param str string
---@return fun(): integer?, string?
function utf8_iter(str)
	local byte_start = 1
	return function()
		local start = byte_start
		if #str < start then return nil end
		local byte_count = utf8_char_bytes(str, start)
		byte_start = start + byte_count
		return start, str:sub(start, start + byte_count - 1)
	end
end

---Estimating string length based on the number of characters
---@param char string
---@return number
function utf8_length(str)
	local str_length = 0
	for _, c in utf8_iter(str) do
		str_length = str_length + 1
	end
	return str_length
end

---Extract Unicode code point from utf-8 character at index i in str
---@param str string
---@param i integer
---@return integer
local function utf8_to_unicode(str, i)
	local byte_count = utf8_char_bytes(str, i)
	local char_byte = str:byte(i)
	local unicode = char_byte
	if byte_count ~= 1 then
		local shift = 2 ^ (8 - byte_count)
		char_byte = char_byte - math.floor(0xFF / shift) * shift
		unicode = char_byte * (2 ^ 6) ^ (byte_count - 1)
	end
	for j = 2, byte_count do
		char_byte = str:byte(i + j - 1) - 0x80
		unicode = unicode + char_byte * (2 ^ 6) ^ (byte_count - j)
	end
	return round(unicode)
end

---Convert Unicode code point to utf-8 string
---@param unicode integer
---@return string?
local function unicode_to_utf8(unicode)
	if unicode < 0x80 then
		return string.char(unicode)
	else
		local byte_count
		if unicode < 0x800 then
			byte_count = 2
		elseif unicode < 0x10000 then
			byte_count = 3
		elseif unicode < 0x110000 then
			byte_count = 4
		else
			return
		end -- too big

		local res = {}
		local shift = 2 ^ 6
		local after_shift = unicode
		for _ = byte_count, 2, -1 do
			local before_shift = after_shift
			after_shift = math.floor(before_shift / shift)
			table.insert(res, 1, before_shift - after_shift * shift + 0x80)
		end
		shift = 2 ^ (8 - byte_count)
		table.insert(res, 1, after_shift + math.floor(0xFF / shift) * shift)
		---@diagnostic disable-next-line: deprecated
		return string.char(unpack(res))
	end
end

---Update osd resolution if valid
---@param width integer
---@param height integer
local function update_osd_resolution(width, height)
	if width > 0 and height > 0 then osd_width, osd_height = width, height end
end

mp.observe_property('osd-dimensions', 'native', function(_, dim)
	if dim then update_osd_resolution(dim.w, dim.h) end
end)

local measure_bounds
do
	local text_osd = mp.create_osd_overlay('ass-events')
	text_osd.compute_bounds, text_osd.hidden = true, true

	---@param ass_text string
	---@return integer, integer, integer, integer
	measure_bounds = function(ass_text)
		update_osd_resolution(mp.get_osd_size())
		text_osd.res_x, text_osd.res_y = osd_width, osd_height
		text_osd.data = ass_text
		local res = text_osd:update()
		return res.x0, res.y0, res.x1, res.y1
	end
end

local normalized_text_width
do
	---@type {wrap: integer; bold: boolean; italic: boolean, rotate: number; size: number}
	local bounds_opts = {wrap = 2, bold = false, italic = false, rotate = 0, size = 0}

	---Measure text width and normalize to a font size of 1
	---text has to be ass safe
	---@param text string
	---@param size number
	---@param bold boolean
	---@param italic boolean
	---@param horizontal boolean
	---@return number, integer
	normalized_text_width = function(text, size, bold, italic, horizontal)
		bounds_opts.bold, bounds_opts.italic, bounds_opts.rotate = bold, italic, horizontal and 0 or -90
		local x1, y1 = nil, nil
		size = size / 0.8
		-- prevent endless loop
		local repetitions_left = 5
		repeat
			size = size * 0.8
			bounds_opts.size = size
			local ass = assdraw.ass_new()
			ass:txt(0, 0, horizontal and 7 or 1, text, bounds_opts)
			_, _, x1, y1 = measure_bounds(ass.text)
			repetitions_left = repetitions_left - 1
			-- make sure nothing got clipped
		until (x1 and x1 < osd_width and y1 < osd_height) or repetitions_left == 0
		local width = (repetitions_left == 0 and not x1) and 0 or (horizontal and x1 or y1)
		return width / size, horizontal and osd_width or osd_height
	end
end

---Estimates character length based on utf8 byte count
---1 character length is roughly the size of a latin character
---@param char string
---@return number
local function char_length(char)
	return #char > 2 and 2 or 1
end

---Estimates string length based on utf8 byte count
---Note: Making a string in the iterator with the character is a waste here,
---but as this function is only used when measuring whole string widths it's fine
---@param text string
---@return number
local function text_length(text)
	if not text or text == '' then return 0 end
	local text_length = 0
	for _, char in utf8_iter(tostring(text)) do text_length = text_length + char_length(char) end
	return text_length
end

---Finds the best orientation of text on screen and returns the estimated max size
---and if the text should be drawn horizontally
---@param text string
---@return number, boolean
local function fit_on_screen(text)
	local estimated_width = text_length(text) * width_length_ratio
	if osd_width >= osd_height then
		-- Fill the screen as much as we can, bigger is more accurate.
		return math.min(osd_width / estimated_width, osd_height), true
	else
		return math.min(osd_height / estimated_width, osd_width), false
	end
end

---Gets next stage from cache
---@param cache {[any]: table}
---@param value any
local function get_cache_stage(cache, value)
	local stage = cache[value]
	if not stage then
		stage = {}
		cache[value] = stage
	end
	return stage
end

---Is measured resolution sufficient
---@param px integer
---@return boolean
local function no_remeasure_required(px)
	return px >= 800 or (px * 1.1 >= osd_width and px * 1.1 >= osd_height)
end

local character_width
do
	---@type {[boolean]: {[string]: {[1]: number, [2]: integer}}}
	local char_width_cache = {}

	---Get measured width of character
	---@param char string
	---@param bold boolean
	---@return number, integer
	character_width = function(char, bold)
		---@type {[string]: {[1]: number, [2]: integer}}
		local char_widths = get_cache_stage(char_width_cache, bold)
		local width_px = char_widths[char]
		if width_px and no_remeasure_required(width_px[2]) then return width_px[1], width_px[2] end

		local unicode = utf8_to_unicode(char, 1)
		for _, block in ipairs(zero_width_blocks) do
			if unicode >= block[1] and unicode <= block[2] then
				char_widths[char] = {0, math.huge}
				return 0, math.huge
			end
		end

		local measured_char = nil
		for _, block in ipairs(same_width_blocks) do
			if unicode >= block[1] and unicode <= block[2] then
				measured_char = unicode_to_utf8(block[1])
				width_px = char_widths[measured_char]
				if width_px and no_remeasure_required(width_px[2]) then
					char_widths[char] = width_px
					return width_px[1], width_px[2]
				end
				break
			end
		end

		if not measured_char then measured_char = char end
		-- half as many repetitions for wide characters
		local char_count = 10 / char_length(char)
		local max_size, horizontal = fit_on_screen(measured_char:rep(char_count))
		local size = math.min(max_size * 0.9, 50)
		char_count = math.min(math.floor(char_count * max_size / size * 0.8), 100)
		local enclosing_char, enclosing_width, next_char_count = '|', 0, char_count
		if measured_char == enclosing_char then
			enclosing_char = ''
		else
			enclosing_width = 2 * character_width(enclosing_char, bold)
		end
		local width_ratio, width, px = nil, nil, nil
		repeat
			char_count = next_char_count
			local str = enclosing_char .. measured_char:rep(char_count) .. enclosing_char
			width, px = normalized_text_width(str, size, bold, false, horizontal)
			width = width - enclosing_width
			width_ratio = width * size / (horizontal and osd_width or osd_height)
			next_char_count = math.min(math.floor(char_count / width_ratio * 0.9), 100)
		until width_ratio < 0.05 or width_ratio > 0.5 or char_count == next_char_count
		width = width / char_count

		width_px = {width, px}
		if char ~= measured_char then char_widths[measured_char] = width_px end
		char_widths[char] = width_px
		return width, px
	end
end

---Calculate text width from individual measured characters
---@param text string|number
---@param bold boolean
---@return number, integer
local function character_based_width(text, bold)
	local max_width = 0
	local min_px = math.huge
	for line in tostring(text):gmatch('([^\n]*)\n?') do
		local total_width = 0
		for _, char in utf8_iter(line) do
			local width, px = character_width(char, bold)
			total_width = total_width + width
			if px < min_px then min_px = px end
		end
		if total_width > max_width then max_width = total_width end
	end
	return max_width, min_px
end

---Measure width of whole text
---@param text string|number
---@param bold boolean
---@param italic boolean
---@return number, integer
local function whole_text_width(text, bold, italic)
	text = tostring(text)
	local size, horizontal = fit_on_screen(text)
	return normalized_text_width(ass_escape(text), size * 0.9, bold, italic, horizontal)
end

---Scale normalized width to real width based on font size and italic
---@param opts {size: number; italic?: boolean}
---@return number, number
local function opts_factor_offset(opts)
	return opts.size, opts.italic and opts.size * 0.2 or 0
end

---Scale normalized width to real width based on font size and italic
---@param opts {size: number; italic?: boolean}
---@return number
local function normalized_to_real(width, opts)
	local factor, offset = opts_factor_offset(opts)
	return factor * width + offset
end

do
	---@type {[boolean]: {[boolean]: {[string|number]: {[1]: number, [2]: integer}}}} | {[boolean]: {[string|number]: {[1]: number, [2]: integer}}}
	local width_cache = {}

	---Calculate width of text with the given opts
	---@param text string|number
	---@return number
	---@param opts {size: number; bold?: boolean; italic?: boolean}
	function text_width(text, opts)
		if not text or text == '' then return 0 end

		---@type boolean, boolean
		local bold, italic = opts.bold or options.font_bold, opts.italic or false

		if options.text_width_estimation then
			---@type {[string|number]: {[1]: number, [2]: integer}}
			local text_width = get_cache_stage(width_cache, bold)
			local width_px = text_width[text]
			if width_px and no_remeasure_required(width_px[2]) then return normalized_to_real(width_px[1], opts) end

			local width, px = character_based_width(text, bold)
			width_cache[bold][text] = {width, px}
			return normalized_to_real(width, opts)
		else
			---@type {[string|number]: {[1]: number, [2]: integer}}
			local text_width = get_cache_stage(get_cache_stage(width_cache, bold), italic)
			local width_px = text_width[text]
			if width_px and no_remeasure_required(width_px[2]) then return width_px[1] * opts.size end

			local width, px = whole_text_width(text, bold, italic)
			width_cache[bold][italic][text] = {width, px}
			return width * opts.size
		end
	end
end

do
	---@type {[string]: string}
	local cache = {}

	---Replace all timestamp digits with 0
	---@param timestamp string
	function timestamp_zero_rep(timestamp)
		local substitute = cache[#timestamp]
		if not substitute then
			substitute = timestamp:gsub('%d', '0')
			cache[#timestamp] = substitute
		end
		return substitute
	end

	---Get width of formatted timestamp as if all the digits were replaced with 0
	---@param timestamp string
	---@param opts {size: number; bold?: boolean; italic?: boolean}
	---@return number
	function timestamp_width(timestamp, opts)
		return text_width(timestamp_zero_rep(timestamp), opts)
	end
end

do
	local wrap_at_chars = {' ', '　', '-', '–'}
	local remove_when_wrap = {' ', '　'}

	---Wrap the text at the closest opportunity to target_line_length
	---@param text string
	---@param opts {size: number; bold?: boolean; italic?: boolean}
	---@param target_line_length number
	---@return string, integer
	function wrap_text(text, opts, target_line_length)
		local target_line_width = target_line_length * width_length_ratio * opts.size
		local bold, scale_factor, scale_offset = opts.bold or false, opts_factor_offset(opts)
		local wrap_at_chars, remove_when_wrap = wrap_at_chars, remove_when_wrap
		local lines = {}
		for _, text_line in ipairs(split(text, '\n')) do
			local line_width = scale_offset
			local line_start = 1
			local before_end = nil
			local before_width = scale_offset
			local before_line_start = 0
			local before_removed_width = 0
			for char_start, char in utf8_iter(text_line) do
				local char_end = char_start + #char - 1
				local char_width = character_width(char, bold) * scale_factor
				line_width = line_width + char_width
				if (char_end == #text_line) or itable_has(wrap_at_chars, char) then
					local remove = itable_has(remove_when_wrap, char)
					local line_width_after_remove = line_width - (remove and char_width or 0)
					if line_width_after_remove < target_line_width then
						before_end = remove and char_start - 1 or char_end
						before_width = line_width_after_remove
						before_line_start = char_end + 1
						before_removed_width = remove and char_width or 0
					else
						if (target_line_width - before_width) <
							(line_width_after_remove - target_line_width) then
							lines[#lines + 1] = text_line:sub(line_start, before_end)
							line_start = before_line_start
							line_width = line_width - before_width - before_removed_width + scale_offset
						else
							lines[#lines + 1] = text_line:sub(line_start, remove and char_start - 1 or char_end)
							line_start = char_end + 1
							line_width = scale_offset
						end
						before_end = line_start
						before_width = scale_offset
					end
				end
			end
			if #text_line >= line_start then
				lines[#lines + 1] = text_line:sub(line_start)
			elseif text_line == '' then
				lines[#lines + 1] = ''
			end
		end
		return table.concat(lines, '\n'), #lines
	end
end

do
	local word_separators = create_set({
		' ', '　', '\t', '-', '–', '_', ',', '.', '+', '&', '(', ')', '[', ']', '{', '}', '<', '>', '/', '\\',
		'（', '）', '【', '】', '；', '：', '《', '》', '“', '”', '‘', '’', '？', '！',
	})

	---Get the first character of each word
	---@param str string
	---@return string[]
	function initials(str)
		local initials, is_word_start, word_separators = {}, true, word_separators
		for _, char in utf8_iter(str) do
			if word_separators[char] then
				is_word_start = true
			elseif is_word_start then
				initials[#initials + 1] = char
				is_word_start = false
			end
		end
		return initials
	end
end
