---
title: Lua API
lang: en
---

# Lua API

sclop's runtime is LuaJIT. Everything the agent does is Lua, built on a small C module.

- `sclop` is a global table: settings, events, keys, the input, the agent, the view and helpers.
- `sclop.core` (also `require('sclop.core')`) holds the C functions.

LuaJIT means Lua 5.1 syntax with LuaJIT's extensions, including `ffi` and `bit`. For code
written for newer Lua, sclop provides `utf8.char`, `utf8.codepoint`, `utf8.len` and
`utf8.charpattern`.

## How it runs

There is one event loop, in C. Every input calls into Lua: a key, a paste, a resize, a
timer, output of a process, data from HTTP. Handlers change state, which is plain Lua
tables, and call `sclop.redraw()`. At the end of each turn of the loop sclop emits DRAW
and, if a redraw was asked for, calls `sclop.view.render()` and draws the lines it
returns. This is the Elm architecture without the immutable model: change state in
handlers, describe the screen in view functions, and do not draw from handlers.

Finished text goes to the scrollback with `sclop.commit()` and cannot be changed later.

## Events

```lua
sclop.events.subscribe(event, fn)
sclop.events.unsubscribe(event, fn)   -- true if fn was subscribed
sclop.events.emit(event, ...)
```

`emit` calls the handlers in the order they subscribed and stops at the first one that
returns something other than nil; it returns that value. Handlers that only watch should
return nothing.

| Event | Arguments | Notes |
|---|---|---|
| START | | the terminal has started (interactive mode only) |
| QUIT | | sclop is exiting, in every mode |
| KEY | key | return true when you handled the key: the keymap is skipped |
| PASTE | text | return true when you handled it: the text is not inserted |
| RESIZE | cols, rows | |
| DRAW | | every turn of the loop, before the view is drawn |
| STATUS | segs | append strings to `segs` to show them in the status line |
| SUBMIT | text | return true when you took the input: it is cleared and not sent |
| MESSAGE | msg | a message was added to the conversation |
| STREAM | kind, delta | `kind` is `'text'` or `'thinking'` |
| TOOL_CALL | call | return `'allow'`, `'ask'` or `'deny'` to decide the permission |
| TOOL_RESULT | call, text, is_error | |
| TURN_END | | the agent finished or stopped a turn |
| COMPACT | summary | the conversation was replaced by a summary |
| ERROR | message | a Lua error escaped a callback |

The constants are `sclop.events.KEY` and so on; their values are lowercase strings (`'key'`).

## Modes and keys

```lua
sclop.modes                               -- { INPUT = 'input', ASK = 'ask' }
sclop.mode                                -- the current mode
sclop:map(mode, key, action [, help])     -- action: function(key), or the name of another key
sclop:unmap(mode, key)
sclop:mappings(mode)                      -- a copy: key -> function or key name
sclop:feedkeys(bytes)                     -- handle bytes as if they were typed
sclop:dokey(key)                          -- run a key through the current mode's keymap
sclop.defaults[mode] = function(key) end  -- what keys without a mapping do
```

A key goes through the KEY event, then the keymap of the current mode, then
`sclop.defaults[mode]`. In INPUT mode the default inserts printable characters. ASK mode
is used while a tool waits for permission. A plugin can add a mode: set `sclop.mode` to
a new name and map keys in it.

Key names:

- Printable characters stand for themselves: `a`, `A`, `<`, `한`, `' '` (space).
- Special keys: `<Enter>` `<Tab>` `<S-Tab>` `<Backspace>` `<Escape>` `<Delete>` `<Insert>`
  `<Home>` `<End>` `<PageUp>` `<PageDown>` `<Up>` `<Down>` `<Left>` `<Right>`
  `<F1>`…`<F12>` `<C-Space>`.
- Control: `<C-a>`…`<C-z>`, `<C-\>`, `<C-]>`, `<C-^>`, `<C-_>`. Ctrl+H is `<C-h>`,
  DEL (0x7f) is `<Backspace>`, CR is `<Enter>`, LF (Ctrl+J) is `<C-j>`.
- Alt: `<M-x>`, `<M-Enter>`, `<M-Backspace>`; with Ctrl, `<C-M-a>`.
- Modifiers on special keys: `<C-Left>`, `<S-Up>`, `<M-PageUp>`, always in the order
  `C-`, `M-`, `S-`.
- ESC with nothing after it for 50 ms is `<Escape>`; followed by a key, it means Alt
  with that key.

## Input

`sclop.input` is the input buffer. Positions are byte offsets that start at 0.

| Field or method | |
|---|---|
| `text`, `pos` | the text and the cursor; setting `pos` directly is fine |
| `:insert(s)` | insert at the cursor and move after the inserted text |
| `:delete(pos, len)` | delete `len` bytes; the cursor moves with the text |
| `:content(pos, len)` | the bytes at `pos` |
| `:set(text [, pos])` | replace the text; `pos` defaults to the end |
| `:prevchar([pos])`, `:nextchar([pos])` | the UTF-8 character boundary before / after |
| `:linestart([pos])`, `:lineend([pos])` | the bounds of the line |
| `:wordprev([pos])`, `:wordnext([pos])` | word motions; words are separated by white space |
| `:vertical(dir)` | one line up (`dir < 0`) or down, keeping the display column; false at the edge |
| `:push_history(text)`, `:history_move(dir)` | the input history |
| `history` | inputs sent so far |

The methods call `sclop.redraw()`.

## Commands

```lua
sclop:command_register(name, fn, help)   -- '/name args' calls fn(args)
sclop:command(line)                      -- run a '/...' line; false if the name is unknown
```

Built in: `help`, `quit`, `clear`, `model`, `compact`.

`sclop.submit(text)` is what Enter calls: it emits SUBMIT, runs a command, or gives the
text to the agent, and returns true if the text was taken.

## Output

| | |
|---|---|
| `sclop.redraw()` | draw the view at the end of this turn of the loop |
| `sclop.commit(text)` | print text into the scrollback, above the live region |
| `sclop.info(text)` | commit, dimmed |
| `sclop.error(text)` | commit in red; to stderr when there is no terminal |
| `sclop.style.NAME(s)` | colors: bold, dim, italic, red, green, yellow, blue, magenta, cyan, gray |
| `sclop.term` | true once the terminal runs (interactive mode) |
| `sclop.quit([code])` | stop the loop and exit |

Shown text may contain SGR color sequences and OSC 8 links. Other escape sequences and
control characters are removed, so tool output cannot move the cursor.

## Timers, processes and HTTP

```lua
local t = sclop.timer(ms, fn [, repeat])   -- t:stop()
```

```lua
local p, err = sclop.spawn{
	argv = { 'git', 'status' },   -- run directly, no shell
	cwd = 'dir',                  -- optional
	stdin = 'text',               -- a string is written, then closed; true keeps it open
	merge = true,                 -- stderr into stdout
	on_stdout = function(data) end,
	on_stderr = function(data) end,
	on_exit = function(code, signal) end,
}
p:write(s)   p:close()   p:kill([signal])   -- signal 15 by default
```

The child runs in a session of its own and `kill` signals its whole process group.
`on_exit` comes after all of the output. If the child exits while something it started
still holds its output open, sclop stops waiting after 200 ms. There is no option for
the environment; run `{ 'env', 'NAME=value', ... }`.

```lua
local h, err = sclop.http{
	url = 'https://example.com',
	method = 'POST',              -- default: POST if there is a body, else GET
	headers = { ['content-type'] = 'application/json' },
	body = '...',
	timeout = 30000,              -- ms for the whole transfer, optional
	on_data = function(chunk) end,
	on_done = function(status, err) end,
}
h:cancel()   -- no callbacks after this
```

Redirects are followed and compressed bodies decoded. An HTTP error such as 404 arrives
as data with its status; `err` is set only when the transfer itself failed.

## JSON

```lua
sclop.json.encode(value)   -- a string; raises an error for values JSON cannot hold
sclop.json.decode(s)       -- the value, or nil and an error
sclop.json.null            -- JSON null
sclop.json.array([t])      -- mark a table as an array; needed for empty arrays
```

- Object keys are written sorted, so the same value always gives the same bytes.
- A table with the keys 1..n is an array and an empty table is `{}`. Write
  `json.array()` for `[]`. Other tables need string keys.
- Invalid UTF-8 in strings becomes U+FFFD.
- Decoded arrays are marked as arrays. A `null` inside an array becomes `sclop.json.null`;
  inside an object, the key is left out.

## The agent

`sclop.agent` runs the conversation.

| Field | |
|---|---|
| `messages` | the conversation |
| `busy` | a turn is running |
| `tokens` | input and output tokens of the last request |
| `partial` | the unfinished line of the reply |
| `thinking` | the thoughts being streamed, or nil |
| `running` | `{ call = ..., output = ... }` of the tool that runs, or nil |
| `asking` | the call waiting for permission, or nil |

| Function | |
|---|---|
| `submit(text)` | add a user message and start a turn |
| `abort()` | stop the request or tool, and answer the remaining tool calls with an error |
| `clear()` | forget the conversation |
| `compact()` | replace the conversation with a summary; false if busy or empty |
| `push(msg)` | add a message and emit MESSAGE |
| `system_prompt()` | the system prompt of the next request |
| `tool_list()` | the tools offered to the model, sorted by name |
| `decide(call)` | the permission of a call |
| `ask(call, answer)` | asks the user; calls `answer('y')`, `answer('n')` or `answer('a')`. Replace it to ask differently |
| `summary(text)` | the messages that replace a compacted conversation |
| `compact_prompt` | the instruction used for compaction |

Messages do not depend on the provider:

```lua
{ role = 'user', content = {
	{ type = 'text', text = '...' },
	{ type = 'tool_result', id = '...', content = '...', is_error = false },
} }
{ role = 'assistant', content = {
	{ type = 'thinking', thinking = '...', signature = '...' },
	{ type = 'text', text = '...' },
	{ type = 'tool_call', id = '...', name = '...', args = { ... } },
} }
```

## Tools

```lua
sclop.tools.register{
	name = 'hello',
	description = 'Greet someone.',             -- or a function that returns the text
	schema = {                                  -- JSON Schema of the arguments
		type = 'object',
		properties = { name = { type = 'string' } },
		required = { 'name' },
	},
	run = function(args, done, progress)
		done('hello ' .. args.name)               -- done(text [, is_error])
	end,
	summary = function(args) return args.name end,           -- optional, shown after the name
	render = function(text, is_error, args) return nil end,  -- optional result line; nil: default
	available = function() return true end,                  -- optional: offer it now?
}
```

`run` can call `done` at once or later. It can return a function that cancels the work;
Esc calls it. `progress(text)` shows output while the tool runs. An error raised in
`run` becomes an error result. `sclop.tools.NAME = nil` removes a tool.

## Providers

A provider is an object with a `stream` method:

```lua
function provider:stream(req, h)
	-- req = { model, system, messages, tools = { { name, description, schema }... }, max_tokens }
	-- while streaming: h.text(delta), h.thinking(delta)
	-- then exactly one of h.done(msg, { input = n, output = n }) or h.error(message)
	return { cancel = function() end }
end
```

Register it with `sclop.providers.NAME = provider`.
`require('sclop.providers.anthropic').new{...}` and `require('sclop.providers.openai').new{...}`
make the built-in kinds; see [configuration](configuration.md#models-and-providers).

## The view

`sclop.view` holds the functions that describe the screen. Replace or wrap any of them.

| Function | |
|---|---|
| `render()` | → lines, cursor row, cursor byte column: the whole live region |
| `live(lines)` | append work in progress: thinking, the partial reply, tool output, the permission question |
| `input(lines)` | append the input lines; returns the cursor row and column |
| `status()` | the status line |
| `separator()`, `prompt(n)` | the rule above the input; the prefix of input line `n` |
| `user(text)`, `assistant(text)`, `thought(ms)` | formats of committed text |
| `tool(call, tool)`, `result(call, text, is_error, tool)` | the lines of a tool call and its result |
| `replay(messages)` | print a restored conversation |
| `tokens(n)`, `clip(s, w)`, `tail(s, w)` | `12.3k`; cut to `w` columns keeping the start / the end |

A clock in the status line, and a hint above an empty conversation:

```lua
sclop.events.subscribe(sclop.events.STATUS, function(segs)
	segs[#segs + 1] = os.date('%H:%M')
end)
sclop.timer(30000, sclop.redraw, true)

local live = sclop.view.live
sclop.view.live = function(lines)
	live(lines)
	if #sclop.agent.messages == 0 then
		lines[#lines + 1] = sclop.style.gray('type a task and press Enter')
	end
end
```

## Sessions

`sclop.session`: `dir()`, `write(entry)`, `load(path)` → messages, `latest()`,
`resume(path?)` → path and message count, `reset()` (the next message starts a new file),
`enable()`, and `path`, the current file. `resume` continues the given session file
(a relative path from the working directory), or the latest one when there is no path.

A session file holds one JSON value per line: a header
`{"type":"session","model":...,"cwd":...}`, then every message, and
`{"type":"compact","summary":...}` where the conversation was compacted.

`sclop.log` is what the `sclog` command runs: `render(path, opts)` returns the text of
one session file, or nil and an error, and `main(args)` parses a command line and
returns an exit code. `opts.thinking`, `opts.tools` and `opts.verbose` are the three
flags of the command; `main` maps `--thinking`, `--tools`, `--verbose` and `--all` onto
them. The format is deliberate: no escape sequences, so the text survives a pipe.

```lua
-- a session file as the model would read it, not the screen
local text = require('sclop.log').render(path, { tools = true })
```

## Helpers

`sclop.util`:

| | |
|---|---|
| `expand(path)` | replace a leading `~` |
| `quote(s)` | quote for the shell |
| `has(cmd)` | is the command installed |
| `lines(text)` | split into lines |
| `truncate(text, max_lines, max_bytes [, tail])` | keep the start, or the end, and say how much was cut |
| `capture(argv, done [, opts])` | run a command and collect its output: `done(output, code, signal)`; `opts.cwd`, `opts.progress` |

Also `sclop.cwd`, `sclop.platform` (`'linux/x64'`), `sclop.version` and
`sclop.set_model(spec)`.

## sclop.core

| Function | |
|---|---|
| `term_start()` → true, or nil and an error | raw mode, bracketed paste, start reading keys |
| `term_stop()` | give the terminal back |
| `size()` → cols, rows | |
| `draw(lines, row, col)` | draw the live region; `row` indexes `lines`, `col` is a byte offset in that line |
| `commit(text)` | print above the live region; plain stdout without a terminal |
| `write(s)` | write bytes as they are |
| `reset()` | forget the last frame; the next draw starts where the cursor is |
| `width(s)` | display width in columns |
| `feed(bytes)` | decode and handle input bytes |
| `timer(ms, fn [, repeat])` → id, `timer_stop(id)` | |
| `watch(fd, 'r' \| 'w' \| 'rw', fn)`, `unwatch(fd)` | call `fn(events)` when the fd is ready; `events` holds `r`, `w`, `e` |
| `spawn(opts)` → id, `proc_write(id, s)`, `proc_close(id)`, `proc_kill(id [, signal])` | |
| `http(opts)` → id, `http_cancel(id)` | |
| `json_encode`, `json_decode`, `null`, `array_mt` | |
| `now()` | milliseconds of a monotonic clock |
| `quit([code])` | |
| `version` | |
| `dispatch` | set by the runtime: C calls `dispatch(event, ...)` for key, paste, resize, draw, error and quit |

`watch` puts your own file descriptors on the loop, for example a socket or a FIFO
opened with `ffi` (see [plugins](plugins.md#reading-a-fifo-with-ffi)). Unwatch before
closing the fd, and do not watch descriptors sclop itself uses, such as 0.
