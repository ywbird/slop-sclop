-- sessions: the conversation goes to .sclop/sessions/<time>.jsonl in the working directory,
-- one JSON value per line: a header, then messages as they are added.
local util = require('sclop.util')
local json = sclop.json

local S = {}
local file

function S.dir()
	return sclop.cwd .. '/.sclop/sessions'
end

local function exists(path)
	local f = io.open(path)
	if f then
		f:close()
	end
	return f ~= nil
end

local function open(path)
	file = io.open(path, 'a')
	if not file then
		sclop.error('cannot write the session file ' .. path)
		return false
	end
	S.path = path
	return true
end

function S.write(entry)
	if not file then
		os.execute('mkdir -p ' .. util.quote(S.dir()))
		local ignore = sclop.cwd .. '/.sclop/.gitignore'
		if not exists(ignore) then -- sessions may hold secrets from tool output
			local f = io.open(ignore, 'w')
			if f then
				f:write('*\n')
				f:close()
			end
		end
		local base = S.dir() .. '/' .. os.date('%Y%m%d-%H%M%S')
		local path, n = base .. '.jsonl', 1
		while exists(path) do
			n = n + 1
			path = base .. '-' .. n .. '.jsonl'
		end
		if not open(path) then
			return
		end
		file:write(json.encode({ type = 'session', model = sclop.provider .. '/' .. sclop.model, cwd = sclop.cwd }), '\n')
	end
	file:write(json.encode(entry), '\n')
	file:flush()
end

-- messages of a session file
function S.load(path)
	local f = io.open(path)
	if not f then
		return nil, 'cannot open ' .. path
	end
	local msgs = {}
	for line in f:lines() do
		local e = json.decode(line)
		if e and e.role then
			msgs[#msgs + 1] = e
		elseif e and e.type == 'compact' then
			msgs = sclop.agent.summary(e.summary)
		end
	end
	f:close()
	return msgs
end

-- the most recently written session of this directory
function S.latest()
	local p = io.popen('ls -1t ' .. util.quote(S.dir()) .. ' 2>/dev/null')
	local name = p:read('*l')
	p:close()
	return name and S.dir() .. '/' .. name
end

-- continue the latest session: returns its path and message count
function S.resume()
	local path = S.latest()
	if not path then
		return nil, 'no session to continue in ' .. S.dir()
	end
	local msgs, err = S.load(path)
	if not msgs or not open(path) then
		return nil, err
	end
	sclop.agent.messages = msgs
	return path, #msgs
end

-- the next message starts a new file
function S.reset()
	if file then
		file:close()
	end
	file, S.path = nil, nil
end

function S.enable()
	sclop.events.subscribe(sclop.events.MESSAGE, S.write)
	sclop.events.subscribe(sclop.events.COMPACT, function(summary)
		S.write({ type = 'compact', summary = summary })
	end)
end

return S
