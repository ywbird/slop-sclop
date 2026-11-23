---
title: Getting started
lang: en
---

# Getting started

sclop is a small coding agent for the terminal. A C core runs the event loop, the
terminal, the screen, child processes, HTTP and JSON. Everything the agent does is Lua
code that your configuration can change.

## Build and install

You need a C99 compiler, make, pkg-config, LuaJIT 2.1 and libcurl.

```sh
make
make test
make install
```

`make test` runs the test suite (`./sclop -l test/run.lua`). When `python3` is
installed it also tests real HTTP against a small mock server, `test/mock.py`.

Build settings are in `config.mk`:

| Variable | Default | Meaning |
|---|---|---|
| `PREFIX` | `/usr/local` | install prefix |
| `SHAREDIR` | `$(PREFIX)/share/sclop` | where the Lua runtime goes |
| `PKGS` | `luajit libcurl` | pkg-config packages |
| `CC`, `CFLAGS`, `LDFLAGS` | | compiler and flags |

`make install` copies the binary and the `sclog` script to `$(PREFIX)/bin` and the
`lua/` directory to `$(SHAREDIR)`, and respects `DESTDIR`.

The binary looks for Lua modules in these places, in order:

1. the directories in `$SCLOP_PATH` (separated by colons)
2. the configuration directory: `$XDG_CONFIG_HOME/sclop`, or `~/.config/sclop`
3. `lua/` next to the executable, so `./sclop` works in the source tree
4. `../share/sclop` relative to the executable, so an installed tree can be moved
5. the `SHAREDIR` it was built with

The configuration directory comes early, so a file there with the same name as a
runtime module replaces that module.

## API keys

| Provider | Variable |
|---|---|
| `anthropic` (default) | `ANTHROPIC_API_KEY` |
| `openai` | `OPENAI_API_KEY` |

Keys can also be set in the configuration file, see [configuration](configuration.md).

## Running

```sh
sclop                       # interactive
sclop -m openai/gpt-5       # choose a model
sclop -c                    # continue the last session of this directory
sclop -c .sclop/sessions/20251123-101500.jsonl   # continue that session file
sclop -p 'summarize README.md' > summary.txt
```

| Option | Meaning |
|---|---|
| `-m MODEL` | the model. `provider/model` also switches the provider, if one with that name exists |
| `-c [SESSION]` | continue a session: the file at that path, or the most recent one of the working directory |
| `-p [PROMPT]` | answer one prompt without the interactive screen. Reads the prompt from stdin if it is missing or `-` |
| `--allow-TOOL` | with `-p`: run a tool whose permission is `ask`. `--allow-all` allows all of them |
| `-l FILE [ARGS]` | run a Lua file with the runtime loaded, but without the configuration or the terminal |
| `-v`, `-h` | print the version or the usage |

## The screen

sclop does not take over the terminal. Finished output (your messages, the replies, tool
calls and their results) is printed into the normal scrollback, where you scroll, search
and copy with the terminal as usual. Only the bottom of the screen is redrawn:

```
∴ the model's current thought…         while it thinks
a reply line that is still arriving
  │ output of a running tool
Allow bash? [y]es [n]o [a]lways         when a tool needs permission
─────────────────────────────────────
> your input
anthropic/claude-sonnet-4-5  12.3k tokens  ⠋
```

The status line shows the provider and model, the size of the last request in tokens,
a spinner while the agent works, and anything plugins add.

While the model thinks, its thoughts appear dimmed at the bottom; afterwards only a line
like `∴ thought for 12s` stays in the scrollback.

## Keys

| Key | Action |
|---|---|
| Enter | send |
| Alt+Enter, Ctrl+J | new line |
| Backspace, Ctrl+H / Delete | delete the character before / after the cursor |
| ← →, Ctrl+B / Ctrl+F | move by character |
| Alt+B / Alt+F, Ctrl+← / Ctrl+→ | move by word |
| Home / End, Ctrl+A / Ctrl+E | start / end of the line |
| ↑ ↓, Ctrl+P / Ctrl+N | move between lines; on the first or last line, browse earlier inputs |
| Ctrl+W, Alt+Backspace | delete the word before the cursor |
| Ctrl+U / Ctrl+K | delete to the start / end of the line |
| Esc | stop the current reply or tool |
| Ctrl+C | stop; if idle, clear the input; if it is empty, quit |
| Ctrl+D | quit if the input is empty, else delete the character after the cursor |
| Ctrl+L | clear the screen |

Pasted text is inserted as it is, newlines included. While the agent works, Enter does
nothing and your text stays in the input.

When a tool asks for permission: `y` allows it once, `n` denies it, `a` allows this tool
until you quit, Esc denies, and Ctrl+C stops the turn.

## Commands

| Command | Action |
|---|---|
| `/help` | list the commands |
| `/model [provider/]model` | show or change the model |
| `/clear` | start a new conversation and a new session file |
| `/compact` | summarize the conversation to free context |
| `/quit` | exit |

Input that starts with `/` but names no command is sent to the model as it is.

## Tools

| Tool | What it does |
|---|---|
| `read` | read a text file with line numbers: up to 2000 lines and 64 KB per call, pages with `offset` and `limit`. A directory gives its entries |
| `write` | create or replace a file, creating missing directories |
| `edit` | replace a string that occurs exactly once, or every occurrence with `replace_all` |
| `bash` | run a shell command. Output is merged and only its last 50 KB kept; killed after 2 minutes unless the call sets `timeout` |
| `grep` | search file contents with ripgrep, or grep if ripgrep is missing; up to 200 lines |
| `glob` | find files by pattern with ripgrep or find; up to 500 paths |
| `skill` | load a skill's instructions; offered only when skills exist |

By default every tool runs without asking, except `read` on `.env` files.
[Configuration](configuration.md#permissions) shows how to change that.

## Sessions

Every message is appended to `.sclop/sessions/<time>.jsonl` in the working directory.
When sclop creates that directory it also writes `.sclop/.gitignore`, so the session
files, which can contain secrets from tool output, stay out of git. `sclop -c` loads the
most recent session, prints it, and keeps appending to it. `sclop -c .sclop/sessions/<time>.jsonl`
continues that file instead: a relative path is taken from the working directory, and a missing
file or a file that is not a session is an error.

### Reading a session

`make install` also puts `sclog` on your `PATH`. It prints one session file as plain text:
the header (`model · cwd`), then the conversation in order. The file argument is required.

| Option | Shows |
|---|---|
| | the user and assistant text only |
| `--thinking` | also thinking blocks |
| `--tools` | also each tool call, with the first three lines of its result and `… N more lines` |
| `--verbose` | the whole tool result; implies `--tools` |
| `--all` | all three |

The output has no colors and no escape sequences, so it survives pipes and works as an
`fzf` preview. An unknown option, a missing file and more than one file are errors.

```
$ sclog .sclop/sessions/20251123-101500.jsonl
anthropic/claude-sonnet-4-5 · /home/me/project

> why does make test fail?

Let me run it.

● bash make test
  ⎿ ...
    … 12 more lines
```

`sclog` is a plain filter, so a picker is a few lines: list the sessions, preview each
one, and resume the one you choose with `sclop -c`.

```sh
sclog .sclop/sessions/20251123-101500.jsonl        # the conversation
sclog --all .sclop/sessions/20251123-101500.jsonl  # everything

# pick a session and resume it
sclop -c "$(ls -t .sclop/sessions/*.jsonl | fzf --preview 'sclog {}')"
```

## Compaction

When the last request used more than `context_window × compact_at` tokens (200000 × 0.8
by default), sclop asks the model for a summary of the conversation and continues from
the summary. `/compact` does the same at any time. The session file records it.

## AGENTS.md

If the working directory has an `AGENTS.md`, its text is added to the system prompt of
every request.

## Print mode

`sclop -p` sends one prompt, runs the tool loop without a person to ask, prints the
last reply to stdout and exits.

```sh
sclop -p 'why does make test fail?' --allow-bash
echo 'list the TODO comments' | sclop -p
sclop -c -p 'and now fix the first one'
sclop -c .sclop/sessions/20251123-101500.jsonl -p 'continue in that session'
```

- A tool whose permission is `ask` is denied, unless `--allow-TOOL` or `--allow-all`
  allows it. The denial is reported on stderr. With the default permissions only `.env`
  reads ask, so all other tools run: configure `ask` for anything you want held back.
- Errors go to stderr.
- The exit status is 0 on success, 1 on failure and 128 + the signal number if sclop
  was interrupted.
- The configuration is loaded and the session saved as usual.
