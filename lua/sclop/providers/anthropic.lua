-- Anthropic Messages API
local sse = require('sclop.sse')
local json = sclop.json

local M = {}
M.__index = M

function M.new(o)
	o = o or {}
	return setmetatable({
		base_url = o.base_url or 'https://api.anthropic.com',
		api_key = o.api_key,
		extra = o.extra or {},
	}, M)
end

local function block(b)
	if b.type == 'text' and b.text ~= '' then
		return { type = 'text', text = b.text }
	elseif b.type == 'thinking' then
		return { type = 'thinking', thinking = b.thinking, signature = b.signature }
	elseif b.type == 'redacted_thinking' then
		return { type = 'redacted_thinking', data = b.data }
	elseif b.type == 'tool_call' then
		return { type = 'tool_use', id = b.id, name = b.name, input = b.args or {} }
	elseif b.type == 'tool_result' then
		return { type = 'tool_result', tool_use_id = b.id, content = b.content, is_error = b.is_error or nil }
	end
end

local function messages(msgs)
	local out = json.array()
	for _, m in ipairs(msgs) do
		local content = json.array()
		for _, b in ipairs(m.content) do
			content[#content + 1] = block(b)
		end
		if #content > 0 then
			out[#out + 1] = { role = m.role, content = content }
		end
	end
	local last = out[#out]
	if last then
		last.content[#last.content].cache_control = { type = 'ephemeral' }
	end
	return out
end

function M:stream(req, h)
	local key = self.api_key or os.getenv('ANTHROPIC_API_KEY')
	if not key or key == '' then
		h.error('no API key: set ANTHROPIC_API_KEY or sclop.providers.anthropic.api_key')
		return { cancel = function() end }
	end
	local body = {
		model = req.model,
		max_tokens = req.max_tokens,
		stream = true,
		system = json.array{ { type = 'text', text = req.system, cache_control = { type = 'ephemeral' } } },
		messages = messages(req.messages),
	}
	if #req.tools > 0 then
		local tools = json.array()
		for _, t in ipairs(req.tools) do
			tools[#tools + 1] = { name = t.name, description = t.description, input_schema = t.schema }
		end
		body.tools = tools
	end
	for k, v in pairs(self.extra) do
		body[k] = v
	end

	local msg, blocks, usage, raw, done = { role = 'assistant', content = {} }, {}, { input = 0, output = 0 }, {}, false
	local function finish(err)
		if done then
			return
		end
		done = true
		if err then
			h.error(err)
		else
			h.done(msg, usage)
		end
	end
	local feed = sse(function(_, data)
		local ev = json.decode(data)
		if not ev then
			return
		end
		local t, d = ev.type, ev.delta
		if t == 'message_start' then
			local u = ev.message and ev.message.usage or {}
			usage.input = (u.input_tokens or 0) + (u.cache_read_input_tokens or 0) + (u.cache_creation_input_tokens or 0)
			usage.output = u.output_tokens or 0
		elseif t == 'content_block_start' then
			local cb = ev.content_block
			if cb.type == 'tool_use' then
				blocks[ev.index] = { type = 'tool_call', id = cb.id, name = cb.name, json = '' }
			else
				blocks[ev.index] = { type = cb.type, text = cb.text, thinking = cb.thinking, signature = cb.signature, data = cb.data }
			end
		elseif t == 'content_block_delta' then
			local b = blocks[ev.index]
			if not b then
				return
			end
			if d.type == 'text_delta' then
				b.text = (b.text or '') .. d.text
				h.text(d.text)
			elseif d.type == 'thinking_delta' then
				b.thinking = (b.thinking or '') .. d.thinking
				h.thinking(d.thinking)
			elseif d.type == 'signature_delta' then
				b.signature = (b.signature or '') .. d.signature
			elseif d.type == 'input_json_delta' then
				b.json = b.json .. d.partial_json
			end
		elseif t == 'content_block_stop' then
			local b = blocks[ev.index]
			if b and b.type == 'tool_call' then
				b.args = b.json ~= '' and json.decode(b.json) or {}
				b.json = nil
			end
			msg.content[#msg.content + 1] = b
		elseif t == 'message_delta' then
			if ev.usage and ev.usage.output_tokens then
				usage.output = ev.usage.output_tokens
			end
			msg.stop = d and d.stop_reason
		elseif t == 'message_stop' then
			finish()
		elseif t == 'error' then
			finish(ev.error and ev.error.message or data)
		end
	end)

	local handle, err = sclop.http{
		url = self.base_url .. '/v1/messages',
		headers = {
			['x-api-key'] = key,
			['anthropic-version'] = '2023-06-01',
			['content-type'] = 'application/json',
		},
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
			finish(err or (not done and 'the stream ended early') or nil)
		end,
	}
	if not handle then
		finish(err)
		return { cancel = function() end }
	end
	return handle
end

return M
