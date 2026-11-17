local json = sclop.json

test('encode sorts keys and tells arrays from objects', function()
	eq(json.encode({ b = 1, a = { true, false }, c = 'x' }), '{"a":[true,false],"b":1,"c":"x"}')
	eq(json.encode(json.array()), '[]')
	eq(json.encode({}), '{}')
	eq(json.encode({ 1.5, -2, 1e20 }), '[1.5,-2,1e+20]')
	eq(json.encode(json.null), 'null')
end)

test('encode escapes and fixes utf-8', function()
	eq(json.encode('a"b\\c\n\t\1'), '"a\\"b\\\\c\\n\\t\\u0001"')
	eq(json.encode('한글'), '"한글"')
	eq(json.encode('bad\255x'), '"bad\239\191\189x"')
end)

test('decode keeps array nulls and drops object nulls', function()
	local v = json.decode(' {"a": [1, null, "x"], "b": null, "c": {"d": true}} ')
	eq(#v.a, 3)
	eq(v.a[2], json.null)
	eq(v.b, nil)
	eq(v.c.d, true)
	eq(json.encode(v), '{"a":[1,null,"x"],"c":{"d":true}}')
end)

test('decode unicode escapes', function()
	eq(json.decode('"\\u00e9\\ud83d\\ude00\\u0041"'), 'é😀A')
end)

test('decode errors', function()
	local v, err = json.decode('{"a":1,}')
	eq(v, nil)
	assert(err:match('^json:'), err)
	eq(json.decode('[1] x'), nil)
	eq(json.decode(''), nil)
end)

test('empty arrays survive a round trip', function()
	eq(json.encode(json.decode('{"a":[]}')), '{"a":[]}')
end)

test('functions cannot be encoded', function()
	assert(not pcall(json.encode, { f = print }))
end)
