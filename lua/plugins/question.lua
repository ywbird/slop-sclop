-- question: a tool for the model to ask the user, with numbered options.
-- The answer is typed into the input: option numbers (comma separated) or free text.
--
--   require('plugins/question')

local S = sclop.style
local pending -- { questions, answers, done }

sclop.tools.register{
	name = 'question',
	description = 'Ask the user one or more questions and wait for the answers. Use it when a choice '
		.. 'is ambiguous and you need a decision. Offer short options; the user may also answer freely.',
	schema = {
		type = 'object',
		properties = {
			questions = {
				type = 'array',
				items = {
					type = 'object',
					properties = {
						question = { type = 'string' },
						options = {
							type = 'array',
							items = {
								type = 'object',
								properties = { label = { type = 'string' }, description = { type = 'string' } },
								required = sclop.json.array{ 'label' },
							},
						},
						multiple = { type = 'boolean', description = 'more than one option may be picked' },
					},
					required = sclop.json.array{ 'question' },
				},
			},
		},
		required = sclop.json.array{ 'questions' },
	},
	summary = function(a)
		local q = a.questions and a.questions[1]
		return q and q.question or ''
	end,
	run = function(a, done)
		if type(a.questions) ~= 'table' or #a.questions == 0 then
			return done('no questions given', true)
		end
		pending = { questions = a.questions, answers = {}, done = done }
		sclop.redraw()
		return function()
			pending = nil
		end
	end,
}

local live = sclop.view.live
sclop.view.live = function(lines)
	live(lines)
	local q = pending and pending.questions[#pending.answers + 1]
	if not q then
		return
	end
	lines[#lines + 1] = S.yellow('? ') .. S.bold(q.question)
	for i, o in ipairs(q.options or {}) do
		lines[#lines + 1] = string.format('  %d. %s%s', i, o.label or '',
			o.description and S.gray(' — ' .. o.description) or '')
	end
	lines[#lines + 1] = S.gray(#(q.options or {}) > 0
		and (q.multiple and '  numbers separated by commas, or your own answer' or '  a number, or your own answer')
		or '  type your answer')
end

sclop.events.subscribe(sclop.events.SUBMIT, function(text)
	local q = pending and pending.questions[#pending.answers + 1]
	if not q then
		return
	end
	local answer = text
	if q.options and text:match('^[%d,%s]+$') then
		local picked = {}
		for n in text:gmatch('%d+') do
			local o = q.options[tonumber(n)]
			if o then
				picked[#picked + 1] = o.label
			end
		end
		if #picked > 0 then
			answer = table.concat(picked, ', ')
		end
	end
	pending.answers[#pending.answers + 1] = answer
	sclop.commit(S.gray('  ? ' .. q.question .. ' → ') .. answer)
	if #pending.answers == #pending.questions then
		local p, out = pending, {}
		pending = nil
		for i, qq in ipairs(p.questions) do
			out[i] = 'Q: ' .. tostring(qq.question) .. '\nA: ' .. p.answers[i]
		end
		p.done(table.concat(out, '\n\n'))
	end
	sclop.redraw()
	return true
end)

return {}
