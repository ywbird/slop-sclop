-- agent: echoes input until the conversation loop lands
local A = { busy = false, messages = {} }

function A.submit(text)
	sclop.commit(sclop.view.user(text))
end

function A.abort() end

function A.clear()
	A.messages = {}
end

return A
