-- sclop runtime: the global `sclop` object
local core = require('sclop.core')

local sclop = { core = core, version = core.version }
_G.sclop = sclop

-- LuaJIT lacks Lua 5.3's utf8 library; enough of it for plugins
if not utf8 then
	utf8 = { charpattern = '[%z\1-\127\194-\244][\128-\191]*' }
	function utf8.char(...)
		local out = {}
		for i, c in ipairs{ ... } do
			if c < 0x80 then
				out[i] = string.char(c)
			elseif c < 0x800 then
				out[i] = string.char(0xc0 + math.floor(c / 0x40), 0x80 + c % 0x40)
			elseif c < 0x10000 then
				out[i] = string.char(0xe0 + math.floor(c / 0x1000), 0x80 + math.floor(c / 0x40) % 0x40, 0x80 + c % 0x40)
			else
				out[i] = string.char(0xf0 + math.floor(c / 0x40000), 0x80 + math.floor(c / 0x1000) % 0x40,
					0x80 + math.floor(c / 0x40) % 0x40, 0x80 + c % 0x40)
			end
		end
		return table.concat(out)
	end
	function utf8.codepoint(s, i)
		i = i or 1
		local c = s:byte(i)
		if not c or c < 0x80 then
			return c
		end
		local n = c >= 0xf0 and 3 or c >= 0xe0 and 2 or 1
		local cp = c % 2 ^ (6 - n)
		for j = 1, n do
			cp = cp * 64 + (s:byte(i + j) or 0) % 64
		end
		return cp
	end
	function utf8.len(s)
		return select(2, s:gsub('[^\128-\191]', ''))
	end
end

-- settings
sclop.provider = 'anthropic'
sclop.model = 'claude-sonnet-4-5'
sclop.max_tokens = 16384
sclop.context_window = 200000
sclop.compact_at = 0.8
sclop.skills = { '~/.agents/skills', '.agents/skills' }
sclop.permissions = {
	['*'] = 'allow',
	read = function(args)
		local p = args.path or ''
		if p:match('%.env$') or (p:match('%.env%.') and not p:match('%.env%.example$')) then
			return 'ask'
		end
		return 'allow'
	end,
}
sclop.providers = {}
sclop.tools = setmetatable({}, { __index = {
	register = function(t)
		sclop.tools[t.name] = t
	end,
} })
sclop.system = [[
You are sclop, a minimal coding agent running in the user's terminal.
You help with software engineering: reading, writing and editing code, and running commands.

- Look at files before you change them. Prefer small, focused edits.
- Run commands to check your work when it helps.
- Keep answers short and direct. The terminal shows plain text, so avoid heavy markdown.
- Ask before doing anything destructive or irreversible.
- Skills available to you are listed in the skill tool's description. Answer from that list; do not scan skill directories unless the user asks you to.]]

local ffi = require('ffi')
ffi.cdef('char *getcwd(char *buf, size_t size);')
local cwd = ffi.C.getcwd(ffi.new('char[4096]'), 4096)
sclop.cwd = cwd ~= nil and ffi.string(cwd) or os.getenv('PWD') or '.'
sclop.platform = jit.os .. '/' .. jit.arch

sclop.json = {
	encode = core.json_encode,
	decode = core.json_decode,
	null = core.null,
	array = function(t)
		return setmetatable(t or {}, core.array_mt)
	end,
}

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
	COMPACT = 'compact',
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

-- styles
local function sgr(code)
	return function(s)
		return '\27[' .. code .. 'm' .. s .. '\27[0m'
	end
end

sclop.style = {
	bold = sgr(1), dim = sgr(2), italic = sgr(3),
	red = sgr(31), green = sgr(32), yellow = sgr(33), blue = sgr(34),
	magenta = sgr(35), cyan = sgr(36), gray = sgr(90),
}

-- async helpers
function sclop.timer(ms, fn, rep)
	local id = core.timer(ms, fn, rep)
	return { stop = function() core.timer_stop(id) end }
end

function sclop.spawn(opts)
	local id, err = core.spawn(opts)
	if not id then
		return nil, err
	end
	return {
		write = function(_, s) return core.proc_write(id, s) end,
		close = function() core.proc_close(id) end,
		kill = function(_, sig) core.proc_kill(id, sig) end,
	}
end

function sclop.http(opts)
	local id, err = core.http(opts)
	if not id then
		return nil, err
	end
	return { cancel = function() core.http_cancel(id) end }
end

-- screen
local dirty = true

function sclop.redraw()
	dirty = true
end

function sclop.commit(text)
	core.commit(text)
	dirty = true
end

function sclop.info(text)
	sclop.commit(sclop.style.dim(text))
end

function sclop.error(text)
	if sclop.term then
		sclop.commit(sclop.style.red(text))
	else
		io.stderr:write('sclop: ', text, '\n')
	end
end

function sclop.quit(code)
	core.quit(code or 0)
end

-- modes and keymaps
sclop.modes = { INPUT = 'input', ASK = 'ask' }
sclop.mode = sclop.modes.INPUT
sclop.defaults = {} -- mode -> handler for unmapped keys
local maps = {}

function sclop:map(mode, key, action, help)
	maps[mode] = maps[mode] or {}
	maps[mode][key] = action
	return help
end

function sclop:unmap(mode, key)
	if maps[mode] then
		maps[mode][key] = nil
	end
end

function sclop:mappings(mode)
	local t = {}
	for k, v in pairs(maps[mode] or {}) do
		t[k] = v
	end
	return t
end

function sclop:feedkeys(bytes)
	core.feed(bytes)
end

function sclop:dokey(key, depth)
	local action = maps[self.mode] and maps[self.mode][key]
	if type(action) == 'string' and (depth or 0) < 8 then
		return self:dokey(action, (depth or 0) + 1)
	end
	if type(action) == 'function' then
		action(key)
	elseif self.defaults[self.mode] then
		self.defaults[self.mode](key)
	end
	dirty = true
end

-- commands
local commands = {}

function sclop:command_register(name, fn, help)
	commands[name] = { fn = fn, help = help }
end

function sclop:command(line)
	local name, args = line:match('^/(%S+)%s*(.-)%s*$')
	local c = name and commands[name]
	if not c then
		return false
	end
	c.fn(args)
	return true
end

-- input text: plugins, then commands, then the agent. true if it was taken.
function sclop.submit(text)
	if sclop.events.emit(sclop.events.SUBMIT, text) then
		return true
	end
	if text:match('^/') and sclop:command(text) then
		return true
	end
	if sclop.agent.busy then
		return false
	end
	sclop.agent.submit(text)
	return true
end

function sclop.set_model(spec)
	local p, m = spec:match('^([^/]+)/(.+)$')
	if p and sclop.providers[p] then
		sclop.provider, sclop.model = p, m
	else
		sclop.model = spec
	end
end

core.dispatch = function(ev, a, b)
	if ev == 'key' then
		if not sclop.events.emit(sclop.events.KEY, a) then
			sclop:dokey(a)
		end
		dirty = true
	elseif ev == 'paste' then
		if not sclop.events.emit(sclop.events.PASTE, a) and sclop.mode == sclop.modes.INPUT then
			sclop.input:insert((a:gsub('\r\n?', '\n')))
		end
		dirty = true
	elseif ev == 'resize' then
		sclop.events.emit(sclop.events.RESIZE, a, b)
		dirty = true
	elseif ev == 'draw' then
		sclop.events.emit(sclop.events.DRAW)
		if dirty and sclop.term then
			dirty = false
			core.draw(sclop.view.render())
		end
	elseif ev == 'error' then
		sclop.events.emit(sclop.events.ERROR, a)
		sclop.error(a)
	elseif ev == 'quit' then
		sclop.events.emit(sclop.events.QUIT)
	end
end

sclop.util = require('sclop.util')
sclop.input = require('sclop.editor').new()
sclop.view = require('sclop.view')
sclop.agent = require('sclop.agent')
sclop.session = require('sclop.session')
sclop.providers.anthropic = require('sclop.providers.anthropic').new()
sclop.providers.openai = require('sclop.providers.openai').new()
for _, name in ipairs{ 'read', 'write', 'edit', 'bash', 'grep', 'glob', 'skill' } do
	require('sclop.tools.' .. name)
end

sclop:command_register('quit', function() sclop.quit() end, 'exit')
sclop:command_register('clear', function()
	sclop.agent.clear()
	sclop.session.reset()
	sclop.info('new conversation')
end, 'start a new conversation')
sclop:command_register('compact', function()
	if not sclop.agent.compact() then
		sclop.info('nothing to compact right now')
	end
end, 'summarize the conversation to free context')
sclop:command_register('model', function(args)
	if args ~= '' then
		sclop.set_model(args)
	end
	sclop.info('model: ' .. sclop.provider .. '/' .. sclop.model)
end, 'show or set the model: /model [provider/]model')
sclop:command_register('help', function()
	local names = {}
	for name in pairs(commands) do
		names[#names + 1] = name
	end
	table.sort(names)
	for i, name in ipairs(names) do
		names[i] = string.format('/%-10s %s', name, commands[name].help or '')
	end
	sclop.info(table.concat(names, '\n'))
end, 'list commands')

-- main

local usage = 'usage: sclop [-c [session]] [-m model] [-p [prompt] [--allow-TOOL | --allow-all]] [-v]\n'
	.. '       sclop -l file.lua [args...]\n'

-- -p: answer one prompt on stdout, without a terminal; 'ask' means deny unless allowed
local function printmode(prompt, allow)
	if prompt == '-' then
		prompt = io.read('*a')
	end
	if not prompt or prompt:match('^%s*$') then
		io.stderr:write('sclop: the prompt is empty\n')
		return sclop.quit(1)
	end
	sclop.commit, sclop.info = function() end, function() end
	sclop.agent.ask = function(call, answer)
		local ok = allow.all or allow[call.name]
		if not ok then
			io.stderr:write('sclop: denied ', call.name, ' (allow it with --allow-', call.name, ')\n')
		end
		answer(ok and 'y' or 'n')
	end
	sclop.events.subscribe(sclop.events.TURN_END, function()
		local last = sclop.agent.messages[#sclop.agent.messages]
		if not last or last.role ~= 'assistant' then
			return sclop.quit(1)
		end
		local text = {}
		for _, b in ipairs(last.content) do
			if b.type == 'text' then
				text[#text + 1] = b.text
			end
		end
		io.write(table.concat(text), '\n')
		io.stdout:flush()
		sclop.quit(0)
	end)
	sclop.agent.submit(prompt)
end

local function loadconfig()
	local base = os.getenv('XDG_CONFIG_HOME')
	if not base or base == '' then
		base = (os.getenv('HOME') or '') .. '/.config'
	end
	local path = base .. '/sclop/init.lua'
	local f = io.open(path)
	if not f then
		return
	end
	f:close()
	local ok, err = pcall(dofile, path)
	if not ok then
		return 'config: ' .. tostring(err)
	end
end

local function ispath(a)
	return a ~= nil and a:sub(1, 1) ~= '-'
end

function sclop.main()
	local i, model, continue, prompt, allow = 1, nil, nil, nil, {}
	while arg[i] do
		local a = arg[i]
		if a == '-c' then
			continue = true
			if ispath(arg[i + 1]) then
				continue = arg[i + 1]
				i = i + 1
			end
		elseif a == '-p' then
			local nxt = arg[i + 1]
			prompt = '-'
			if nxt and (nxt == '-' or nxt:sub(1, 1) ~= '-') then
				prompt = nxt
				i = i + 1
			end
		elseif a:match('^%-%-allow%-.') then
			allow[a:sub(9)] = true
		elseif a == '-v' then
			print('sclop ' .. sclop.version)
			return sclop.quit()
		elseif a == '-l' and arg[i + 1] then
			local chunk = assert(loadfile(arg[i + 1]))
			return chunk(unpack(arg, i + 2))
		elseif a == '-m' and arg[i + 1] then
			model = arg[i + 1]
			i = i + 1
		else
			io.stderr:write(usage)
			return sclop.quit(a == '-h' and 0 or 1)
		end
		i = i + 1
	end
	local err = loadconfig()
	if model then
		sclop.set_model(model)
	end
	sclop.session.enable()
	local resumed, count
	if continue then
		resumed, count = sclop.session.resume(continue ~= true and continue or nil)
	end
	if prompt then
		if err then
			sclop.error(err)
		end
		if continue and not resumed then
			sclop.error(count)
			return sclop.quit(1)
		end
		return printmode(prompt, allow)
	end
	local ok, terr = core.term_start()
	if not ok then
		io.stderr:write('sclop: ', terr, '\n')
		return sclop.quit(1)
	end
	sclop.term = true
	if err then
		sclop.error(err)
	end
	if resumed then
		sclop.view.replay(sclop.agent.messages)
		sclop.info(string.format('continuing %s (%d messages)', resumed, count))
	elseif continue then
		sclop.error(count)
	end
	sclop.events.emit(sclop.events.START)
end

return sclop
