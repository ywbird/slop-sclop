# sclop

A minimal coding agent for the terminal, written in C and LuaJIT. If opencode and pi are
neovim and vim, sclop is vis.

The C core does the event loop, the terminal, the screen, child processes, HTTP and
JSON. The conversation loop, the providers, the tools, the input editor and the screen
layout are Lua, and your configuration can change any of them.

- Inline UI: output stays in your terminal's scrollback; only the bottom is redrawn
- Anthropic and OpenAI-compatible APIs, streaming, prompt caching, thinking
- Tools: read, write, edit, bash, grep, glob, skill
- Per-tool permissions, sessions, context compaction, a non-interactive mode
- Lua plugins: a Korean input method, questions to the user, web fetching
- Links only libc, LuaJIT and libcurl

## Quick start

```sh
make
export ANTHROPIC_API_KEY=...
./sclop
```

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
