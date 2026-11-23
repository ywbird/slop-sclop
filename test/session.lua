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
	eq(io.open(dir .. '/.sclop/.gitignore'):read('*a'), '*\n')
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

local function text(role, t)
	return { role = role, content = { { type = 'text', text = t } } }
end

test('resume takes an explicit session path', function()
	local saved, s = sclop.cwd, sclop.session
	sclop.cwd = dir
	local old = dir .. '/.sclop/sessions/old.jsonl'
	local f = io.open(old, 'w')
	f:write(sclop.json.encode({ type = 'session', model = 'x/y', cwd = dir }), '\n')
	f:write(sclop.json.encode(text('user', 'old')), '\n')
	f:close()
	local p, n = s.resume(old)
	eq(p, old)
	eq(n, 1)
	eq(sclop.agent.messages[1].content[1].text, 'old')
	s.reset()

	local rel, rn = s.resume('.sclop/sessions/old.jsonl') -- relative to the working directory
	eq(rel, old)
	eq(rn, 1)
	s.reset()
	sclop.agent.clear()

	local missing, merr = s.resume(dir .. '/nope.jsonl')
	eq(missing, nil)
	assert(merr:find('no such session file', 1, true), merr)

	local plain = dir .. '/plain.jsonl'
	f = io.open(plain, 'w')
	f:write('{"role":"user","content":[]}\n')
	f:close()
	local bad, berr = s.resume(plain)
	eq(bad, nil)
	assert(berr:find('is not a session file', 1, true), berr)
	s.reset()
	sclop.cwd = saved
end)

test('a compact line in a session replaces what came before', function()
	local path = dir .. '/compact.jsonl'
	local f = io.open(path, 'w')
	for _, e in ipairs{ text('user', 'old'), { type = 'compact', summary = 'SUM' }, text('user', 'new') } do
		f:write(sclop.json.encode(e), '\n')
	end
	f:close()
	local msgs = sclop.session.load(path)
	eq(#msgs, 3)
	assert(msgs[1].content[1].text:find('SUM', 1, true))
	eq(msgs[3].content[1].text, 'new')
end)

-- replies 'S: <number of messages it was sent>'
sclop.providers.counter = {
	stream = function(_, req, h)
		local t = sclop.timer(5, function()
			h.done(text('assistant', 'S: ' .. #req.messages), { input = 10, output = 1 })
		end)
		return { cancel = function() t:stop() end }
	end,
}

-- run fn with the counter provider; check(turn_ends, summary) runs after `turns` turns
local function compaction_test(name, turns, fn, check)
	atest(name, function(done)
		local saved = { sclop.commit, sclop.info, sclop.provider, sclop.context_window }
		local ends, summary = 0, nil
		local function oncompact(s) summary = s end
		local h
		h = function()
			ends = ends + 1
			if ends < turns then
				return
			end
			sclop.events.unsubscribe(sclop.events.TURN_END, h)
			sclop.events.unsubscribe(sclop.events.COMPACT, oncompact)
			sclop.commit, sclop.info, sclop.provider, sclop.context_window = saved[1], saved[2], saved[3], saved[4]
			local ok, err = pcall(check, summary, sclop.agent.messages)
			sclop.agent.clear()
			done(not ok and err or nil)
		end
		sclop.commit, sclop.info, sclop.provider = function() end, function() end, 'counter'
		sclop.events.subscribe(sclop.events.TURN_END, h)
		sclop.events.subscribe(sclop.events.COMPACT, oncompact)
		sclop.agent.clear()
		fn()
	end)
end

compaction_test('compact swaps the conversation for a summary', 1, function()
	sclop.agent.messages = { text('user', 'a'), text('assistant', 'b') }
	assert(sclop.agent.compact())
end, function(summary, m)
	eq(summary, 'S: 3')
	eq(#m, 2)
	assert(m[1].content[1].text:find('S: 3', 1, true))
end)

compaction_test('a full context compacts by itself', 2, function()
	sclop.context_window = 10
	sclop.agent.submit('x')
end, function(summary, m)
	eq(summary, 'S: 3')
	eq(#m, 2)
end)
