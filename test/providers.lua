local json = sclop.json

-- replace sclop.http with a canned response for one request
local function fake(body, status)
	local real, sent = sclop.http, nil
	sclop.http = function(opts)
		sclop.http = real
		sent = opts
		sclop.timer(0, function()
			for chunk in body:gmatch('[^\n]*\n?') do
				if chunk ~= '' then
					opts.on_data(chunk)
				end
			end
			opts.on_done(status or 200)
		end)
		return { cancel = function() end }
	end
	return function() return sent end
end

local function user(text)
	return { role = 'user', content = { { type = 'text', text = text } } }
end

local function run(provider, messages, done, check)
	local text = {}
	provider:stream({ model = 'm', system = 'sys', messages = messages, tools = {}, max_tokens = 10 }, {
		text = function(d) text[#text + 1] = d end,
		thinking = function() end,
		done = function(msg, usage)
			local ok, err = pcall(check, msg, usage, table.concat(text))
			done(not ok and err or nil)
		end,
		error = function(err)
			local ok, e = pcall(check, nil, nil, nil, err)
			done(not ok and e or nil)
		end,
	})
end

atest('anthropic: text and a tool call', function(done)
	local sent = fake([[
event: message_start
data: {"type":"message_start","message":{"usage":{"input_tokens":10,"cache_read_input_tokens":5,"output_tokens":1}}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hel"}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"lo"}}

event: content_block_stop
data: {"type":"content_block_stop","index":0}

event: content_block_start
data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"tu1","name":"read","input":{}}}

event: content_block_delta
data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"path\":"}}

event: content_block_delta
data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"\"a.c\"}"}}

event: content_block_stop
data: {"type":"content_block_stop","index":1}

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"output_tokens":20}}

event: message_stop
data: {"type":"message_stop"}

]])
	local p = require('sclop.providers.anthropic').new{ api_key = 'k' }
	run(p, { user('hi') }, done, function(msg, usage, text)
		eq(text, 'Hello')
		eq(msg.content[1].text, 'Hello')
		eq(msg.content[2].type, 'tool_call')
		eq(msg.content[2].args.path, 'a.c')
		eq(usage.input, 15)
		eq(usage.output, 20)
		local req = sent()
		eq(req.headers['x-api-key'], 'k')
		local body = json.decode(req.body)
		eq(body.system[1].cache_control.type, 'ephemeral')
		eq(body.messages[1].content[1].cache_control.type, 'ephemeral')
		eq(body.tools, nil)
	end)
end)

atest('anthropic: HTTP errors carry the message', function(done)
	fake('{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}', 401)
	local p = require('sclop.providers.anthropic').new{ api_key = 'k' }
	run(p, { user('hi') }, done, function(msg, _, _, err)
		eq(msg, nil)
		eq(err, 'HTTP 401: invalid x-api-key')
	end)
end)

atest('openai: text, tool call and tool results', function(done)
	local sent = fake([[
data: {"choices":[{"delta":{"role":"assistant","content":"Hi"}}]}

data: {"choices":[{"delta":{"content":" there"}}]}

data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"c1","function":{"name":"bash","arguments":"{\"comm"}}]}}]}

data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"and\":\"ls\"}"}}]}}]}

data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}

data: {"choices":[],"usage":{"prompt_tokens":5,"completion_tokens":7}}

data: [DONE]

]])
	local p = require('sclop.providers.openai').new{ api_key = 'k' }
	local history = {
		user('hi'),
		{ role = 'assistant', content = { { type = 'tool_call', id = 'c0', name = 'read', args = {} } } },
		{ role = 'user', content = { { type = 'tool_result', id = 'c0', content = 'data' } } },
	}
	run(p, history, done, function(msg, usage, text)
		eq(text, 'Hi there')
		eq(msg.content[2].name, 'bash')
		eq(msg.content[2].args.command, 'ls')
		eq(usage.input, 5)
		eq(usage.output, 7)
		local req = sent()
		eq(req.headers.authorization, 'Bearer k')
		local m = json.decode(req.body).messages
		eq(m[1].role, 'system')
		eq(m[3].tool_calls[1]['function'].arguments, '{}')
		assert(req.body:find('"content":null', 1, true), 'assistant content should be null')
		eq(m[4].role, 'tool')
		eq(m[4].tool_call_id, 'c0')
	end)
end)
