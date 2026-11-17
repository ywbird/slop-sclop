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

test('sessions are written and continued', function()
	local saved, s = sclop.cwd, sclop.session
	sclop.cwd = dir
	s.reset()
	s.write({ role = 'user', content = { { type = 'text', text = 'hi' } } })
	s.write({ role = 'assistant', content = { { type = 'tool_call', id = 'x', name = 'read', args = {} } } })
	local path = s.path
	s.reset()
	local msgs = s.load(path)
	eq(#msgs, 2)
	eq(msgs[1].content[1].text, 'hi')
	eq(sclop.json.encode(msgs[2].content[1].args), '{}')
	local p, n = s.resume()
	eq(p, path)
	eq(n, 2)
	eq(sclop.agent.messages[1].content[1].text, 'hi')
	s.reset()
	sclop.agent.clear()
	sclop.cwd = saved
end)
