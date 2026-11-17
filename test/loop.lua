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

atest('watch calls back when an fd is readable', function(done)
	local ffi = require('ffi')
	ffi.cdef[[
	int pipe(int fds[2]);
	long read(int fd, void *buf, unsigned long n);
	long write(int fd, const void *buf, unsigned long n);
	int close(int fd);
	]]
	local fds = ffi.new('int[2]')
	assert(ffi.C.pipe(fds) == 0)
	local r, w = fds[0], fds[1]
	sclop.core.watch(r, 'r', function(ev)
		local buf = ffi.new('char[8]')
		local n = tonumber(ffi.C.read(r, buf, 8))
		sclop.core.unwatch(r)
		ffi.C.close(r)
		ffi.C.close(w)
		done((ev ~= 'r' or ffi.string(buf, n) ~= 'ping') and ev .. ' ' .. ffi.string(buf, n) or nil)
	end)
	ffi.C.write(w, 'ping', 4)
end)

test('now is monotonic', function()
	local a = sclop.core.now()
	assert(sclop.core.now() >= a)
end)
