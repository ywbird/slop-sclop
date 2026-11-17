-- agent: the conversation loop, tool calls and permissions
local A = { busy = false, messages = {}, tokens = 0, partial = '' }

local request, ticker, pending
local streamed -- text of the reply being streamed, kept if it is interrupted

local function view()
	return sclop.view
end

function A.system_prompt()
	return string.format('%s\n\nEnvironment:\n- Working directory: %s\n- Platform: %s\n- Date: %s',
		sclop.system, sclop.cwd, sclop.platform, os.date('%Y-%m-%d'))
end

-- tools offered to the model, sorted so the request prefix stays cacheable
function A.tool_list()
	local names, list = {}, {}
	for name, t in pairs(sclop.tools) do
		if not t.available or t.available() then
			names[#names + 1] = name
		end
	end
	table.sort(names)
	for i, name in ipairs(names) do
		local t = sclop.tools[name]
		local d = t.description
		list[i] = { name = name, description = type(d) == 'function' and d() or d, schema = t.schema }
	end
	return list
end

function A.push(msg)
	A.messages[#A.messages + 1] = msg
	sclop.events.emit(sclop.events.MESSAGE, msg)
end

local function settle_thinking()
	if A.thinking then
		sclop.commit(view().thought(sclop.core.now() - A.thinking_start))
		A.thinking = nil
	end
end

local function flush_partial()
	if A.partial ~= '' then
		sclop.commit(view().assistant(A.partial))
		A.partial = ''
	end
end

local function stop()
	A.busy = false
	request, pending = nil, nil
	if ticker then
		ticker:stop()
		ticker = nil
	end
	sclop.events.emit(sclop.events.TURN_END)
	sclop.redraw()
end

local turn

-- permission for a call: an event handler, then sclop.permissions
function A.decide(call)
	local d = sclop.events.emit(sclop.events.TOOL_CALL, call)
	if d then
		return d
	end
	local p = sclop.permissions[call.name]
	if p == nil then
		p = sclop.permissions['*']
	end
	if type(p) == 'function' then
		p = p(call.args or {})
	end
	return p or 'allow'
end

local function run_tool(call, done)
	local tool = sclop.tools[call.name]
	sclop.commit(view().tool(call, tool))
	if not tool then
		return done('there is no tool named ' .. tostring(call.name), true)
	end
	local function finish(text, is_error)
		A.running = nil
		sclop.commit(view().result(call, text, is_error, tool))
		done(text, is_error)
	end
	local function execute()
		local finished, running = false, { call = call, output = '' }
		A.running = running
		local ok, cancel = pcall(tool.run, call.args or {}, function(text, is_error)
			if not finished and A.running == running then -- not interrupted
				finished = true
				A.cancel = nil
				finish(tostring(text), is_error)
			end
		end, function(output)
			if A.running == running then
				running.output = output
				sclop.redraw()
			end
		end)
		if not ok and finished then
			return sclop.error(tostring(cancel)) -- raised after the tool was done
		elseif not ok then
			finished = true
			return finish('the tool failed: ' .. tostring(cancel), true)
		end
		if not finished then
			A.cancel = cancel
		end
	end
	local d = A.decide(call)
	if d == 'deny' then
		return finish('permission denied by the user\'s settings', true)
	elseif d == 'ask' then
		A.asking = call
		sclop.mode = sclop.modes.ASK
		A.answer = function(answer)
			A.asking, A.answer = nil, nil
			sclop.mode = sclop.modes.INPUT
			if answer == 'n' then
				return finish('the user denied permission', true)
			end
			if answer == 'a' then
				sclop.permissions[call.name] = 'allow'
			end
			execute()
		end
		sclop.redraw()
		return
	end
	execute()
end

-- after a reply: run its tool calls in order, then ask again; else the turn is over
function A.after(msg)
	local calls = {}
	for _, b in ipairs(msg.content) do
		if b.type == 'tool_call' then
			calls[#calls + 1] = b
		end
	end
	if #calls == 0 then
		return stop()
	end
	local p = { calls = calls, results = {} }
	pending = p
	local function nextcall()
		if pending ~= p then
			return -- interrupted
		end
		local call = calls[#p.results + 1]
		if not call then
			pending = nil
			A.push({ role = 'user', content = p.results })
			return turn()
		end
		run_tool(call, function(text, is_error)
			if pending ~= p then
				return
			end
			p.results[#p.results + 1] = { type = 'tool_result', id = call.id, content = text, is_error = is_error }
			sclop.events.emit(sclop.events.TOOL_RESULT, call, text, is_error)
			nextcall()
		end)
	end
	nextcall()
end

function turn()
	local provider = sclop.providers[sclop.provider]
	if not provider then
		sclop.error('unknown provider: ' .. tostring(sclop.provider))
		return stop()
	end
	streamed = {}
	request = provider:stream({
		model = sclop.model,
		system = A.system_prompt(),
		messages = A.messages,
		tools = A.tool_list(),
		max_tokens = sclop.max_tokens,
	}, {
		thinking = function(delta)
			if not A.thinking then
				A.thinking, A.thinking_start = '', sclop.core.now()
			end
			A.thinking = A.thinking .. delta
			sclop.events.emit(sclop.events.STREAM, 'thinking', delta)
			sclop.redraw()
		end,
		text = function(delta)
			settle_thinking()
			streamed[#streamed + 1] = delta
			A.partial = A.partial .. delta
			local lines, rest = A.partial:match('^(.*)\n(.-)$')
			if lines then
				sclop.commit(view().assistant(lines))
				A.partial = rest
			end
			sclop.events.emit(sclop.events.STREAM, 'text', delta)
			sclop.redraw()
		end,
		done = function(msg, usage)
			request = nil
			settle_thinking()
			flush_partial()
			A.tokens = usage.input + usage.output
			if #msg.content > 0 then
				A.push(msg)
			end
			A.after(msg)
		end,
		error = function(err)
			request = nil
			settle_thinking()
			flush_partial()
			sclop.error(err)
			stop()
		end,
	})
end
A.turn = turn

function A.submit(text)
	sclop.commit(view().user(text))
	A.push({ role = 'user', content = { { type = 'text', text = text } } })
	A.busy = true
	ticker = sclop.timer(100, sclop.redraw, true)
	turn()
end

function A.abort()
	if request then
		request:cancel()
		request = nil
		settle_thinking()
		flush_partial()
		local text = table.concat(streamed)
		if text ~= '' then
			A.push({ role = 'assistant', content = { { type = 'text', text = text } } })
		end
	end
	if pending then
		local p = pending
		pending = nil
		if A.cancel then
			pcall(A.cancel)
			A.cancel = nil
		end
		A.running, A.asking, A.answer = nil, nil, nil
		sclop.mode = sclop.modes.INPUT
		for i = #p.results + 1, #p.calls do
			p.results[i] = { type = 'tool_result', id = p.calls[i].id, content = 'interrupted by the user', is_error = true }
		end
		A.push({ role = 'user', content = p.results })
	end
	sclop.info('interrupted')
	stop()
end

function A.clear()
	A.messages = {}
	A.tokens = 0
end

local K = sclop.modes.ASK
for _, key in ipairs{ 'y', 'n', 'a' } do
	sclop:map(K, key, function()
		if A.answer then
			A.answer(key)
		end
	end)
end
sclop:map(K, '<Escape>', 'n')
sclop:map(K, '<C-c>', function() A.abort() end)

return A
