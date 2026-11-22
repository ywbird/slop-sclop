-- Korean IME (두벌식) for sclop.
--
-- Port of vis-korea-ime (https://codeberg.org/ywbird/vis-korea-ime), which ports
-- Korean-IME.nvim (https://github.com/kiyoon/Korean-IME.nvim).
-- Copyright (c) 2025 Kiyoon Kim, Copyright (c) 2026 ywbird. MIT license, see LICENSE.
--
--   local ime = require('plugins/korean-ime')
--   ime.setup()
--   sclop:map(sclop.modes.INPUT, '<M-\\>', ime.change_mode)

local M = { mode = 'en' }

local function has_value(arr, item)
	for i = 1, #arr do
		if arr[i] == item then
			return true
		end
	end
	return false
end

local function array_append(arr1, arr2)
	local c = {}
	for _, v in ipairs(arr1) do
		table.insert(c, v)
	end
	for _, v in ipairs(arr2) do
		table.insert(c, v)
	end
	return c
end

-- stylua: ignore start
-- TABLE{I,M,F} -- tables for initial, medial, final jamos
--                     0     1     2     3     4     5     6     7     8     9
local TABLEI = { [0]='ㄱ', 'ㄲ', 'ㄴ', 'ㄷ', 'ㄸ', 'ㄹ', 'ㅁ', 'ㅂ', 'ㅃ', 'ㅅ',
                     'ㅆ', 'ㅇ', 'ㅈ', 'ㅉ', 'ㅊ', 'ㅋ', 'ㅌ', 'ㅍ', 'ㅎ'}
local TABLEM = { [0]='ㅏ', 'ㅐ', 'ㅑ', 'ㅒ', 'ㅓ', 'ㅔ', 'ㅕ', 'ㅖ', 'ㅗ', 'ㅘ',
                     'ㅙ', 'ㅚ', 'ㅛ', 'ㅜ', 'ㅝ', 'ㅞ', 'ㅟ', 'ㅠ', 'ㅡ', 'ㅢ',
                     'ㅣ'}
local TABLEF = { [0]='ㄱ', 'ㄲ', 'ㄳ', 'ㄴ', 'ㄵ', 'ㄶ', 'ㄷ', 'ㄹ', 'ㄺ', 'ㄻ',
                     'ㄼ', 'ㄽ', 'ㄾ', 'ㄿ', 'ㅀ', 'ㅁ', 'ㅂ', 'ㅄ', 'ㅅ', 'ㅆ',
                     'ㅇ', 'ㅈ', 'ㅊ', 'ㅋ', 'ㅌ', 'ㅍ', 'ㅎ'}

-- TABLEC{M,F} -- mappings from keystrokes to medial/final compounds
--                Key consists of two elements (A * 100 + B).
local TABLECM = { [800]=9, [801]=10, [820]=11, [1304]=14, [1305]=15, [1320]=16,
                  [1820]=19}
local TABLECF = { [0]=1, [18]=2, [321]=4, [326]=5, [700]=8, [715]=9, [716]=10,
                  [718]=11, [724]=12, [725]=13, [726]=14, [1618]=17, [1818]=19}

-- TABLEFC -- reverse mapping from final jamo to compound elements & initial jamo
-- Legend: (A * 100 + B) * 100 + C
--         A and B are compound elements; if not compound, A should be 99.
--         C is equivalent initial jamo # or 99 (no equivalent jamo).
local TABLEFC = { [0]=990000,      1,    999, 990202,  31299,  31899, 990303, 990505,
--                      'ㄱ',   'ㄲ',   'ㄳ',   'ㄴ',   'ㄵ',   'ㄶ',   'ㄷ',   'ㄹ',
                       70099,  70699,  70799,  70999,  71699,  71799,  71899, 990606,
--                      'ㄺ',   'ㄻ',   'ㄼ',   'ㄽ',   'ㄾ',   'ㄿ',   'ㅀ',   'ㅁ',
                      990707, 160999, 990909, 180910, 991111, 991212, 991414, 991515,
--                      'ㅂ',   'ㅄ',   'ㅅ',   'ㅆ',   'ㅇ',   'ㅈ',   'ㅊ',   'ㅋ',
                      991616, 991717, 991818 }
--                      'ㅌ',   'ㅍ',   'ㅎ'
-- stylua: ignore end

---Get a Hangeul syllable from serial (-1 to 11171)
local function get_syllable(serial)
	return utf8.char(44033 + serial)
end

local syllable = {
	init = -1,
	med = -1,
	fin = -1,
	state = 0,
}

---Get current syllable's representation
M.keystrokes = function()
	local keys = {}
	if syllable.init < 0 then
		if not (syllable.med < 0) then
			table.insert(keys, TABLEM[syllable.med])
		end
		if not (syllable.fin < 0) then
			table.insert(keys, TABLEF[syllable.fin])
		end
	elseif syllable.med < 0 then
		table.insert(keys, TABLEI[syllable.init])
		if not (syllable.fin < 0) then
			table.insert(keys, TABLEF[syllable.fin])
		end
	else
		table.insert(keys, get_syllable(syllable.init * 588 + syllable.med * 28 + syllable.fin))
	end
	return keys
end

---Update current syllable and return appropriate key sequences
---존재하는 글자에 따라 한번 혹은 두번 지운 후 글자 입력하는 방식임.
local function update_syllable(init, med, fin)
	local keys = {}
	if not (syllable.init < 0 and syllable.med < 0 and syllable.fin < 0) then
		table.insert(keys, -1)
		if (syllable.init < 0 or syllable.med < 0) and syllable.fin >= 0 then
			table.insert(keys, -1)
		end
	end
	syllable.init = init
	syllable.med = med
	syllable.fin = fin
	return array_append(keys, M.keystrokes())
end

-------------------------------------------------------------------------------
-- KS X 5002 two-layered scheme (Dubeolsik standard)
-- Legend: A * 100 + B or -1 (not applicable)
--         Vowel if A is 99, where B is medial jamo #
--         Consonant otherwise, where A is initial # and B is final # (or 99)

-- stylua: ignore start
local MAP2s = { [0]=615, 9917, 1422, 1120,  499,  507, 1826, 9908, 9902, 9904,
                9900, 9920, 9918, 9913, 9903, 9907,  899,  101,  203, 1019,
                9906, 1725, 1399, 1624, 9912, 1523,   -1,   -1,   -1,   -1,
                -1,   -1,  615, 9917, 1422, 1120,  306,  507, 1826, 9908,
                9902, 9904, 9900, 9920, 9918, 9913, 9901, 9905,  716,    0,
                203,  918, 9906, 1725, 1221, 1624, 9912, 1523,   -1,   -1,
                -1,   -1}
-- stylua: ignore end

local function finish_2s()
	syllable.init = -1
	syllable.med = -1
	syllable.fin = -1
	syllable.state = 0
end

---@param key integer
local function compose_2s(key)
	if key < 65 or MAP2s[key - 65] < 0 then
		finish_2s()
		return { utf8.char(key) }
	end
	local value1 = math.floor(MAP2s[key - 65] / 100) -- init #
	local value2 = MAP2s[key - 65] % 100 -- final #
	local isvowel = (value1 == 99)

	if syllable.state == 1 then -- initial jamo is present
		if isvowel then
			syllable.state = 2
			return update_syllable(syllable.init, value2, -1)
		-- ㄱ, ㄷ, ㅂ, ㅅ, ㅈ double to ㄲ, ㄸ, ㅃ, ㅆ, ㅉ (syllable.init + 1)
		elseif has_value({ 0, 3, 7, 9, 12 }, value1) and value1 == syllable.init then
			return update_syllable(syllable.init + 1, -1, -1)
		end
	elseif syllable.state == 2 or syllable.state == 5 then -- medial jamo is present
		if isvowel then
			if TABLECM[syllable.med * 100 + value2] ~= nil then
				local newmedial = TABLECM[syllable.med * 100 + value2]
				return update_syllable(syllable.init, newmedial, -1)
			end
		elseif syllable.state == 2 and value2 ~= 99 then
			syllable.state = 3
			return update_syllable(syllable.init, syllable.med, value2)
		end
	elseif syllable.state == 3 or syllable.state == 4 then -- all jamo are present
		if isvowel then
			local prevfinal, nextinitial
			if syllable.state == 3 then
				prevfinal = -1
				nextinitial = TABLEFC[syllable.fin] % 100
			else
				prevfinal = math.floor(TABLEFC[syllable.fin] / 10000)
				nextinitial = math.floor(TABLEFC[syllable.fin] / 100 % 100)
			end
			local iresult = update_syllable(syllable.init, syllable.med, prevfinal)
			finish_2s()
			syllable.state = 2
			return array_append(iresult, update_syllable(nextinitial, value2, -1))
		else
			if TABLECF[syllable.fin * 100 + value2] ~= nil then
				syllable.state = 4
				local newfinal = TABLECF[syllable.fin * 100 + value2]
				return update_syllable(syllable.init, syllable.med, newfinal)
			end
		end
	end

	finish_2s()
	if value1 == 99 then
		syllable.state = 5
		return update_syllable(-1, value2, -1)
	else
		syllable.state = 1
		return update_syllable(value1, -1, -1)
	end
end

local function revert_2s()
	if syllable.fin >= 0 then
		syllable.state = 2
		return update_syllable(syllable.init, syllable.med, -1)
	end
	if syllable.med >= 0 then
		syllable.state = (syllable.init < 0 and 0 or 1)
		return update_syllable(syllable.init, -1, -1)
	end
	syllable.state = 0
	if syllable.init >= 0 then
		return update_syllable(-1, -1, -1)
	else
		return { -1 }
	end
end

-------------------------------------------------------------------------
-- sclop glue

-- where our last edit left the input; anything else moved it, ending the syllable
local expect_pos, expect_len

local function settle()
	local i = sclop.input
	if i.pos ~= expect_pos or #i.text ~= expect_len then
		finish_2s()
	end
end

-- -1 deletes the character before the cursor, strings are inserted
local function apply(keys)
	local i = sclop.input
	for _, k in ipairs(keys) do
		if k == -1 then
			local p = i:prevchar()
			i:delete(p, i.pos - p)
		else
			i:insert(k)
		end
	end
	expect_pos, expect_len = i.pos, #i.text
end

M.change_mode = function()
	finish_2s()
	M.mode = M.mode == 'en' and 'ko' or 'en'
	sclop.redraw()
end

M.get_mode = function()
	return M.mode
end

M.set_mode = function(mode)
	finish_2s()
	M.mode = mode == 'ko' and 'ko' or 'en'
	sclop.redraw()
end

M.setup = function()
	local I = sclop.modes.INPUT
	for key = 33, 126 do
		sclop:map(I, string.char(key), function()
			settle()
			apply(M.mode == 'ko' and compose_2s(key) or { string.char(key) })
		end)
	end

	-- Fix: https://github.com/kiyoon/Korean-IME.nvim/issues/2
	sclop:map(I, ' ', function()
		finish_2s()
		apply({ ' ' })
	end)

	local function backspace()
		settle()
		apply(M.mode == 'ko' and revert_2s() or { -1 })
	end
	-- <C-h> is normally an alias of <Backspace>; a different mapping is left alone
	if sclop:mappings(I)['<C-h>'] == '<Backspace>' then
		sclop:map(I, '<C-h>', backspace)
	end
	sclop:map(I, '<Backspace>', backspace)

	sclop.events.subscribe(sclop.events.STATUS, function(segs)
		if M.mode == 'ko' then
			segs[#segs + 1] = '한'
		end
	end)
end

return M
