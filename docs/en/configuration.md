# Configuration

sclop reads one Lua file at startup: `$XDG_CONFIG_HOME/sclop/init.lua`, or
`~/.config/sclop/init.lua`. It runs after the whole runtime is loaded, so it can change
anything: settings, keys, tools, providers, even the functions the runtime is made of.
If it raises an error, sclop shows it and starts with whatever ran before the error.
Scripts run with `sclop -l` do not load it.

## Settings

| Setting | Default | Meaning |
|---|---|---|
| `sclop.provider` | `'anthropic'` | name of a provider in `sclop.providers` |
| `sclop.model` | `'claude-sonnet-4-5'` | model name sent to the provider |
| `sclop.max_tokens` | `16384` | limit of a reply, sent to Anthropic |
| `sclop.context_window` | `200000` | how many tokens the model takes, for compaction |
| `sclop.compact_at` | `0.8` | compact when the last request used this share of the window |
| `sclop.system` | built in | the base system prompt |
| `sclop.skills` | `{ '~/.agents/skills', '.agents/skills' }` | directories with skills |
| `sclop.permissions` | everything allowed, `.env` reads ask | see [Permissions](#permissions) |

## Models and providers

```lua
sclop.provider = 'openai'
sclop.model = 'gpt-5'
```

The same from the command line, `sclop -m openai/gpt-5`, or inside sclop,
`/model openai/gpt-5`.

Two providers are built in.

**anthropic**, the Anthropic Messages API:

| Field | Default |
|---|---|
| `api_key` | `$ANTHROPIC_API_KEY` |
| `base_url` | `https://api.anthropic.com` |
| `extra` | `{}`, merged into every request body |

**openai**, OpenAI-compatible Chat Completions:

| Field | Default |
|---|---|
| `api_key` | the variable named by `key_env` |
| `key_env` | `'OPENAI_API_KEY'` |
| `base_url` | `https://api.openai.com/v1` |
| `extra` | `{}`, merged into every request body |

Without a key, `openai` sends no `Authorization` header, which suits local servers.

```lua
sclop.providers.anthropic.api_key = 'sk-ant-...'   -- instead of the environment
```

Add other OpenAI-compatible servers with `new`:

```lua
local openai = require('sclop.providers.openai')

sclop.providers.openrouter = openai.new{
	base_url = 'https://openrouter.ai/api/v1',
	key_env = 'OPENROUTER_API_KEY',
}
sclop.providers.ollama = openai.new{ base_url = 'http://localhost:11434/v1' }

sclop.provider = 'openrouter'
sclop.model = 'anthropic/claude-sonnet-4.5'
```

`sclop -m openrouter/anthropic/claude-sonnet-4.5` works as well: the part before the
first `/` names the provider because a provider with that name exists.

Options of the API go into `extra`. Extended thinking on Anthropic:

```lua
sclop.providers.anthropic.extra = {
	thinking = { type = 'enabled', budget_tokens = 8000 },
}
```

`sclop.max_tokens` has to be larger than the budget. OpenAI-compatible servers that
stream `reasoning_content` or `reasoning` show it as thinking without any setting.
sclop sends no reply limit to `openai`; set one with `extra = { max_tokens = 4096 }` if
your server needs it.

On Anthropic the system prompt and the end of the conversation are marked for prompt
caching in every request. sclop keeps the start of each request the same from one
request to the next (tools and JSON keys are sorted) so the cache keeps hitting.

## The system prompt

`sclop.agent.system_prompt()` builds the system prompt of every request from:

1. `sclop.system`, the base text:

   ```
   You are sclop, a minimal coding agent running in the user's terminal.
   You help with software engineering: reading, writing and editing code, and running commands.

   - Look at files before you change them. Prefer small, focused edits.
   - Run commands to check your work when it helps.
   - Keep answers short and direct. The terminal shows plain text, so avoid heavy markdown.
   - Ask before doing anything destructive or irreversible.
   ```

2. the environment:

   ```
   Environment:
   - Working directory: /home/me/project
   - Platform: linux/x64
   - Date: 2026-11-17
   ```

3. the `AGENTS.md` of the working directory, if there is one.

The list of skills goes into the description of the `skill` tool, and each tool's
description is sent with the tool, not in the system prompt.

Change the base text:

```lua
sclop.system = sclop.system .. '\n- Answer in Korean.'
```

Or change how the whole prompt is made:

```lua
local base = sclop.agent.system_prompt
sclop.agent.system_prompt = function()
	return base() .. '\n\nMore rules...'
end
```

Keep the prompt the same between requests. Anything that changes every time, like the
time of day, breaks prompt caching. The default changes once a day, with the date.

The instruction used for compaction is `sclop.agent.compact_prompt`.

## Permissions

Before running a tool, sclop decides on `'allow'`, `'ask'` or `'deny'`, taking the first
answer from:

1. a TOOL_CALL event handler that returns one of the three,
2. `sclop.permissions[name of the tool]`,
3. `sclop.permissions['*']`.

A permission is one of the three strings, or a function that gets the tool's arguments
and returns one.

By default everything is allowed, except that `read` asks for paths that end in `.env`
or contain `.env.` (`.env.example` is allowed).

```lua
-- confirm every shell command
sclop.permissions.bash = 'ask'

-- confirm only some
sclop.permissions.bash = function(args)
	return args.command:match('^%s*rm ') and 'ask' or 'allow'
end

-- never change files
sclop.permissions.write = 'deny'
sclop.permissions.edit = 'deny'

-- ask for tools that have no rule of their own
sclop.permissions['*'] = 'ask'
```

A denied call reaches the model as an error, so it can try something else. Answering
`a` at the prompt sets `sclop.permissions[name] = 'allow'` until you quit. In `-p` mode,
`ask` means deny unless `--allow-NAME` or `--allow-all` is given.

## Skills

A skill is a directory with a `SKILL.md` file whose frontmatter has a `name` and a
`description`:

```markdown
---
name: release
description: How to make a release of this project
---
1. Update the version in config.mk.
...
```

sclop looks for `*/SKILL.md` in each directory of `sclop.skills`; relative paths are
relative to the working directory. The names and descriptions go into the description of
the `skill` tool, and when the model loads a skill it also gets the skill's directory,
to find files that come with it. The list is read once per run.

```lua
sclop.skills = { '~/.agents/skills', '.agents/skills', '~/notes/skills' }
```

## Tools

`sclop.tools` maps names to tools. Remove a tool, or change what the model reads about it:

```lua
sclop.tools.glob = nil
sclop.tools.bash.description = sclop.tools.bash.description .. ' Prefer make targets.'
```

New tools come from plugins or from `sclop.tools.register`, see the
[Lua API](lua-api.md#tools).

## Keys

Map a key in a mode to a function, or to another key:

```lua
local I = sclop.modes.INPUT
sclop:map(I, '<C-o>', function() sclop.input:insert('TODO: ') end)
sclop:map(I, '<C-s>', '<Enter>')     -- Ctrl+S sends too
sclop:unmap(I, '<C-l>')
```

Key names follow vis: plain characters stand for themselves (`a`, `한`, `' '`), special
keys go in angle brackets (`<Enter>`, `<Up>`, `<F5>`), and modifiers are written `C-`,
`M-`, `S-` in that order (`<C-M-Left>`). The [Lua API](lua-api.md#modes-and-keys) has the
whole list.

## Plugins

```lua
local ime = require('plugins/korean-ime')
ime.setup()
sclop:map(sclop.modes.INPUT, '<M-\\>', ime.change_mode)

require('plugins/question')
require('plugins/webfetch')
```

See [plugins](plugins.md).

## Example

```lua
-- ~/.config/sclop/init.lua
local openai = require('sclop.providers.openai')
sclop.providers.openrouter = openai.new{
	base_url = 'https://openrouter.ai/api/v1',
	key_env = 'OPENROUTER_API_KEY',
}

sclop.provider = 'anthropic'
sclop.model = 'claude-sonnet-4-5'
sclop.system = sclop.system .. '\n- Answer in Korean.'

sclop.permissions.bash = function(args)
	return args.command:match('^%s*rm ') and 'ask' or 'allow'
end

local ime = require('plugins/korean-ime')
ime.setup()
sclop:map(sclop.modes.INPUT, '<M-\\>', ime.change_mode)
require('plugins/question')
require('plugins/webfetch')
```
