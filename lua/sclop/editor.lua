-- input buffer and the default INPUT keymap. Positions are 0-based byte offsets.
local M = {}
local Input = {}
Input.__index = Input

function M.new()
	return setmetatable({ text = '', pos = 0, history = {}, hindex = 0 }, Input)
end

function Input:set(text, pos)
	self.text = text
	self.pos = math.max(0, math.min(pos or #text, #text))
	sclop.redraw()
end

function Input:insert(s)
	local t = self.text
	self.text = t:sub(1, self.pos) .. s .. t:sub(self.pos + 1)
	self.pos = self.pos + #s
	sclop.redraw()
end

function Input:delete(pos, len)
	if pos < 0 then
		len, pos = len + pos, 0
	end
	if len <= 0 then
		return
	end
	local t = self.text
	self.text = t:sub(1, pos) .. t:sub(pos + len + 1)
	if self.pos >= pos + len then
		self.pos = self.pos - len
	elseif self.pos > pos then
		self.pos = pos
	end
	sclop.redraw()
end

function Input:content(pos, len)
	return self.text:sub(pos + 1, pos + len)
end

local function cont(b)
	return b and b >= 0x80 and b < 0xc0
end

function Input:prevchar(pos)
	pos = (pos or self.pos) - 1
	while pos > 0 and cont(self.text:byte(pos + 1)) do
		pos = pos - 1
	end
	return math.max(pos, 0)
end

function Input:nextchar(pos)
	pos = (pos or self.pos) + 1
	while pos < #self.text and cont(self.text:byte(pos + 1)) do
		pos = pos + 1
	end
	return math.min(pos, #self.text)
end

function Input:linestart(pos)
	local s = self.text:sub(1, pos or self.pos):match('.*\n()')
	return s and s - 1 or 0
end

function Input:lineend(pos)
	local e = self.text:find('\n', (pos or self.pos) + 1, true)
	return e and e - 1 or #self.text
end

function Input:wordprev(pos)
	return self.text:sub(1, pos or self.pos):find('[^%s]*%s*$') - 1
end

function Input:wordnext(pos)
	local _, e = self.text:find('^%s*[^%s]*', (pos or self.pos) + 1)
	return e or #self.text
end

-- move a line up (dir < 0) or down keeping the display column; false at the edge
function Input:vertical(dir)
	local s, width = self:linestart(), sclop.core.width
	local col = width(self.text:sub(s + 1, self.pos))
	local target
	if dir < 0 then
		if s == 0 then
			return false
		end
		target = self:linestart(s - 1)
	else
		local e = self:lineend()
		if e >= #self.text then
			return false
		end
		target = e + 1
	end
	local p, e = target, self:lineend(target)
	while p < e do
		local np = self:nextchar(p)
		if width(self.text:sub(target + 1, np)) > col then
			break
		end
		p = np
	end
	self.pos = p
	return true
end

function Input:push_history(text)
	if text ~= self.history[#self.history] then
		table.insert(self.history, text)
	end
	self.hindex = 0
end

-- dir < 0: older entry, dir > 0: newer; hindex 0 is the draft being edited
function Input:history_move(dir)
	local h, i = self.history, self.hindex - dir
	if i < 0 or i > #h then
		return
	end
	if self.hindex == 0 then
		self.draft = self.text
	end
	self.hindex = i
	self:set(i == 0 and self.draft or h[#h - i + 1])
end

-- default keymap
local I = sclop.modes.INPUT

local function input()
	return sclop.input
end

local function special(key)
	return #key > 1 and key:sub(1, 1) == '<' and key:sub(-1) == '>'
end

sclop.defaults[I] = function(key)
	if not special(key) then
		input():insert(key)
	end
end

sclop:map(I, '<Enter>', function()
	local i = input()
	local text = i.text
	if not text:match('^%s*$') and sclop.submit(text) then
		i:push_history(text)
		i:set('')
	end
end)
sclop:map(I, '<M-Enter>', function() input():insert('\n') end)
sclop:map(I, '<C-j>', '<M-Enter>')
sclop:map(I, '<Backspace>', function()
	local i = input()
	local p = i:prevchar()
	i:delete(p, i.pos - p)
end)
sclop:map(I, '<C-h>', '<Backspace>')
sclop:map(I, '<Delete>', function()
	local i = input()
	i:delete(i.pos, i:nextchar() - i.pos)
end)
sclop:map(I, '<C-d>', function()
	if input().text == '' then
		sclop.quit()
	else
		sclop:dokey('<Delete>')
	end
end)
sclop:map(I, '<Left>', function() input().pos = input():prevchar() end)
sclop:map(I, '<C-b>', '<Left>')
sclop:map(I, '<Right>', function() input().pos = input():nextchar() end)
sclop:map(I, '<C-f>', '<Right>')
sclop:map(I, '<Home>', function() input().pos = input():linestart() end)
sclop:map(I, '<C-a>', '<Home>')
sclop:map(I, '<End>', function() input().pos = input():lineend() end)
sclop:map(I, '<C-e>', '<End>')
sclop:map(I, '<Up>', function()
	if not input():vertical(-1) then
		input():history_move(-1)
	end
end)
sclop:map(I, '<C-p>', '<Up>')
sclop:map(I, '<Down>', function()
	if not input():vertical(1) then
		input():history_move(1)
	end
end)
sclop:map(I, '<C-n>', '<Down>')
sclop:map(I, '<M-b>', function() input().pos = input():wordprev() end)
sclop:map(I, '<C-Left>', '<M-b>')
sclop:map(I, '<M-f>', function() input().pos = input():wordnext() end)
sclop:map(I, '<C-Right>', '<M-f>')
sclop:map(I, '<C-w>', function()
	local i = input()
	local p = i:wordprev()
	i:delete(p, i.pos - p)
end)
sclop:map(I, '<M-Backspace>', '<C-w>')
sclop:map(I, '<C-u>', function()
	local i = input()
	local s = i:linestart()
	i:delete(s, i.pos - s)
end)
sclop:map(I, '<C-k>', function()
	local i = input()
	i:delete(i.pos, i:lineend() - i.pos)
end)
sclop:map(I, '<Escape>', function()
	if sclop.agent.busy then
		sclop.agent.abort()
	end
end)
sclop:map(I, '<C-c>', function()
	if sclop.agent.busy then
		sclop.agent.abort()
	elseif input().text ~= '' then
		input():set('')
	else
		sclop.quit()
	end
end)
sclop:map(I, '<C-l>', function()
	sclop.core.write('\27[H\27[2J')
	sclop.core.reset()
end)

return M
