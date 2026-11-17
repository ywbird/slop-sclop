local util = require('sclop.util')

local shell = util.has('bash') and 'bash' or 'sh'
local KEEP = 50 * 1024

sclop.tools.register{
	name = 'bash',
	description = 'Run a shell command in the working directory. stdout and stderr are merged; '
		.. 'long output keeps only its end. There is no terminal and no stdin, so avoid interactive '
		.. 'programs. timeout is in milliseconds, 120000 by default.',
	schema = {
		type = 'object',
		properties = {
			command = { type = 'string', description = 'the command line' },
			timeout = { type = 'integer', description = 'milliseconds before the command is killed' },
		},
		required = sclop.json.array{ 'command' },
	},
	summary = function(a)
		return a.command
	end,
	run = function(a, done, progress)
		local out, size, timedout, timer = {}, 0, false, nil
		local ms = tonumber(a.timeout) or 120000
		local p, err = sclop.spawn{
			argv = { shell, '-c', a.command or '' },
			merge = true,
			on_stdout = function(data)
				out[#out + 1] = data
				size = size + #data
				if size > 4 * KEEP then
					out = { table.concat(out):sub(-KEEP) }
					size = KEEP
				end
				progress(table.concat(out):sub(-2048))
			end,
			on_exit = function(code, sig)
				if timer then
					timer:stop()
				end
				local text = util.truncate(table.concat(out), 2000, KEEP, true)
				if timedout then
					text = text .. string.format('\n(killed after %d ms)', ms)
				elseif sig ~= 0 then
					text = text .. '\n(killed by signal ' .. sig .. ')'
				elseif code ~= 0 then
					text = text .. '\n(exit code ' .. code .. ')'
				end
				text = text:gsub('^\n', '')
				done(text ~= '' and text or '(no output)', timedout)
			end,
		}
		if not p then
			return done(err, true)
		end
		timer = sclop.timer(ms, function()
			timedout = true
			p:kill(9)
		end)
		return function()
			p:kill(9)
		end
	end,
}
