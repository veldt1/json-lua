local JSON = {}

-- Function to determine the type of the given Lua object
local function determine_type(object)
	-- If the object is not a table, return its type directly
	if type(object) ~= 'table' then return type(object) end
	
	local index = 1
	for _ in pairs(object) do
		if object[index] ~= nil then index = index + 1 else return 'table' end
	end
	return index == 1 and 'table' or 'array'
end

local escape_char_map = {
	['\\'] = '\\',
	['"'] = '"',
	['/'] = '/',
	['\b'] = 'b',
	['\f'] = 'f',
	['\n'] = 'n',
	['\r'] = 'r',
	['\t'] = 't'
}

local function escape_string(string_value)
	return string_value:gsub('["/\\%z\b\f\n\r\t]', function(c)
		return '\\' .. (escape_char_map[c] or string.format('u%04x', c:byte()))
	end)
end

-- Skip delimiters in the JSON string
local function skip_delimiter(str, position, delimiter, error_if_missing)
	position = position + #str:match('^%s*', position)
	if str:sub(position, position) ~= delimiter then
		if error_if_missing then
			error('Expected ' .. delimiter .. ' near position ' .. position)
		end
		return position, false
	end
	return position + 1, true
end

-- Parse a JSON string value
local function parse_string_value(str, position, accumulated_value)
	accumulated_value = accumulated_value or ''
	if position > #str then error('End of input found while parsing string.') end
	local current_char = str:sub(position, position)
	if current_char == '"' then return accumulated_value, position + 1 end
	if current_char ~= '\\' then return parse_string_value(str, position + 1, accumulated_value .. current_char) end
	local escape_map = {b = '\b', f = '\f', n = '\n', r = '\r', t = '\t'}
	return parse_string_value(str, position + 2, accumulated_value .. (escape_map[str:sub(position + 1, position + 1)] or str:sub(position + 1, position + 1)))
end

-- Parse a JSON number value
local function parse_number_value(str, position)
	local number_str = str:match('^-?%d+%.?%d*[eE]?[+-]?%d*', position)
	if not number_str then error('Error parsing number at position ' .. position .. '.') end
	return tonumber(number_str), position + #number_str
end

-- Stringify a Lua object to a JSON string
function JSON:Stringify(object, as_key)
	local string_list, kind = {}, determine_type(object)
	local handlers = {
		['array'] = function()
			if as_key then error('Cannot encode array as key.') end
			table.insert(string_list, '[')
			for index, value in ipairs(object) do
				if index > 1 then table.insert(string_list, ', ') end
				table.insert(string_list, JSON:Stringify(value))
			end
			table.insert(string_list, ']')
		end,
		['table'] = function()
			if as_key then error('Cannot encode table as key.') end
			table.insert(string_list, '{')
			for key, value in pairs(object) do
				if #string_list > 1 then table.insert(string_list, ', ') end
				table.insert(string_list, JSON:Stringify(key, true))
				table.insert(string_list, ':')
				table.insert(string_list, JSON:Stringify(value))
			end
			table.insert(string_list, '}')
		end,
		['string'] = function() return '"' .. escape_string(object) .. '"' end,
		['number'] = function() return as_key and '"' .. tostring(object) .. '"' or tostring(object) end,
		['boolean'] = function() return tostring(object) end,
		['nil'] = function() return 'null' end,
	}
	return handlers[kind] and handlers[kind]() or table.concat(string_list) or error('Unjsonifiable type: ' .. kind .. '.')
end

JSON.null = {}

-- Parse a JSON string into a Lua object
function JSON:Parse(str, position, end_delimiter)
	position = position or 1
	if position > #str then error('Reached unexpected end of input.') end
	position = position + #str:match('^%s*', position)
	local first_char = str:sub(position, position)
	if first_char == end_delimiter then return nil, position + 1 end
	local handlers = {
		['{'] = function()
			local object, key, delimiter_found = {}, true, true
			position = position + 1
			while true do
				key, position = JSON:Parse(str, position, '}')
				if key == nil then return object, position end
				if not delimiter_found then error('Comma missing between object items.') end
				position = skip_delimiter(str, position, ':', true)
				object[key], position = JSON:Parse(str, position)
				position, delimiter_found = skip_delimiter(str, position, ',')
			end
		end,
		['['] = function()
			local array, value, delimiter_found = {}, true, true
			position = position + 1
			while true do
				value, position = JSON:Parse(str, position, ']')
				if value == nil then return array, position end
				if not delimiter_found then error('Comma missing between array items.') end
				table.insert(array, value)
				position, delimiter_found = skip_delimiter(str, position, ',')
			end
		end,
		['"'] = function() return parse_string_value(str, position + 1) end,
		['-'] = function() return parse_number_value(str, position) end,
	}
	return (handlers[first_char] or handlers[first_char:match('%d')] or function()
		local literals = {['true'] = true, ['false'] = false, ['null'] = JSON.null}
		for literal_str, literal_val in pairs(literals) do
			local literal_end = position + #literal_str - 1
			if str:sub(position, literal_end) == literal_str then return literal_val, literal_end + 1 end
		end
		error('Invalid json syntax starting at position ' .. position .. ': ' .. str:sub(position, position + 10))
	end)()
end

return JSON
