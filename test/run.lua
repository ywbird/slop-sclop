-- test runner: ./sclop -l test/run.lua [name...]
local names = { ... }
if #names == 0 then
	names = { 'loop', 'keys', 'editor', 'json', 'sse', 'providers', 'tools', 'http', 'session', 'log', 'print', 'plugins' }
end

local passed, failed, queue = 0, 0, {}

local function result(name, err)
	if err then
		failed = failed + 1
		io.stderr:write('FAIL ', name, ': ', tostring(err), '\n')
	else
		passed = passed + 1
	end
end

function test(name, fn)
	local ok, err = pcall(fn)
	result(name, not ok and err or nil)
end

-- async test: fn(done) must call done() or done(err) within 5 seconds
function atest(name, fn)
	table.insert(queue, { name = name, fn = fn })
end

function eq(got, want, what)
	if got ~= want then
		error(string.format('%s: want %q, got %q', what or 'value', tostring(want), tostring(got)), 2)
	end
end

for _, name in ipairs(names) do
	dofile('test/' .. name .. '.lua')
end

local function nextasync()
	local t = table.remove(queue, 1)
	if not t then
		print(string.format('%d passed, %d failed', passed, failed))
		return sclop.quit(failed > 0 and 1 or 0)
	end
	local finished
	local timeout = sclop.timer(5000, function()
		finished = true
		result(t.name, 'timeout')
		nextasync()
	end)
	local ok, err = pcall(t.fn, function(e)
		if finished then
			return
		end
		finished = true
		timeout:stop()
		result(t.name, e)
		sclop.timer(0, nextasync)
	end)
	if not ok and not finished then
		finished = true
		timeout:stop()
		result(t.name, err)
		sclop.timer(0, nextasync)
	end
end

nextasync()
