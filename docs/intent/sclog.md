# Intent: `sclog`

A standalone shell command that prints a session `.jsonl` file as readable plaintext.

## Confirmed intent

- **Outcome**: `sclog FILE` prints the whole session `.jsonl` to stdout as plaintext, in time order.
  - Default: conversation only. Neither thinking nor tool calls/results are shown.
  - `--thinking`: show thinking blocks.
  - `--tools`: show the tool call as one line plus 3 lines of its result and `… N more lines`.
  - `--verbose`: implies `--tools` and shows tool results in full.
  - `--all`: `--thinking` + `--verbose` (i.e. all three).
- **User**: fzf preview (`fzf --preview='sclog {}'`), and me re-reading past sessions alone.
- **Why now**: sessions already pile up in `.sclop/sessions`, but there is no way to read them.
- **Success**: no ANSI/color, does not break when piped, tens of ms per file, the header is a single first line.
- **Constraint**: a standalone shell command. The logic lives in `lua/sclop/log.lua`, and the `sclog`
  script at the repo root delegates with `exec sclop -l .../log.lua "$@"`. Included in `make install`.

## Out of scope

- Any option other than the above flags (`--thinking`, `--tools`, `--verbose`, `--all`),
  including picking the latest session when the argument is omitted
- An `fzf` wrapper or picker (a separate script can call `sclog`)
- ANSI/color/box rendering
- A slash command (`/log`)
- Adding C code
- External dependencies such as `jq`

## Output format

```
model · cwd
> user message
assistant text

● bash ls -la
  ⎿ LICENSE
    Makefile
    … 42 more lines
```

- The first line is the session header (`model · cwd`), one line.
- User messages take a `> ` prefix; continuation lines are indented by two spaces.
- In the default mode, thinking and tool calls/results are all omitted.
- `--tools`: a tool call is one line, `● name summary`, and its result goes under `  ⎿ ` as
  3 lines plus `… N more lines`.
- `--verbose`: implies `--tools` and appends the full tool result.
- `--thinking`: prints thinking in full as a `∴ ` block.
- A `tool_result` carried in a user message is not emitted as its own block; it is attached
  under the matching tool call.

## Implementation notes

- In `sclop -l script.lua args...` the trailing arguments arrive as the script's `...`, and the C
  side also fills the global `arg` (`lua_setglobal(L, "arg")` in `lua.c`, as `test/run.lua` uses it).
- The JSON parser (`sclop.json`) and session header handling already exist in Lua.
- An unknown flag writes usage to stderr and exits 1.
