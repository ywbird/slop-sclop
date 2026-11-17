local util = require('sclop.util')

local dir = os.tmpname()
os.remove(dir)
os.execute('mkdir -p ' .. util.quote(dir))

local function run(name, args)
	local r
	sclop.tools[name].run(args, function(text, is_error) r = { text, is_error } end, function() end)
	return r[1], r[2]
end

local function arun(name, args, check, done)
	sclop.tools[name].run(args, function(text, is_error)
		local ok, err = pcall(check, text, is_error)
		done(not ok and err or nil)
	end, function() end)
end

test('write creates directories and read numbers lines', function()
	local _, err = run('write', { path = dir .. '/a/b.txt', content = 'one\ntwo\nthree\n' })
	eq(err, nil)
	eq(run('read', { path = dir .. '/a/b.txt', offset = 2, limit = 1 }),
		'     2\ttwo\n(lines 2-2 of 3, read on with offset=3)')
	eq(run('read', { path = dir .. '/a/b.txt' }), '     1\tone\n     2\ttwo\n     3\tthree')
end)

test('read lists directories and refuses binaries', function()
	assert(run('read', { path = dir }):find('a/', 1, true))
	local f = io.open(dir .. '/bin', 'wb')
	f:write('ab\0cd')
	f:close()
	local _, err = run('read', { path = dir .. '/bin' })
	eq(err, true)
end)

test('edit replaces exactly one match', function()
	local p = dir .. '/e.txt'
	run('write', { path = p, content = 'x = 1\ny = 1\n' })
	local text, err = run('edit', { path = p, old_string = '= 1', new_string = '= 2' })
	eq(err, true)
	assert(text:find('2 times'), text)
	eq(select(2, run('edit', { path = p, old_string = 'nope', new_string = 'x' })), true)
	eq(run('edit', { path = p, old_string = 'y = 1', new_string = 'y = 3' }), 'edited ' .. p .. ' (1 replacement)')
	eq(run('edit', { path = p, old_string = ' = ', new_string = ':', replace_all = true }),
		'edited ' .. p .. ' (2 replacements)')
	eq(io.open(p):read('*a'), 'x:1\ny:3\n')
end)

atest('bash merges output and reports the exit code', function(done)
	arun('bash', { command = 'echo hi; echo err >&2; exit 3' }, function(text, is_error)
		eq(text, 'hi\nerr\n(exit code 3)')
		eq(is_error, false)
	end, done)
end)

atest('bash timeout kills the command', function(done)
	local t = sclop.core.now()
	arun('bash', { command = 'sleep 5', timeout = 100 }, function(text, is_error)
		eq(text, '(killed after 100 ms)')
		eq(is_error, true)
		assert(sclop.core.now() - t < 2000, 'took too long')
	end, done)
end)

atest('bash does not wait for background children', function(done)
	local t = sclop.core.now()
	arun('bash', { command = 'sleep 3 & echo started' }, function(text)
		eq(text, 'started')
		assert(sclop.core.now() - t < 1500, 'waited for the background job')
	end, done)
end)

atest('grep finds lines', function(done)
	arun('grep', { pattern = 'tw.', path = dir }, function(text)
		assert(text:find('b.txt:2:two', 1, true), text)
	end, done)
end)

atest('glob finds files', function(done)
	arun('glob', { pattern = '*.txt', path = dir }, function(text)
		assert(text:find('a/b.txt', 1, true), text)
		assert(text:find('e.txt', 1, true), text)
	end, done)
end)

test('skills are found and loaded', function()
	os.execute('mkdir -p ' .. util.quote(dir .. '/skills/foo'))
	local f = io.open(dir .. '/skills/foo/SKILL.md', 'w')
	f:write('---\nname: foo\ndescription: >\n  does foo\n  well\n---\nBody of foo.\n')
	f:close()
	local saved = sclop.skills
	sclop.skills = { dir .. '/skills' }
	require('sclop.tools.skill').reload()
	local list = sclop.agent.tool_list()
	sclop.skills = saved
	local desc
	for _, t in ipairs(list) do
		if t.name == 'skill' then
			desc = t.description
		end
	end
	assert(desc and desc:find('- foo: does foo well', 1, true), tostring(desc))
	assert(run('skill', { name = 'foo' }):find('Body of foo.', 1, true))
	require('sclop.tools.skill').reload()
end)

test('read asks for .env files', function()
	eq(sclop.agent.decide({ name = 'read', args = { path = 'a/.env' } }), 'ask')
	eq(sclop.agent.decide({ name = 'read', args = { path = '.env.local' } }), 'ask')
	eq(sclop.agent.decide({ name = 'read', args = { path = '.env.example' } }), 'allow')
	eq(sclop.agent.decide({ name = 'bash', args = {} }), 'allow')
end)

-- the agent loop with a provider that replays canned replies
local replies = {}
sclop.providers.fake = {
	stream = function(_, _, h)
		local r = table.remove(replies, 1)
		local t = sclop.timer(10, function()
			h.done({ role = 'assistant', content = r }, { input = 1, output = 1 })
		end)
		return { cancel = function() t:stop() end }
	end,
}

local function agent_test(name, setup, check)
	atest(name, function(done)
		local saved = { sclop.commit, sclop.info, sclop.provider }
		local h
		h = function()
			sclop.events.unsubscribe(sclop.events.TURN_END, h)
			sclop.commit, sclop.info, sclop.provider = saved[1], saved[2], saved[3]
			sclop.permissions.bash = nil
			local ok, err = pcall(check, sclop.agent.messages)
			done(not ok and err or nil)
		end
		sclop.commit, sclop.info, sclop.provider = function() end, function() end, 'fake'
		sclop.events.subscribe(sclop.events.TURN_END, h)
		sclop.agent.clear()
		setup()
	end)
end

local function bash_call(cmd)
	return { { type = 'tool_call', id = 't1', name = 'bash', args = { command = cmd } } }
end

agent_test('agent runs tool calls, then asks again', function()
	replies = { bash_call('echo hello'), { { type = 'text', text = 'done' } } }
	sclop.agent.submit('go')
end, function(m)
	eq(#m, 4)
	eq(m[3].content[1].type, 'tool_result')
	eq(m[3].content[1].content, 'hello')
	eq(m[4].content[1].text, 'done')
end)

agent_test('ask mode waits for the answer', function()
	sclop.permissions.bash = 'ask'
	replies = { bash_call('echo no'), { { type = 'text', text = 'ok' } } }
	local poll
	poll = sclop.timer(5, function()
		if sclop.agent.asking then
			poll:stop()
			sclop:feedkeys('n')
		end
	end, true)
	sclop.agent.submit('go')
end, function(m)
	eq(m[3].content[1].content, 'the user denied permission')
	eq(m[3].content[1].is_error, true)
	eq(sclop.mode, sclop.modes.INPUT)
end)

agent_test('interrupting a tool fills in its result', function()
	replies = { bash_call('sleep 5') }
	sclop.agent.submit('go')
	local poll
	poll = sclop.timer(5, function()
		if sclop.agent.running then
			poll:stop()
			sclop.agent.abort()
		end
	end, true)
end, function(m)
	eq(#m, 3)
	eq(m[3].content[1].content, 'interrupted by the user')
	eq(sclop.agent.busy, false)
end)
