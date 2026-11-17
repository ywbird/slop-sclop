-- webfetch: a tool that fetches a URL. HTML pages become markdown.
--
--   require('plugins/webfetch')

local util = require('sclop.util')

local M = {}
local MAX = 5 * 1024 * 1024

local entities = {
	amp = '&', lt = '<', gt = '>', quot = '"', apos = "'", nbsp = ' ', copy = '©', reg = '®',
	mdash = '—', ndash = '–', hellip = '…', laquo = '«', raquo = '»', ldquo = '“', rdquo = '”',
	lsquo = '‘', rsquo = '’', middot = '·', bull = '•', trade = '™', times = '×',
}

local function decode(s)
	return (s:gsub('&(#?)([xX]?)(%w+);', function(hash, x, name)
		if hash == '#' then
			local n = tonumber(name, x ~= '' and 16 or 10)
			return n and n > 0 and n < 0x110000 and utf8.char(n) or nil
		end
		return entities[name:lower()]
	end))
end

local function attr(attrs, name)
	return attrs:match(name .. '%s*=%s*"([^"]*)"') or attrs:match(name .. "%s*=%s*'([^']*)'")
		or attrs:match(name .. '%s*=%s*([^%s>]+)')
end

local skipped = { script = true, style = true, head = true, noscript = true, svg = true,
	template = true, iframe = true }
local blocks = { p = true, div = true, section = true, article = true, header = true, footer = true,
	main = true, nav = true, aside = true, table = true, form = true, figure = true, figcaption = true,
	dl = true, dt = true, dd = true, details = true, summary = true, ul = true, ol = true,
	blockquote = true }

-- html to markdown; base is the page URL, for links that start with '/'
function M.markdown(html, base)
	local lower, out = html:lower(), {}
	local pos, pre, lists, href = 1, 0, {}, {}
	local origin = base and base:match('^(https?://[^/]+)') or ''

	local function emit(s)
		out[#out + 1] = s
	end
	local function link(url)
		url = decode(url or '')
		return url:sub(1, 1) == '/' and url:sub(2, 2) ~= '/' and origin .. url or url
	end
	local function text(s)
		s = decode(s)
		if pre == 0 then
			s = s:gsub('%s+', ' ')
			local last = out[#out]
			if not last or last:match('[\n ]$') then
				s = s:gsub('^ ', '')
			end
		end
		if s ~= '' then
			emit(s)
		end
	end

	while pos <= #html do
		local lt = html:find('<', pos, true)
		if not lt then
			text(html:sub(pos))
			break
		end
		text(html:sub(pos, lt - 1))
		if html:sub(lt, lt + 3) == '<!--' then
			local e = html:find('-->', lt + 4, true)
			pos = e and e + 3 or #html + 1
		else
			local gt = html:find('>', lt + 1, true) or #html
			local close, name, attrs = html:sub(lt + 1, gt - 1):match('^(/?)%s*([%w]+)(.*)$')
			pos = gt + 1
			name = name and name:lower()
			if not name then
				-- <!doctype>, a stray '<' or similar
			elseif close == '' and skipped[name] then
				local e = lower:find('</' .. name, pos, true)
				pos = e or #html + 1
			elseif name:match('^h[1-6]$') then
				emit(close == '' and '\n\n' .. string.rep('#', tonumber(name:sub(2))) .. ' ' or '\n\n')
			elseif name == 'br' then
				emit('\n')
			elseif name == 'hr' then
				emit('\n\n---\n\n')
			elseif name == 'pre' then
				pre = math.max(0, pre + (close == '' and 1 or -1))
				emit(close == '' and '\n\n```\n' or '\n```\n\n')
			elseif name == 'code' and pre == 0 then
				emit('`')
			elseif name == 'strong' or name == 'b' then
				emit('**')
			elseif name == 'em' or name == 'i' then
				emit('*')
			elseif name == 'a' then
				if close == '' then
					href[#href + 1] = link(attr(attrs, 'href'))
					emit('[')
				else
					emit('](' .. (table.remove(href) or '') .. ')')
				end
			elseif name == 'img' then
				emit('![' .. decode(attr(attrs, 'alt') or '') .. '](' .. link(attr(attrs, 'src')) .. ')')
			elseif name == 'li' and close == '' then
				local l = lists[#lists]
				local mark = '- '
				if l and l.ordered then
					l.n = l.n + 1
					mark = l.n .. '. '
				end
				emit('\n' .. string.rep('  ', math.max(#lists - 1, 0)) .. mark)
			elseif name == 'tr' then
				emit('\n')
			elseif (name == 'td' or name == 'th') and close == '' then
				emit(' | ')
			elseif blocks[name] then
				local list = name == 'ul' or name == 'ol'
				local nested = list and #lists > (close == '' and 0 or 1)
				if list and close == '' then
					lists[#lists + 1] = { ordered = name == 'ol', n = 0 }
				elseif list then
					table.remove(lists)
				end
				if not nested then
					emit(name == 'blockquote' and close == '' and '\n\n> ' or '\n\n')
				end
			end
		end
	end
	local md = table.concat(out):gsub('[ \t]+\n', '\n'):gsub('\n\n\n+', '\n\n')
	return (md:gsub('^%s+', ''):gsub('%s+$', ''))
end

sclop.tools.register{
	name = 'webfetch',
	description = 'Fetch a URL. HTML pages are turned into markdown, other text comes as is. '
		.. 'format: "markdown" (default) or "html" for the raw page.',
	schema = {
		type = 'object',
		properties = {
			url = { type = 'string', description = 'http or https URL' },
			format = { type = 'string', enum = sclop.json.array{ 'markdown', 'html' } },
		},
		required = sclop.json.array{ 'url' },
	},
	summary = function(a)
		return a.url
	end,
	run = function(a, done)
		local url = a.url or ''
		if not url:match('^https?://') then
			return done('the url must start with http:// or https://', true)
		end
		local chunks, size, h, err = {}, 0, nil, nil
		h, err = sclop.http{
			url = url,
			timeout = 30000,
			headers = { accept = 'text/html,text/plain,*/*;q=0.5' },
			on_data = function(c)
				size = size + #c
				if size > MAX then
					h:cancel()
					return done('the response is larger than 5 MB', true)
				end
				chunks[#chunks + 1] = c
			end,
			on_done = function(status, err)
				local body = table.concat(chunks)
				if err then
					return done(err, true)
				elseif status >= 400 then
					return done('HTTP ' .. status .. '\n' .. body:sub(1, 2000), true)
				end
				local head = body:sub(1, 2048):lower()
				if a.format ~= 'html' and (head:find('<html') or head:find('<!doctype html')) then
					body = M.markdown(body, url)
				end
				done(util.truncate(body, 5000, 100 * 1024))
			end,
		}
		if not h then
			return done(err, true)
		end
		return function()
			h:cancel()
		end
	end,
}

return M
