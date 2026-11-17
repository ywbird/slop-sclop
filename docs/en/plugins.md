---
title: Plugins
lang: en
---

# Plugins

A plugin is a Lua module. There is no plugin manager: put the file where Lua finds
modules and `require` it from your configuration.

The configuration directory is on the module path, so:

```
~/.config/sclop/plugins/hello.lua        -> require('plugins/hello')
~/.config/sclop/plugins/hello/init.lua   -> require('plugins/hello')
```

The second form suits `git clone` into `~/.config/sclop/plugins/`. A file in the
configuration directory wins over a bundled file with the same name.

C works too: `~/.config/sclop/foo.so` is loaded by `require('foo')` (it must export
`luaopen_foo`), and LuaJIT's `ffi` calls C functions without any module at all.

## Writing a plugin

A plugin uses the same [Lua API](lua-api.md) as the runtime. Some conventions:

- Return a table. If the plugin needs options or should not act just by being loaded,
  do the work in `setup(opts)`.
- Leave keys alone unless the user asked for them; show how to map them instead.
- Change state in handlers and call `sclop.redraw()`; describe the screen in view
  functions.

### A status segment and a command

Show the git branch in the status line, refreshed after each turn:

```lua
-- ~/.config/sclop/plugins/git-branch.lua
local M = {}
local branch

local function refresh()
	sclop.util.capture({ 'git', 'branch', '--show-current' }, function(out, code)
		branch = code == 0 and out:match('[^\n]+') or nil
		sclop.redraw()
	end)
end

function M.setup()
	sclop.events.subscribe(sclop.events.START, refresh)
	sclop.events.subscribe(sclop.events.TURN_END, refresh)
	sclop.events.subscribe(sclop.events.STATUS, function(segs)
		if branch then
			segs[#segs + 1] = '⎇ ' .. branch
		end
	end)
	sclop:command_register('branch', refresh, 'refresh the git branch')
end

return M
```

```lua
require('plugins/git-branch').setup()
```

### A tool with its own view

A task list the model keeps up to date, shown above the input:

```lua
-- ~/.config/sclop/plugins/todo.lua
local items = {}

sclop.tools.register{
	name = 'todo',
	description = 'Replace your task list. Use it for work with several steps; mark finished items done.',
	schema = {
		type = 'object',
		properties = {
			items = {
				type = 'array',
				items = {
					type = 'object',
					properties = { text = { type = 'string' }, done = { type = 'boolean' } },
					required = { 'text' },
				},
			},
		},
		required = { 'items' },
	},
	run = function(args, done)
		items = args.items or {}
		sclop.redraw()
		done('the list has ' .. #items .. ' items')
	end,
}

local live = sclop.view.live
sclop.view.live = function(lines)
	live(lines)
	for _, item in ipairs(items) do
		lines[#lines + 1] = (item.done and '  ✓ ' or '  ☐ ') .. item.text
	end
end

return {}
```

### Reading a FIFO with ffi

Prompts written to a named pipe are sent to the agent, so other programs can drive
sclop. This uses `ffi` to open the pipe and `sclop.core.watch` to put it on the event
loop. The flag values are Linux's.

```lua
-- ~/.config/sclop/plugins/fifo.lua
-- Linux: O_RDWR keeps the FIFO open, so reads never see end of file
local ffi = require('ffi')
ffi.cdef[[
int open(const char *path, int flags);
long read(int fd, void *buf, unsigned long n);
]]
local O_RDWR, O_NONBLOCK = 2, 2048

local M = {}

function M.setup(path)
	os.execute('mkfifo ' .. sclop.util.quote(path) .. ' 2>/dev/null')
	local fd = ffi.C.open(path, O_RDWR + O_NONBLOCK)
	assert(fd >= 0, 'cannot open ' .. path)
	local buf = ffi.new('char[4096]')
	sclop.core.watch(fd, 'r', function()
		local n = tonumber(ffi.C.read(fd, buf, 4096))
		local text = n > 0 and ffi.string(buf, n):gsub('%s+$', '')
		if text and text ~= '' and not sclop.agent.busy then
			sclop.agent.submit(text)
		end
	end)
end

return M
```

```lua
require('plugins/fifo').setup('/tmp/sclop.fifo')
```

```sh
echo 'run the tests and fix what fails' > /tmp/sclop.fifo
```

### Trying a plugin without the UI

`sclop -l` runs a Lua file with the runtime loaded, which is handy for checking a plugin:

```lua
-- check.lua
require('plugins/todo')
sclop.tools.todo.run({ items = { { text = 'a', done = true } } }, function(text) print(text) end)
sclop.quit()
```

```sh
SCLOP_PATH=~/.config/sclop sclop -l check.lua
```

## Bundled plugins

### korean-ime

Korean input (두벌식, the standard two-set layout) inside sclop's input, independent of
the operating system's input method. Useful over SSH, on a bare console, or when the
terminal's input method misbehaves. It is a port of
[vis-korea-ime](https://codeberg.org/ywbird/vis-korea-ime), itself a port of
[Korean-IME.nvim](https://github.com/kiyoon/Korean-IME.nvim).

```lua
local ime = require('plugins/korean-ime')
ime.setup()
sclop:map(sclop.modes.INPUT, '<M-\\>', ime.change_mode)   -- Alt+\ switches 한/EN
```

| | |
|---|---|
| `setup()` | take over the printable keys (`!` to `~`), space and Backspace in INPUT mode, and Ctrl+H when it is the default alias of Backspace |
| `change_mode()` | switch between `'en'` and `'ko'` |
| `get_mode()`, `set_mode(mode)` | read or set the mode |

In Korean mode the status line shows `한`. Typing `dkssudgktpdy` gives 안녕하세요, and
Backspace takes back one jamo at a time. A syllable is finished when the cursor moves or
the text changes in another way, for example by pasting. Only INPUT mode is affected, so
the answers to a permission question (`y`, `n`, `a`) stay plain keys.

### question

Gives the model a `question` tool to ask you something and wait for the answer.

```lua
require('plugins/question')
```

The model sends one or more questions, each with optional options:

```json
{ "questions": [
  { "question": "Which database?", "options": [
      { "label": "sqlite" }, { "label": "postgres", "description": "needs a server" } ],
    "multiple": false } ] }
```

The question and numbered options appear above the input. Answer in the input box:
an option number, several numbers separated by commas, or your own words, then Enter.
Several questions come one after another. The model gets `Q: …` / `A: …` pairs. Esc
stops the turn. With korean-ime you can answer in Korean.

### webfetch

Gives the model a `webfetch` tool that fetches a URL.

```lua
require('plugins/webfetch')
```

- Arguments: `url` (http or https), `format`: `'markdown'` (default) or `'html'`.
- 30 second timeout, at most 5 MB. The result is cut to 5000 lines and 100 KB.
- A page that looks like HTML is turned into markdown: headings, paragraphs, links
  (paths starting with `/` become absolute), images, bold and italic, code and `pre`
  blocks, nested lists, table rows, block quotes. `script`, `style`, `head`, `svg`,
  `noscript`, `template` and `iframe` are dropped and entities decoded. Other content
  comes back as it is.
- `require('plugins/webfetch').markdown(html, base_url)` does the conversion alone.
- To confirm each fetch: `sclop.permissions.webfetch = 'ask'`.
