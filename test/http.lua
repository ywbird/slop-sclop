-- real HTTP against test/mock.py; skipped without python3
if not require('sclop.util').has('python3') then
	return
end

atest('streams over http and chains requests from callbacks', function(done)
	local port = tostring(20000 + os.time() % 10000)
	local server = sclop.spawn{ argv = { 'python3', 'test/mock.py', port } }
	local p = require('sclop.providers.anthropic').new{ base_url = 'http://127.0.0.1:' .. port, api_key = 'k' }
	local function finish(err)
		server:kill()
		done(err)
	end
	local function ask(text, h)
		p:stream({ model = 'm', system = 's', tools = {}, max_tokens = 10,
			messages = { { role = 'user', content = { { type = 'text', text = text } } } } }, h)
	end
	local tries = 0
	local function start()
		ask('first', {
			text = function() end,
			thinking = function() end,
			error = function(err)
				tries = tries + 1
				if tries > 60 then
					return finish(err)
				end
				sclop.timer(50, start) -- the server is still starting
			end,
			done = function(msg)
				if msg.content[1].text ~= 'You said: first\nThat is all.' then
					return finish('first reply: ' .. tostring(msg.content[1].text))
				end
				-- called from inside curl's write callback: must still work
				ask('second', {
					text = function() end,
					thinking = function() end,
					error = finish,
					done = function(m2)
						finish(m2.content[1].text ~= 'You said: second\nThat is all.' and 'second reply' or nil)
					end,
				})
			end,
		})
	end
	start()
end)
