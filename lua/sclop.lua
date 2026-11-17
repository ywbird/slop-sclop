-- sclop runtime: the global `sclop` object
local core = require('sclop.core')

local sclop = { core = core, version = core.version }
_G.sclop = sclop

-- events: same contract as vis.events
local handlers = {}

sclop.events = {
	START = 'start',
	QUIT = 'quit',
	KEY = 'key',
	PASTE = 'paste',
	RESIZE = 'resize',
	DRAW = 'draw',
	STATUS = 'status',
	SUBMIT = 'submit',
	MESSAGE = 'message',
	STREAM = 'stream',
	TOOL_CALL = 'tool_call',
	TOOL_RESULT = 'tool_result',
	TURN_END = 'turn_end',
	ERROR = 'error',
}

function sclop.events.subscribe(ev, fn)
	handlers[ev] = handlers[ev] or {}
	table.insert(handlers[ev], fn)
end

function sclop.events.unsubscribe(ev, fn)
	for i, h in ipairs(handlers[ev] or {}) do
		if h == fn then
			table.remove(handlers[ev], i)
			return true
		end
	end
	return false
end

function sclop.events.emit(ev, ...)
	local h = handlers[ev]
	if not h then
		return
	end
	for i = 1, #h do
		local r = h[i](...)
		if r ~= nil then
			return r
		end
	end
end

-- async helpers

function sclop.timer(ms, fn, rep)
	local id = core.timer(ms, fn, rep)
	return { stop = function() core.timer_stop(id) end }
end

function sclop.quit(code)
	core.quit(code or 0)
end

function sclop.error(text)
	io.stderr:write('sclop: ', text, '\n')
end

core.dispatch = function(ev, a)
	if ev == 'error' then
		sclop.events.emit(sclop.events.ERROR, a)
		sclop.error(a)
	elseif ev == 'quit' then
		sclop.events.emit(sclop.events.QUIT)
	end
end

local usage = 'usage: sclop [-v] [-h] [-l file.lua [args...]]\n'

function sclop.main()
	local a = arg[1]
	if a == '-v' then
		print('sclop ' .. sclop.version)
		return sclop.quit()
	elseif a == '-l' and arg[2] then
		local chunk = assert(loadfile(arg[2]))
		return chunk(unpack(arg, 3))
	elseif a then
		io.stderr:write(usage)
		return sclop.quit(a == '-h' and 0 or 1)
	end
	io.stderr:write('sclop: interactive mode is not built yet\n')
	sclop.quit(1)
end

return sclop
