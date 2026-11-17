local function keys(bytes)
	local got = {}
	local function h(k)
		got[#got + 1] = k
		return true
	end
	sclop.events.subscribe(sclop.events.KEY, h)
	sclop.core.feed(bytes)
	sclop.events.unsubscribe(sclop.events.KEY, h)
	return table.concat(got, '|')
end

test('plain and utf-8 keys', function()
	eq(keys('a한 <'), 'a|한| |<')
end)

test('control keys', function()
	eq(keys('\r\t\127\8\10\1\0\28'), '<Enter>|<Tab>|<Backspace>|<C-h>|<C-j>|<C-a>|<C-Space>|<C-\\>')
end)

test('escape and meta', function()
	eq(keys('\27'), '<Escape>')
	eq(keys('\27x\27\r\27\1\27\127'), '<M-x>|<M-Enter>|<C-M-a>|<M-Backspace>')
end)

test('csi and ss3', function()
	eq(keys('\27[A\27[1;5C\27[3~\27[Z\27OP\27[5;3~\27[24~'),
		'<Up>|<C-Right>|<Delete>|<S-Tab>|<F1>|<M-PageUp>|<F12>')
end)

test('unknown sequences are dropped', function()
	eq(keys('\27[99xq'), 'q')
end)

test('invalid utf-8 becomes U+FFFD', function()
	eq(keys('\255a'), '\239\191\189|a')
end)

test('bracketed paste', function()
	local got
	local function h(t)
		got = t
		return true
	end
	sclop.events.subscribe(sclop.events.PASTE, h)
	eq(keys('x\27[200~hi\nthere\27[Ay\27[201~z'), 'x|z')
	sclop.events.unsubscribe(sclop.events.PASTE, h)
	eq(got, 'hi\nthere\27[Ay')
end)
