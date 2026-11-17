-- view: the live region (the TEA view) and the formats of committed text
local S = sclop.style
local V = {}

local spinner = { '⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏' }

function V.prompt(n)
	return n == 1 and S.bold('> ') or '  '
end

function V.separator()
	return S.gray(string.rep('─', (sclop.core.size())))
end

function V.tokens(n)
	return n < 1000 and tostring(n) or string.format('%.1fk', n / 1000)
end

-- lines of work in progress; filled by the agent's state
function V.live(lines)
	local a = sclop.agent
	if a.partial and a.partial ~= '' then
		lines[#lines + 1] = a.partial
	end
end

-- input lines; returns the cursor row and byte column
function V.input(lines)
	local input, row, col, start, n = sclop.input, nil, nil, 0, 0
	for line in (input.text .. '\n'):gmatch('(.-)\n') do
		n = n + 1
		local prefix = V.prompt(n)
		lines[#lines + 1] = prefix .. line
		if not row and input.pos <= start + #line then
			row, col = #lines, #prefix + input.pos - start
		end
		start = start + #line + 1
	end
	return row, col
end

function V.status()
	local a = sclop.agent
	local segs = { sclop.provider .. '/' .. sclop.model }
	if a.tokens and a.tokens > 0 then
		segs[#segs + 1] = V.tokens(a.tokens) .. ' tokens'
	end
	if a.busy then
		segs[#segs + 1] = spinner[math.floor(sclop.core.now() / 80) % #spinner + 1]
	end
	sclop.events.emit(sclop.events.STATUS, segs)
	return S.gray(table.concat(segs, '  '))
end

function V.render()
	local lines = {}
	V.live(lines)
	lines[#lines + 1] = V.separator()
	local row, col = V.input(lines)
	lines[#lines + 1] = V.status()
	return lines, row, col
end

-- committed text

function V.user(text)
	return '\n' .. S.bold('> ') .. (text:gsub('\n', '\n  ')) .. '\n'
end

return V
