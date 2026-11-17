local util = require('sclop.util')

local cache

-- the value of a frontmatter key; folded (>) and literal (|) blocks are joined
local function field(front, key)
	local v, rest = ('\n' .. front .. '\n'):match('\n' .. key .. ':[ \t]*([^\n]*)\n(.*)')
	if not v then
		return nil
	end
	if v:match('^[>|][-+]?%s*$') then
		local lines = {}
		for line in rest:gmatch('([^\n]*)\n') do
			if not line:match('^%s') then
				break
			end
			lines[#lines + 1] = line:match('^%s*(.-)%s*$')
		end
		v = table.concat(lines, ' ')
	end
	return (v:gsub('^["\'](.*)["\']$', '%1'))
end

local function skills()
	if cache then
		return cache
	end
	cache = {}
	for _, dir in ipairs(sclop.skills) do
		dir = util.expand(dir)
		local p = io.popen('ls -1 ' .. util.quote(dir) .. ' 2>/dev/null')
		for name in p:lines() do
			local file = dir .. '/' .. name .. '/SKILL.md'
			local f = io.open(file)
			if f then
				local front = f:read('*a'):match('^%-%-%-\r?\n(.-)\r?\n%-%-%-')
				f:close()
				local id = front and field(front, 'name') or name
				if not cache[id] then
					cache[id] = { file = file, dir = dir .. '/' .. name,
						description = front and field(front, 'description') or '' }
				end
			end
		end
		p:close()
	end
	return cache
end

sclop.tools.register{
	name = 'skill',
	available = function()
		return next(skills()) ~= nil
	end,
	description = function()
		local names = {}
		for name in pairs(skills()) do
			names[#names + 1] = name
		end
		table.sort(names)
		for i, name in ipairs(names) do
			names[i] = '- ' .. name .. ': ' .. skills()[name].description
		end
		return 'Load a skill: instructions for a particular kind of task. Load one when the task '
			.. 'matches its description.\nAvailable skills:\n' .. table.concat(names, '\n')
	end,
	schema = {
		type = 'object',
		properties = { name = { type = 'string', description = 'skill name' } },
		required = sclop.json.array{ 'name' },
	},
	summary = function(a)
		return a.name
	end,
	render = function(_, is_error)
		return not is_error and sclop.style.gray('  ⎿ loaded') or nil
	end,
	run = function(a, done)
		local s = skills()[a.name or '']
		if not s then
			return done('no skill named ' .. tostring(a.name), true)
		end
		local f, err = io.open(s.file)
		if not f then
			return done(err, true)
		end
		local text = f:read('*a')
		f:close()
		done(text .. '\n\nBase directory of this skill: ' .. s.dir)
	end,
}

return { reload = function() cache = nil end }
