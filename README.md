<div align="center">

# sclop

**A minimal coding agent for the terminal, written in C and LuaJIT.**

If opencode and pi are neovim and vim, sclop is vis.

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Language](https://img.shields.io/badge/language-C99%20%2B%20LuaJIT-grey.svg)](SPEC.md)
[![Links](https://img.shields.io/badge/links-libc%20%C2%B7%20LuaJIT%20%C2%B7%20libcurl-grey.svg)](#design)

<img src="assets/AI-X-light.svg" alt="AI:X" width="120">

</div>

## Design

**Mechanism in C, policy in Lua.** The C core does the event loop, the terminal, the
screen, child processes, HTTP and JSON — and nothing else. The conversation loop, the
providers, the tools, the input editor and the screen layout are Lua, and your
configuration can replace any of them.

```
┌─ C core ─────────────────┐      ┌─ Lua (LuaJIT) ────────────────┐
│ loop   term   ui   proc  │◄────►│ agent    providers    tools   │
│ http   json        lua.c │      │ editor   view        plugins  │
└──────────────────────────┘      └───────────────────────────────┘
```

Configuration is a single Lua file. The code stays flat and short, like vis.

## Features

- Inline UI — output stays in your terminal's scrollback; only the bottom is redrawn
- Anthropic and OpenAI-compatible APIs, streaming, prompt caching, thinking
- Tools: `read`, `write`, `edit`, `bash`, `grep`, `glob`, `skill`
- Per-tool permissions (`allow` / `ask` / `deny`), sessions, context compaction,
  a non-interactive mode (`-p`)
- Lua plugins: a Korean input method, questions to the user, web fetching
- `AGENTS.md` loading, runtime module overrides, `make test`

## Quick start

```sh
make
make test
export ANTHROPIC_API_KEY=...
./sclop
```

You need a C99 compiler, make, pkg-config, LuaJIT 2.1 and libcurl.
`OPENAI_API_KEY` selects the OpenAI-compatible provider; keys can also live in the
config file. See [getting started](docs/en/getting-started.md) for install and
runtime paths.

## Documentation

| English | 한국어 |
|---|---|
| [Getting started](docs/en/getting-started.md) | [시작하기](docs/ko/getting-started.md) |
| [Configuration](docs/en/configuration.md) | [설정](docs/ko/configuration.md) |
| [Lua API](docs/en/lua-api.md) | [Lua API](docs/ko/lua-api.md) |
| [Plugins](docs/en/plugins.md) | [플러그인](docs/ko/plugins.md) |

The design notes are in [SPEC.md](SPEC.md) and the work list in [TODO.md](TODO.md)
(both in Korean).

## License

MIT, see [LICENSE](LICENSE). `lua/plugins/korean-ime.lua` comes from
[vis-korea-ime](https://codeberg.org/ywbird/vis-korea-ime) and
[Korean-IME.nvim](https://github.com/kiyoon/Korean-IME.nvim) by Kiyoon Kim.
