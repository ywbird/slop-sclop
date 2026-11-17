local util = require('sclop.util')

sclop.tools.register{
	name = 'write',
	description = 'Create a file or replace its whole content. Missing parent directories are created. '
		.. 'Prefer edit for changes to part of an existing file.',
	schema = {
		type = 'object',
		properties = {
			path = { type = 'string', description = 'file path' },
			content = { type = 'string', description = 'the complete new content' },
		},
		required = sclop.json.array{ 'path', 'content' },
	},
	summary = function(a)
		return a.path
	end,
	run = function(a, done)
		local path, content = util.expand(a.path), a.content or ''
		local dir = path:match('^(.+)/[^/]*$')
		if dir then
			os.execute('mkdir -p ' .. util.quote(dir))
		end
		local f, err = io.open(path, 'wb')
		if not f then
			return done(err, true)
		end
		local ok, werr = f:write(content)
		f:close()
		if not ok then
			return done(werr, true)
		end
		done(string.format('wrote %d bytes to %s', #content, a.path))
	end,
}
