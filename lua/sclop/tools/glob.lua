local util = require('sclop.util')

local rg = util.has('rg')

sclop.tools.register{
	name = 'glob',
	description = 'Find files by glob pattern, e.g. "**/*.c" or "src/*.lua". Returns at most 500 paths.',
	schema = {
		type = 'object',
		properties = {
			pattern = { type = 'string', description = 'glob pattern' },
			path = { type = 'string', description = 'directory to search, the working directory by default' },
		},
		required = sclop.json.array{ 'pattern' },
	},
	summary = function(a)
		return a.pattern .. (a.path and ' in ' .. a.path or '')
	end,
	run = function(a, done)
		local dir, pattern = util.expand(a.path or '.'), a.pattern or '*'
		local argv
		if rg then
			argv = { 'rg', '--files', '--sort', 'path', '-g', pattern, '--', dir }
		elseif pattern:find('/') then
			argv = { 'find', dir, '-type', 'f', '-path', dir .. '/' .. (pattern:gsub('^%*%*/', '*/')) }
		else
			argv = { 'find', dir, '-type', 'f', '-name', pattern }
		end
		return util.capture(argv, function(out, code)
			if out == '' then
				return done(code > 1 and 'search failed' or 'no files found', code > 1)
			end
			done(util.truncate(out, 500, 50 * 1024), code > 1)
		end)
	end,
}
