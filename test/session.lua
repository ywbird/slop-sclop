local util = require('sclop.util')

local dir = os.tmpname()
os.remove(dir)
os.execute('mkdir -p ' .. util.quote(dir))

test('AGENTS.md joins the system prompt', function()
	local saved = sclop.cwd
	sclop.cwd = dir
	assert(not sclop.agent.system_prompt():find('AGENTS.md', 1, true))
	local f = io.open(dir .. '/AGENTS.md', 'w')
	f:write('Use tabs.\n')
	f:close()
	local s = sclop.agent.system_prompt()
	sclop.cwd = saved
	assert(s:find('AGENTS.md in the working directory:\n\nUse tabs.', 1, true), s)
end)
