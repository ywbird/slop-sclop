-- small helpers shared by tools and plugins
local U = {}

function U.expand(path)
	path = path or ''
	if path:sub(1, 1) == '~' then
		path = (os.getenv('HOME') or '') .. path:sub(2)
	end
	return path
end

function U.quote(s)
	return "'" .. s:gsub("'", "'\\''") .. "'"
end

function U.has(cmd)
	local p = io.popen('command -v ' .. cmd .. ' 2>/dev/null')
	local found = p:read('*l')
	p:close()
	return found ~= nil
end

function U.lines(text)
	local t = {}
	for l in (text:gsub('\n$', '') .. '\n'):gmatch('(.-)\n') do
		t[#t + 1] = l
	end
	return t
end

-- keep at most max_lines lines and max_bytes bytes, from the head or the tail
function U.truncate(text, max_lines, max_bytes, tail)
	local lines = U.lines(text)
	local n, keep, bytes = #lines, {}, 0
	local first, last, step = 1, n, 1
	if tail then
		first, last, step = n, 1, -1
	end
	for i = first, last, step do
		if #keep >= max_lines or bytes + #lines[i] + 1 > max_bytes then
			break
		end
		keep[#keep + 1] = lines[i]
		bytes = bytes + #lines[i] + 1
	end
	if #keep == 0 and n > 0 then
		keep[1] = tail and lines[n]:sub(-max_bytes) or lines[1]:sub(1, max_bytes)
	end
	local cut = n - #keep
	if tail then
		for i = 1, math.floor(#keep / 2) do
			keep[i], keep[#keep - i + 1] = keep[#keep - i + 1], keep[i]
		end
		if cut > 0 then
			table.insert(keep, 1, string.format('(%d earlier lines cut)', cut))
		end
	elseif cut > 0 then
		keep[#keep + 1] = string.format('(%d more lines cut)', cut)
	end
	return table.concat(keep, '\n')
end

-- run argv, collecting stdout and stderr: done(output, code, signal); returns the process
function U.capture(argv, done, opts)
	local out = {}
	opts = opts or {}
	local p, err = sclop.spawn{
		argv = argv,
		cwd = opts.cwd,
		merge = true,
		on_stdout = function(data)
			out[#out + 1] = data
			if opts.progress then
				opts.progress(table.concat(out))
			end
		end,
		on_exit = function(code, sig)
			done(table.concat(out), code, sig)
		end,
	}
	if not p then
		done(err, -1, 0)
	end
	return p
end

return U
