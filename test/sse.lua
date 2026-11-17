local sse = require('sclop.sse')

test('sse events split across chunks', function()
	local got = {}
	local feed = sse(function(ev, data) got[#got + 1] = ev .. '=' .. data end)
	feed('event: a\ndata: 1\n\n: comment\nda')
	feed('ta: 2\ndata:3\r\n\r\n')
	eq(table.concat(got, ';'), 'a=1;message=2\n3')
end)
