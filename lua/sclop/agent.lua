-- agent: the conversation loop
local A = { busy = false, messages = {}, tokens = 0, partial = '' }

local request, ticker
local streamed -- text of the reply being streamed, kept if it is interrupted

local function view()
	return sclop.view
end

function A.system_prompt()
	return string.format('%s\n\nEnvironment:\n- Working directory: %s\n- Platform: %s\n- Date: %s',
		sclop.system, sclop.cwd, sclop.platform, os.date('%Y-%m-%d'))
end

function A.tool_list()
	return {}
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
	request = nil
	if ticker then
		ticker:stop()
		ticker = nil
	end
	sclop.events.emit(sclop.events.TURN_END)
	sclop.redraw()
end

local function turn()
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

-- what to do once a reply is complete; the tool loop hooks in here
function A.after(msg)
	stop()
end

function A.submit(text)
	sclop.commit(view().user(text))
	A.push({ role = 'user', content = { { type = 'text', text = text } } })
	A.busy = true
	ticker = sclop.timer(100, sclop.redraw, true)
	turn()
end

A.turn = turn

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
	sclop.info('interrupted')
	stop()
end

function A.clear()
	A.messages = {}
	A.tokens = 0
end

return A
