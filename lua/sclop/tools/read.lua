local util = require('sclop.util')

local MAX_BYTES = 64 * 1024

sclop.tools.register{
	name = 'read',
	description = 'Read a text file or list a directory. Lines come numbered: line number, a tab, then text; '
		.. 'the number is not part of the file. A call returns at most limit lines (default 2000) '
		.. 'and about 64 KB; lines longer than 2000 bytes are cut. '
		.. 'Use offset (first line, from 1) and limit to page through big files. '
		.. 'Use grep to find specific content in large files, and prefer one larger read over many small slices. '
		.. 'A directory path lists its entries.',
	schema = {
		type = 'object',
		properties = {
			path = { type = 'string', description = 'file or directory path' },
			offset = { type = 'integer', description = 'first line to read, from 1' },
			limit = { type = 'integer', description = 'number of lines, 2000 by default' },
		},
		required = sclop.json.array{ 'path' },
	},
	summary = function(a)
		return a.path
	end,
	render = function(text, is_error)
		if is_error then
			return nil
		end
		local n = select(2, text:gsub('\n', '')) + 1
		return sclop.style.gray(string.format('  ⎿ %d lines', n))
	end,
	run = function(a, done)
		local path = util.expand(a.path)
		local f, err = io.open(path, 'rb')
		if not f then
			return done(err, true)
		end
		local data = f:read('*a')
		f:close()
		if not data then
			local p = io.popen('ls -1Ap ' .. util.quote(path) .. ' 2>&1')
			local list = p:read('*a')
			p:close()
			return done(list ~= '' and list or '(empty directory)')
		end
		if data:sub(1, 8192):find('\0', 1, true) then
			return done('this is a binary file', true)
		end
		local first = math.max(1, math.floor(tonumber(a.offset) or 1))
		local limit = math.max(1, math.floor(tonumber(a.limit) or 2000))
		local out, n, bytes = {}, 0, 0
		if data ~= '' and data:sub(-1) ~= '\n' then
			data = data .. '\n'
		end
		for line in data:gmatch('([^\n]*)\n') do
			n = n + 1
			if n >= first and #out < limit and bytes < MAX_BYTES then
				if #line > 2000 then
					line = line:sub(1, 2000) .. '…'
				end
				out[#out + 1] = string.format('%6d\t%s', n, line)
				bytes = bytes + #out[#out] + 1
			end
		end
		if #out == 0 then
			return done(n == 0 and '(empty file)' or string.format('offset %d is past the end: the file has %d lines', first, n), n > 0)
		end
		local last = first + #out - 1
		if last < n then
			out[#out + 1] = string.format('(lines %d-%d of %d, read on with offset=%d)', first, last, n, last + 1)
		end
		done(table.concat(out, '\n'))
	end,
}
