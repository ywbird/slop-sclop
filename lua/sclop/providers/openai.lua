-- OpenAI compatible Chat Completions API
local sse = require('sclop.sse')
local json = sclop.json

local M = {}
M.__index = M

function M.new(o)
	o = o or {}
	return setmetatable({
		base_url = o.base_url or 'https://api.openai.com/v1',
		api_key = o.api_key,
		key_env = o.key_env or 'OPENAI_API_KEY',
		extra = o.extra or {},
	}, M)
end

local function messages(system, msgs)
	local out = json.array{ { role = 'system', content = system } }
	for _, m in ipairs(msgs) do
		local text = {}
		if m.role == 'assistant' then
			local calls = json.array()
			for _, b in ipairs(m.content) do
				if b.type == 'text' then
					text[#text + 1] = b.text
				elseif b.type == 'tool_call' then
					calls[#calls + 1] = {
						id = b.id,
						type = 'function',
						['function'] = { name = b.name, arguments = json.encode(b.args or {}) },
					}
				end
			end
			local am = { role = 'assistant', content = #text > 0 and table.concat(text) or json.null }
			if #calls > 0 then
				am.tool_calls = calls
			end
			out[#out + 1] = am
		else
			for _, b in ipairs(m.content) do
				if b.type == 'tool_result' then
					out[#out + 1] = { role = 'tool', tool_call_id = b.id, content = b.content }
				elseif b.type == 'text' then
					text[#text + 1] = b.text
				end
			end
			if #text > 0 then
				out[#out + 1] = { role = 'user', content = table.concat(text, '\n') }
			end
		end
	end
	return out
end

function M:stream(req, h)
	local key = self.api_key or os.getenv(self.key_env) or ''
	local body = {
		model = req.model,
		stream = true,
		stream_options = { include_usage = true },
		messages = messages(req.system, req.messages),
	}
	if #req.tools > 0 then
		local tools = json.array()
		for _, t in ipairs(req.tools) do
			tools[#tools + 1] = {
				type = 'function',
				['function'] = { name = t.name, description = t.description, parameters = t.schema },
			}
		end
		body.tools = tools
	end
	for k, v in pairs(self.extra) do
		body[k] = v
	end

	local text, reasoning, calls, usage, raw, done = {}, {}, {}, { input = 0, output = 0 }, {}, false
	local function finish(err)
		if done then
			return
		end
		done = true
		if err then
			return h.error(err)
		end
		local msg = { role = 'assistant', content = {} }
		if #reasoning > 0 then
			msg.content[#msg.content + 1] = { type = 'thinking', thinking = table.concat(reasoning) }
		end
		if #text > 0 then
			msg.content[#msg.content + 1] = { type = 'text', text = table.concat(text) }
		end
		for i = 1, table.maxn(calls) do
			local c = calls[i]
			if c then
				c.args = c.json ~= '' and json.decode(c.json) or {}
				c.json = nil
				if c.id == '' then
					c.id = 'call_' .. i
				end
				msg.content[#msg.content + 1] = c
			end
		end
		h.done(msg, usage)
	end
	local feed = sse(function(_, data)
		if data == '[DONE]' then
			return finish()
		end
		local ev = json.decode(data)
		if not ev then
			return
		end
		if ev.error then
			return finish(ev.error.message or data)
		end
		if ev.usage then
			usage.input = ev.usage.prompt_tokens or 0
			usage.output = ev.usage.completion_tokens or 0
		end
		local c = ev.choices and ev.choices[1]
		local d = c and c.delta
		if not d then
			return
		end
		local r = d.reasoning_content or d.reasoning
		if type(r) == 'string' and r ~= '' then
			reasoning[#reasoning + 1] = r
			h.thinking(r)
		end
		if type(d.content) == 'string' and d.content ~= '' then
			text[#text + 1] = d.content
			h.text(d.content)
		end
		for _, tc in ipairs(d.tool_calls or {}) do
			local i = (tc.index or 0) + 1
			local call = calls[i] or { type = 'tool_call', id = '', name = '', json = '' }
			calls[i] = call
			local f = tc['function'] or {}
			if tc.id then
				call.id = tc.id
			end
			if f.name and call.name == '' then
				call.name = f.name
			end
			if f.arguments then
				call.json = call.json .. f.arguments
			end
		end
	end)

	local headers = { ['content-type'] = 'application/json' }
	if key ~= '' then
		headers.authorization = 'Bearer ' .. key
	end
	local handle, err = sclop.http{
		url = self.base_url .. '/chat/completions',
		headers = headers,
		body = json.encode(body),
		on_data = function(chunk)
			if #raw < 32 then
				raw[#raw + 1] = chunk
			end
			feed(chunk)
		end,
		on_done = function(status, err)
			if not err and status ~= 200 then
				local e = json.decode(table.concat(raw))
				err = string.format('HTTP %d: %s', status,
					e and e.error and e.error.message or table.concat(raw):sub(1, 300))
			end
			feed('\n\n')
			finish(err)
		end,
	}
	if not handle then
		finish(err)
		return { cancel = function() end }
	end
	return handle
end

return M
