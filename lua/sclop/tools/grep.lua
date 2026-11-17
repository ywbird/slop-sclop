local util = require('sclop.util')

local rg = util.has('rg')

sclop.tools.register{
	name = 'grep',
	description = 'Search file contents with a regular expression. Returns path:line:text, '
		.. 'at most 200 lines. include filters files by glob, e.g. "*.c".',
	schema = {
		type = 'object',
		properties = {
			pattern = { type = 'string', description = 'regular expression' },
			path = { type = 'string', description = 'file or directory, the working directory by default' },
			include = { type = 'string', description = 'glob of files to search' },
			ignore_case = { type = 'boolean' },
			literal = { type = 'boolean', description = 'treat the pattern as plain text' },
		},
		required = sclop.json.array{ 'pattern' },
	},
	summary = function(a)
		return a.pattern .. (a.path and ' in ' .. a.path or '')
	end,
	run = function(a, done)
		local argv
		if rg then
			argv = { 'rg', '-n', '--no-heading', '--color=never', '--max-columns=300' }
			if a.include then
				argv[#argv + 1] = '-g'
				argv[#argv + 1] = a.include
			end
		else
			argv = { 'grep', '-rnI', a.literal and '-F' or '-E' }
			if a.include then
				argv[#argv + 1] = '--include=' .. a.include
			end
		end
		if a.ignore_case then
			argv[#argv + 1] = '-i'
		end
		if rg and a.literal then
			argv[#argv + 1] = '-F'
		end
		for _, v in ipairs{ '-e', a.pattern or '', '--', util.expand(a.path or '.') } do
			argv[#argv + 1] = v
		end
		return util.capture(argv, function(out, code)
			if code == 1 and out == '' then
				return done('no matches')
			end
			done(util.truncate(out, 200, 50 * 1024), code > 1)
		end)
	end,
}
