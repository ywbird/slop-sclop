-- sclog: print a session .jsonl as readable plaintext.
-- The `sclog` script runs `sclop -l lua/sclog.lua` to reach M.main.
local util = require('sclop.util')

local json = sclop.json
local M = {}

local usage = 'usage: sclog [--thinking] [--tools] [--verbose] [--all] FILE\n'

local function oneline(s)
	return (s:gsub('%s*\n%s*', ' ⏎ '))
end

-- the text of a tool_result
local function result_text(content)
	if type(content) ~= 'table' then
		return tostring(content or '')
	end
	local t = {}
	for _, b in ipairs(content) do
		t[#t + 1] = type(b) == 'table' and tostring(b.text or '') or tostring(b)
	end
	return table.concat(t, '\n')
end

-- the result of a tool call: `  ⎿ ` and three lines, or all of it when verbose
local function result_block(content, verbose)
	local lines = util.lines(result_text(content))
	local max = verbose and #lines or math.min(3, #lines)
	local t = {}
	for i = 1, max do
		t[#t + 1] = (i == 1 and '  ⎿ ' or '    ') .. lines[i]
	end
	if #lines > max then
		t[#t + 1] = string.format('    … %d more lines', #lines - max)
	end
	return table.concat(t, '\n')
end

-- the one-line form of a tool call, using the tool's own summary
local function call_line(b)
	local tool = sclop.tools[b.name]
	local ok, s = pcall(tool and tool.summary and tool.summary or json.encode, b.args or {})
	local summary = ok and s ~= nil and tostring(s) or ''
	summary = oneline(summary)
	return '● ' .. b.name .. (summary ~= '' and ' ' .. summary or '')
end

-- the blocks of one assistant message; results is a tool call id -> tool_result map
local function message_blocks(content, results, opt, out)
	results = results or {}
	for _, b in ipairs(content or {}) do
		local t = b.text or b.thinking or ''
		if b.type == 'text' then
			if t ~= '' then
				out[#out + 1] = t
			end
		elseif b.type == 'thinking' and opt.thinking then
			if t ~= '' then
				out[#out + 1] = '∴ ' .. t:gsub('\n', '\n  ')
			end
		elseif b.type == 'tool_call' and opt.tools then
			local r = results[b.id]
			out[#out + 1] = call_line(b) .. (r and '\n' .. result_block(r.content, opt.verbose) or '')
		end
	end
end

-- the whole file as text, or nil and an error
function M.render(path, opt)
	opt = opt or {}
	local f, err = io.open(path)
	if not f then
		return nil, err
	end
	local out, pending = {}, nil
	for line in f:lines() do
		local e = json.decode(line)
		if e and e.type == 'session' then
			out[#out + 1] = (e.model or '?') .. ' · ' .. (e.cwd or '?')
		elseif e and e.type == 'compact' then
			if pending then
				message_blocks(pending.content, nil, opt, out)
				pending = nil
			end
			out[#out + 1] = '── compacted ──\n' .. (e.summary or '')
		elseif e and e.role == 'assistant' then
			pending = e -- printed with the results in the user message after it
		elseif e and e.role == 'user' then
			local results = {}
			for _, b in ipairs(e.content or {}) do
				if b.type == 'tool_result' then
					results[b.id] = b
				end
			end
			if pending then
				message_blocks(pending.content, results, opt, out)
				pending = nil
			end
			for _, b in ipairs(e.content or {}) do
				if b.type == 'text' and b.text ~= '' then
					out[#out + 1] = '> ' .. b.text:gsub('\n', '\n  ')
				end
			end
		end
	end
	if pending then
		message_blocks(pending.content, nil, opt, out)
	end
	f:close()
	return table.concat(out, '\n\n') .. '\n'
end

-- command line: flags, then exactly one file
function M.main(args)
	local opt, path = {}, nil
	for _, a in ipairs(args) do
		if a == '--thinking' then
			opt.thinking = true
		elseif a == '--tools' then
			opt.tools = true
		elseif a == '--verbose' then
			opt.tools, opt.verbose = true, true
		elseif a == '--all' then
			opt.thinking, opt.tools, opt.verbose = true, true, true
		elseif a:sub(1, 1) == '-' then
			io.stderr:write('sclog: unknown option ', a, '\n', usage)
			return 1
		elseif path then
			io.stderr:write('sclog: one file at a time\n', usage)
			return 1
		else
			path = a
		end
	end
	if not path then
		io.stderr:write(usage)
		return 1
	end
	local text, err = M.render(path, opt)
	if not text then
		io.stderr:write('sclog: ', err or ('cannot read ' .. path), '\n')
		return 1
	end
	io.write(text)
	return 0
end

return M
