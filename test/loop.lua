atest('timers fire in order', function(done)
	local seen = {}
	sclop.timer(20, function() table.insert(seen, 'b') end)
	sclop.timer(0, function() table.insert(seen, 'a') end)
	sclop.timer(40, function()
		done(table.concat(seen) ~= 'ab' and 'order ' .. table.concat(seen) or nil)
	end)
end)

atest('repeating timer stops', function(done)
	local n = 0
	local t
	t = sclop.timer(5, function()
		n = n + 1
		if n == 3 then
			t:stop()
			sclop.timer(30, function() done(n ~= 3 and 'ran ' .. n .. ' times' or nil) end)
		end
	end, true)
end)

test('now is monotonic', function()
	local a = sclop.core.now()
	assert(sclop.core.now() >= a)
end)
