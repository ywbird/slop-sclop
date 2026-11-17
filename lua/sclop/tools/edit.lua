local util = require('sclop.util')

sclop.tools.register{
	name = 'edit',
	description = 'Replace exact text in a file. old_string must match exactly once, including '
		.. 'whitespace, unless replace_all is true. Read the file first; do not include the line '
		.. 'number prefix from read.',
	schema = {
		type = 'object',
		properties = {
			path = { type = 'string', description = 'file path' },
			old_string = { type = 'string', description = 'exact text to replace' },
			new_string = { type = 'string', description = 'replacement text' },
			replace_all = { type = 'boolean', description = 'replace every occurrence' },
		},
		required = sclop.json.array{ 'path', 'old_string', 'new_string' },
	},
	summary = function(a)
		return a.path
	end,
	run = function(a, done)
		local path, old, new = util.expand(a.path), a.old_string or '', a.new_string or ''
		local f, err = io.open(path, 'rb')
		if not f then
			return done(err, true)
		end
		local data = f:read('*a')
		f:close()
		if not data then
			return done(a.path .. ' is not a file', true)
		end
		if old == '' then
			return done('old_string is empty', true)
		end
		if old == new then
			return done('old_string and new_string are the same', true)
		end
		local parts, pos, count = {}, 1, 0
		while true do
			local s, e = data:find(old, pos, true)
			if not s then
				break
			end
			count = count + 1
			parts[#parts + 1] = data:sub(pos, s - 1)
			parts[#parts + 1] = new
			pos = e + 1
		end
		if count == 0 then
			return done('old_string was not found in ' .. a.path, true)
		end
		if count > 1 and not a.replace_all then
			return done(string.format('old_string occurs %d times in %s: add context to make it unique, '
				.. 'or set replace_all', count, a.path), true)
		end
		parts[#parts + 1] = data:sub(pos)
		local w, werr = io.open(path, 'wb')
		if not w then
			return done(werr, true)
		end
		w:write(table.concat(parts))
		w:close()
		done(string.format('edited %s (%d replacement%s)', a.path, count, count == 1 and '' or 's'))
	end,
}
