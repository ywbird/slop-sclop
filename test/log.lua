-- sclog: a session file as plaintext
local util = require('sclop.util')
local log = require('sclop.log')

local json = sclop.json
local dir = os.tmpname()
os.remove(dir)
os.execute('mkdir -p ' .. util.quote(dir))

local function session(name, entries)
	local path = dir .. '/' .. name
	local f = assert(io.open(path, 'w'))
	for _, e in ipairs(entries) do
		f:write(json.encode(e), '\n')
	end
	f:close()
	return path
end

local function text(role, t)
	return { role = role, content = { { type = 'text', text = t } } }
end

local path = session('one.jsonl', {
	{ type = 'session', model = 'p/m', cwd = '/w' },
	text('user', 'hello\nthere'),
	{ role = 'assistant', content = {
		{ type = 'thinking', thinking = 'hmm\nthen' },
		{ type = 'text', text = 'sure' },
		{ type = 'tool_call', id = 'a', name = 'bash', args = { command = 'ls' } },
		{ type = 'tool_call', id = 'b', name = 'bash', args = { command = 'pwd' } },
	} },
	{ role = 'user', content = {
		{ type = 'tool_result', id = 'a', content = { { type = 'text', text = '1\n2\n3\n4\n5' } } },
		{ type = 'tool_result', id = 'b', content = { { type = 'text', text = '/w' } } },
	} },
	{ role = 'assistant', content = { { type = 'text', text = 'done' } } },
})

test('the default is the conversation alone', function()
	local got = assert(log.render(path, {}))
	eq(got, 'p/m · /w\n\n> hello\n  there\n\nsure\n\ndone\n')
end)

test('--thinking adds thinking blocks', function()
	local got = assert(log.render(path, { thinking = true }))
	assert(got:find('∴ hmm\n  then', 1, true), got)
	assert(not got:find('● bash', 1, true), got)
end)

test('--tools adds calls with three lines of their result', function()
	local got = assert(log.render(path, { tools = true }))
	assert(got:find('● bash ls\n  ⎿ 1\n    2\n    3\n    … 2 more lines', 1, true), got)
	assert(got:find('● bash pwd\n  ⎿ /w', 1, true), got)
	assert(not got:find('∴', 1, true), got)
end)

test('--verbose shows the whole result', function()
	local got = assert(log.render(path, { tools = true, verbose = true }))
	assert(got:find('  ⎿ 1\n    2\n    3\n    4\n    5', 1, true), got)
	assert(not got:find('more lines', 1, true), got)
end)

test('--all is thinking, tools and verbose', function()
	local got = assert(log.render(path, { thinking = true, tools = true, verbose = true }))
	assert(got:find('∴ hmm', 1, true), got)
	assert(got:find('    5', 1, true), got)
	assert(not got:find('more lines', 1, true), got)
end)

test('a result without its call is not invented', function()
	local p = session('orphan.jsonl', {
		{ type = 'session', model = 'p/m', cwd = '/w' },
		{ role = 'user', content = { { type = 'tool_result', id = 'x', content = 'orphan' } } },
	})
	local got = assert(log.render(p, { tools = true }))
	eq(got, 'p/m · /w\n')
end)

test('a compact line is shown as a break', function()
	local p = session('compact.jsonl', {
		{ type = 'session', model = 'p/m', cwd = '/w' },
		text('user', 'before'),
		{ type = 'compact', summary = 'SUM' },
		text('user', 'after'),
	})
	local got = assert(log.render(p, {}))
	eq(got, 'p/m · /w\n\n> before\n\n── compacted ──\nSUM\n\n> after\n')
end)

test('an unreadable file is an error', function()
	local got, err = log.render(dir .. '/nope.jsonl', {})
	eq(got, nil)
	assert(err:find('nope.jsonl', 1, true), err)
end)

test('bad arguments are refused', function()
	local saved = io.stderr
	local errs = {}
	io.stderr = { write = function(_, ...) errs[#errs + 1] = table.concat({ ... }) end }
	local nofile = log.main{}
	local extra = log.main{ 'a.jsonl', 'b.jsonl' }
	local flag = log.main{ '--nope', 'a.jsonl' }
	local missing = log.main{ dir .. '/nope.jsonl' }
	io.stderr = saved
	eq(nofile, 1)
	eq(extra, 1)
	eq(flag, 1)
	eq(missing, 1)
	eq(#errs, 4)
	assert(errs[1]:find('usage', 1, true), errs[1])
	assert(errs[2]:find('one file', 1, true), errs[2])
	assert(errs[3]:find('unknown option --nope', 1, true), errs[3])
	assert(errs[4]:find('nope.jsonl', 1, true), errs[4])
end)
