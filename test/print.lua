-- sclop -p, run as a child with a config whose provider asks for one bash call
local util = require('sclop.util')

local exe = os.getenv('PWD') .. '/sclop'
local dir = os.tmpname()
os.remove(dir)
os.execute('mkdir -p ' .. util.quote(dir .. '/sclop'))
local f = io.open(dir .. '/sclop/init.lua', 'w')
f:write([[
sclop.permissions.bash = 'ask'
sclop.provider = 'fake'
sclop.providers.fake = {
	stream = function(_, req, h)
		local last = req.messages[#req.messages].content[1]
		local reply = last.type == 'tool_result'
			and { { type = 'text', text = 'result: ' .. last.content } }
			or { { type = 'tool_call', id = 't', name = 'bash', args = { command = 'echo ran' } } }
		sclop.timer(1, function() h.done({ role = 'assistant', content = reply }, { input = 1, output = 1 }) end)
		return { cancel = function() end }
	end,
}
]])
f:close()

local function sclop_p(args, stdin, check, done)
	local out, err = {}, {}
	local argv = { 'env', 'XDG_CONFIG_HOME=' .. dir, exe }
	for _, a in ipairs(args) do
		argv[#argv + 1] = a
	end
	sclop.spawn{
		argv = argv,
		cwd = dir,
		stdin = stdin,
		on_stdout = function(d) out[#out + 1] = d end,
		on_stderr = function(d) err[#err + 1] = d end,
		on_exit = function(code)
			local ok, e = pcall(check, table.concat(out), table.concat(err), code)
			done(not ok and e or nil)
		end,
	}
end

atest('-p denies ask by default', function(done)
	sclop_p({ '-p', 'go' }, nil, function(out, err, code)
		eq(out, 'result: the user denied permission\n')
		eq(err, 'sclop: denied bash (allow it with --allow-bash)\n')
		eq(code, 0)
	end, done)
end)

atest('-p --allow-bash runs it', function(done)
	sclop_p({ '-p', 'go', '--allow-bash' }, nil, function(out, _, code)
		eq(out, 'result: ran\n')
		eq(code, 0)
	end, done)
end)

atest('-p reads the prompt from stdin', function(done)
	sclop_p({ '-p', '--allow-all' }, 'go\n', function(out, _, code)
		eq(out, 'result: ran\n')
		eq(code, 0)
	end, done)
end)

atest('-p -c continues the session', function(done)
	sclop_p({ '-c', '-p', 'more', '--allow-all' }, nil, function(out, _, code)
		eq(out, 'result: ran\n')
		eq(code, 0)
		local p = io.popen('ls -1 ' .. util.quote(dir .. '/.sclop/sessions'))
		local files = p:read('*a')
		p:close()
		eq(select(2, files:gsub('\n', '')), 3)
	end, done)
end)

atest('-p -c PATH continues that session file', function(done)
	local p = io.popen('ls -1t ' .. util.quote(dir .. '/.sclop/sessions'))
	local name = p:read('*l')
	p:close()
	local path = dir .. '/.sclop/sessions/' .. name
	local before = io.open(path):read('*a')
	sclop_p({ '-c', path, '-p', 'more', '--allow-all' }, nil, function(out, _, code)
		eq(out, 'result: ran\n')
		eq(code, 0)
		local after = io.open(path):read('*a')
		assert(#after > #before, 'the given session file did not grow')
		local files = io.popen('ls -1 ' .. util.quote(dir .. '/.sclop/sessions')):read('*a')
		eq(select(2, files:gsub('\n', '')), 3) -- no new session file
	end, done)
end)

atest('-p -c PATH fails on a missing file', function(done)
	sclop_p({ '-c', dir .. '/nope.jsonl', '-p', 'more' }, nil, function(out, err, code)
		eq(out, '')
		assert(err:find('no such session file', 1, true), err)
		eq(code, 1)
	end, done)
end)
