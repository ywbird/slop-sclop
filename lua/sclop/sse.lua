-- server-sent events: sse(fn) returns feed(chunk), calling fn(event, data) per event
return function(fn)
	local buf, event, data = '', nil, {}
	return function(chunk)
		buf = buf .. chunk
		local pos = 1
		while true do
			local nl = buf:find('\n', pos, true)
			if not nl then
				break
			end
			local line = buf:sub(pos, nl - 1):gsub('\r$', '')
			pos = nl + 1
			if line == '' then
				if #data > 0 then
					fn(event or 'message', table.concat(data, '\n'))
				end
				event, data = nil, {}
			elseif line:sub(1, 1) ~= ':' then
				local field, value = line:match('^([^:]*):? ?(.*)$')
				if field == 'event' then
					event = value
				elseif field == 'data' then
					data[#data + 1] = value
				end
			end
		end
		buf = buf:sub(pos)
	end
end
