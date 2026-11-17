# Lua API

sclop의 런타임은 LuaJIT이다. 에이전트가 하는 일은 전부 작은 C 모듈 위에 쓴 Lua다.

- `sclop`은 전역 표다. 설정, 이벤트, 키, 입력, 에이전트, 화면, 도우미가 들어 있다.
- `sclop.core`(`require('sclop.core')`도 같음)는 C 함수 모음이다.

LuaJIT이므로 문법은 Lua 5.1에 LuaJIT 확장(`ffi`, `bit` 등)이 더해진 것이다. 새 버전 Lua용으로
쓴 코드를 위해 `utf8.char`, `utf8.codepoint`, `utf8.len`, `utf8.charpattern`을 채워 둔다.

## 동작 방식

이벤트 루프는 C에 하나 있다. 키, 붙여넣기, 창 크기 변경, 타이머, 프로세스 출력, HTTP 데이터 같은
입력이 생길 때마다 Lua를 부른다. 핸들러는 상태(그냥 Lua 표)를 바꾸고 `sclop.redraw()`를 부른다.
루프가 한 바퀴 돌 때마다 끝에서 DRAW를 내보내고, 다시 그리라는 요청이 있었으면
`sclop.view.render()`를 불러 돌려받은 줄을 그린다. 불변 모델을 뺀 Elm 아키텍처다. 핸들러에서는
상태를 바꾸고, 화면은 view 함수로 표현하고, 핸들러에서 직접 그리지 않는다.

끝난 텍스트는 `sclop.commit()`으로 스크롤백에 보내고, 그 뒤로는 바꿀 수 없다.

## 이벤트

```lua
sclop.events.subscribe(event, fn)
sclop.events.unsubscribe(event, fn)   -- fn이 구독돼 있었으면 true
sclop.events.emit(event, ...)
```

`emit`은 구독한 순서대로 핸들러를 부르다가, 처음으로 nil이 아닌 값을 돌려준 핸들러에서 멈추고
그 값을 돌려준다. 지켜보기만 하는 핸들러는 아무것도 돌려주지 않아야 한다.

| 이벤트 | 인자 | 비고 |
|---|---|---|
| START | | 터미널이 시작됨 (대화형 모드만) |
| QUIT | | 종료할 때, 모든 모드 |
| KEY | key | 처리했으면 true. 키맵을 건너뛴다 |
| PASTE | text | 처리했으면 true. 텍스트를 넣지 않는다 |
| RESIZE | cols, rows | |
| DRAW | | 루프 한 바퀴마다, 화면을 그리기 전 |
| STATUS | segs | `segs`에 문자열을 넣으면 상태줄에 나온다 |
| SUBMIT | text | 입력을 가져갔으면 true. 입력은 비워지고 전송되지 않는다 |
| MESSAGE | msg | 대화에 메시지가 추가됨 |
| STREAM | kind, delta | `kind`는 `'text'` 또는 `'thinking'` |
| TOOL_CALL | call | `'allow'`, `'ask'`, `'deny'`를 돌려주면 권한이 정해진다 |
| TOOL_RESULT | call, text, is_error | |
| TURN_END | | 에이전트가 턴을 끝냈거나 멈춤 |
| COMPACT | summary | 대화가 요약으로 바뀜 |
| ERROR | message | 콜백에서 Lua 오류가 빠져나옴 |

상수는 `sclop.events.KEY` 같은 이름이고 값은 소문자 문자열(`'key'`)이다.

## 모드와 키

```lua
sclop.modes                               -- { INPUT = 'input', ASK = 'ask' }
sclop.mode                                -- 현재 모드
sclop:map(mode, key, action [, help])     -- action: function(key) 또는 다른 키 이름
sclop:unmap(mode, key)
sclop:mappings(mode)                      -- 복사본: key -> 함수 또는 키 이름
sclop:feedkeys(bytes)                     -- 입력한 것처럼 바이트 처리
sclop:dokey(key)                          -- 현재 모드의 키맵으로 키 하나 처리
sclop.defaults[mode] = function(key) end  -- 매핑 없는 키의 동작
```

키는 KEY 이벤트 → 현재 모드의 키맵 → `sclop.defaults[mode]` 순서로 간다. INPUT 모드의 기본
동작은 출력 가능한 문자를 넣는 것이다. ASK 모드는 tool이 권한을 기다리는 동안 쓴다. 플러그인은
모드를 추가할 수 있다. `sclop.mode`에 새 이름을 넣고 그 모드에 키를 매핑하면 된다.

키 이름:

- 출력 가능한 문자는 그대로: `a`, `A`, `<`, `한`, `' '`(스페이스)
- 특수키: `<Enter>` `<Tab>` `<S-Tab>` `<Backspace>` `<Escape>` `<Delete>` `<Insert>`
  `<Home>` `<End>` `<PageUp>` `<PageDown>` `<Up>` `<Down>` `<Left>` `<Right>`
  `<F1>`…`<F12>` `<C-Space>`
- Ctrl: `<C-a>`…`<C-z>`, `<C-\>`, `<C-]>`, `<C-^>`, `<C-_>`. Ctrl+H는 `<C-h>`,
  DEL(0x7f)은 `<Backspace>`, CR은 `<Enter>`, LF(Ctrl+J)는 `<C-j>`
- Alt: `<M-x>`, `<M-Enter>`, `<M-Backspace>`. Ctrl과 함께면 `<C-M-a>`
- 특수키의 수식키: `<C-Left>`, `<S-Up>`, `<M-PageUp>`. 순서는 항상 `C-`, `M-`, `S-`
- ESC 뒤 50ms 동안 아무것도 없으면 `<Escape>`, 뒤에 키가 오면 Alt+그 키

## 입력

`sclop.input`은 입력 버퍼다. 위치는 0부터 시작하는 바이트 오프셋이다.

| 필드 / 메서드 | |
|---|---|
| `text`, `pos` | 텍스트와 커서. `pos`는 직접 바꿔도 된다 |
| `:insert(s)` | 커서에 넣고 넣은 텍스트 뒤로 이동 |
| `:delete(pos, len)` | `len` 바이트 지움. 커서는 텍스트를 따라 움직인다 |
| `:content(pos, len)` | `pos`의 바이트 |
| `:set(text [, pos])` | 텍스트 교체. `pos` 기본값은 끝 |
| `:prevchar([pos])`, `:nextchar([pos])` | 앞 / 뒤 UTF-8 글자 경계 |
| `:linestart([pos])`, `:lineend([pos])` | 줄의 처음과 끝 |
| `:wordprev([pos])`, `:wordnext([pos])` | 단어 이동. 단어는 공백으로 나눈다 |
| `:vertical(dir)` | 화면 열을 유지하며 한 줄 위(`dir < 0`) / 아래. 끝이면 false |
| `:push_history(text)`, `:history_move(dir)` | 입력 기록 |
| `history` | 지금까지 보낸 입력 |

메서드는 `sclop.redraw()`를 부른다.

## 명령

```lua
sclop:command_register(name, fn, help)   -- '/name args'가 fn(args)를 부름
sclop:command(line)                      -- '/...' 줄 실행. 모르는 이름이면 false
```

내장 명령: `help`, `quit`, `clear`, `model`, `compact`.

`sclop.submit(text)`는 Enter가 부르는 함수다. SUBMIT을 내보내고, 명령을 실행하거나 텍스트를
에이전트에 넘기고, 텍스트를 가져갔으면 true를 돌려준다.

## 출력

| | |
|---|---|
| `sclop.redraw()` | 이번 루프 끝에 화면을 그린다 |
| `sclop.commit(text)` | live 영역 위, 스크롤백에 텍스트 출력 |
| `sclop.info(text)` | 흐리게 commit |
| `sclop.error(text)` | 빨갛게 commit. 터미널이 없으면 stderr |
| `sclop.style.NAME(s)` | 색: bold, dim, italic, red, green, yellow, blue, magenta, cyan, gray |
| `sclop.term` | 터미널이 돌고 있으면 true (대화형 모드) |
| `sclop.quit([code])` | 루프를 멈추고 종료 |

보여주는 텍스트에는 SGR 색 시퀀스와 OSC 8 링크를 쓸 수 있다. 다른 이스케이프 시퀀스와 제어 문자는
지우므로 tool 출력이 커서를 옮길 수 없다.

## 타이머, 프로세스, HTTP

```lua
local t = sclop.timer(ms, fn [, repeat])   -- t:stop()
```

```lua
local p, err = sclop.spawn{
	argv = { 'git', 'status' },   -- 셸 없이 바로 실행
	cwd = 'dir',                  -- 생략 가능
	stdin = 'text',               -- 문자열이면 써 넣고 닫음. true면 열어 둠
	merge = true,                 -- stderr를 stdout으로
	on_stdout = function(data) end,
	on_stderr = function(data) end,
	on_exit = function(code, signal) end,
}
p:write(s)   p:close()   p:kill([signal])   -- 기본 시그널 15
```

자식은 자기 세션에서 돌고, `kill`은 프로세스 그룹 전체에 시그널을 보낸다. `on_exit`는 출력을 다
받은 뒤에 온다. 자식이 끝났는데 자식이 띄운 다른 프로세스가 출력을 계속 열고 있으면 200ms 뒤에
기다리기를 그만둔다. 환경 변수 옵션은 없다. `{ 'env', 'NAME=value', ... }`로 실행한다.

```lua
local h, err = sclop.http{
	url = 'https://example.com',
	method = 'POST',              -- 기본: body가 있으면 POST, 없으면 GET
	headers = { ['content-type'] = 'application/json' },
	body = '...',
	timeout = 30000,              -- 전체 전송 ms, 생략 가능
	on_data = function(chunk) end,
	on_done = function(status, err) end,
}
h:cancel()   -- 이후로 콜백 없음
```

리다이렉트를 따라가고 압축된 본문은 풀어 준다. 404 같은 HTTP 오류는 상태 코드와 함께 데이터로
온다. `err`는 전송 자체가 실패했을 때만 있다.

## JSON

```lua
sclop.json.encode(value)   -- 문자열. JSON으로 못 담는 값이면 오류
sclop.json.decode(s)       -- 값, 또는 nil과 오류
sclop.json.null            -- JSON null
sclop.json.array([t])      -- 표를 배열로 표시. 빈 배열에 필요
```

- 객체 키는 정렬해서 쓴다. 같은 값은 항상 같은 바이트가 된다.
- 키가 1..n인 표는 배열, 빈 표는 `{}`. `[]`는 `json.array()`로 쓴다. 그 밖의 표는 키가 문자열이어야 한다.
- 문자열 속 잘못된 UTF-8은 U+FFFD가 된다.
- 디코드한 배열에는 배열 표시가 붙는다. 배열 안의 `null`은 `sclop.json.null`, 객체 안의 `null`은 키를 뺀다.

## 에이전트

`sclop.agent`가 대화를 진행한다.

| 필드 | |
|---|---|
| `messages` | 대화 |
| `busy` | 턴 진행 중 |
| `tokens` | 마지막 요청의 입력 + 출력 토큰 |
| `partial` | 아직 안 끝난 답의 한 줄 |
| `thinking` | 스트리밍 중인 생각, 없으면 nil |
| `running` | 실행 중인 tool의 `{ call = ..., output = ... }`, 없으면 nil |
| `asking` | 권한을 기다리는 호출, 없으면 nil |

| 함수 | |
|---|---|
| `submit(text)` | 사용자 메시지를 넣고 턴 시작 |
| `abort()` | 요청이나 tool을 멈추고, 남은 tool 호출에는 오류로 답한다 |
| `clear()` | 대화를 잊는다 |
| `compact()` | 대화를 요약으로 바꾼다. 진행 중이거나 비었으면 false |
| `push(msg)` | 메시지를 넣고 MESSAGE를 내보낸다 |
| `system_prompt()` | 다음 요청의 system prompt |
| `tool_list()` | 모델에 내놓는 tool, 이름순 |
| `decide(call)` | 호출의 권한 |
| `ask(call, answer)` | 사용자에게 묻고 `answer('y')`, `answer('n')`, `answer('a')`를 부른다. 바꾸면 묻는 방법이 바뀐다 |
| `summary(text)` | 요약된 대화를 대신하는 메시지들 |
| `compact_prompt` | compaction에 쓰는 지시문 |

메시지 형식은 provider와 무관하다.

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

## tool

```lua
sclop.tools.register{
	name = 'hello',
	description = 'Greet someone.',             -- 또는 설명을 돌려주는 함수
	schema = {                                  -- 인자의 JSON Schema
		type = 'object',
		properties = { name = { type = 'string' } },
		required = { 'name' },
	},
	run = function(args, done, progress)
		done('hello ' .. args.name)               -- done(text [, is_error])
	end,
	summary = function(args) return args.name end,           -- 생략 가능. 이름 뒤에 보임
	render = function(text, is_error, args) return nil end,  -- 생략 가능. 결과 줄, nil이면 기본
	available = function() return true end,                  -- 생략 가능. 지금 내놓을지
}
```

`run`은 `done`을 바로 불러도 되고 나중에 불러도 된다. 작업을 멈추는 함수를 돌려줄 수 있고,
Esc가 그 함수를 부른다. `progress(text)`는 실행 중 출력을 보여준다. `run`에서 난 오류는 오류
결과가 된다. `sclop.tools.NAME = nil`로 tool을 뺀다.

## provider

provider는 `stream` 메서드가 있는 객체다.

```lua
function provider:stream(req, h)
	-- req = { model, system, messages, tools = { { name, description, schema }... }, max_tokens }
	-- 스트리밍 중: h.text(delta), h.thinking(delta)
	-- 끝에 h.done(msg, { input = n, output = n })과 h.error(message) 중 정확히 하나
	return { cancel = function() end }
end
```

`sclop.providers.NAME = provider`로 등록한다. 내장 종류는
`require('sclop.providers.anthropic').new{...}`, `require('sclop.providers.openai').new{...}`로
만든다. [설정](configuration.md#모델과-provider) 참고.

## 화면 (view)

`sclop.view`에는 화면을 표현하는 함수가 들어 있다. 어느 것이든 바꾸거나 감쌀 수 있다.

| 함수 | |
|---|---|
| `render()` | → 줄들, 커서 줄, 커서 바이트 열. live 영역 전체 |
| `live(lines)` | 진행 중인 것 추가: 생각, 미완성 답, tool 출력, 권한 질문 |
| `input(lines)` | 입력 줄 추가. 커서 줄과 열을 돌려준다 |
| `status()` | 상태줄 |
| `separator()`, `prompt(n)` | 입력 위 구분선, 입력 n번째 줄의 머리 |
| `user(text)`, `assistant(text)`, `thought(ms)` | commit하는 텍스트 형식 |
| `tool(call, tool)`, `result(call, text, is_error, tool)` | tool 호출 줄과 결과 줄 |
| `replay(messages)` | 불러온 대화 출력 |
| `tokens(n)`, `clip(s, w)`, `tail(s, w)` | `12.3k`. `w`열에 맞게 앞 / 뒤를 남기고 자름 |

상태줄에 시계, 빈 대화일 때 입력창 위에 안내 한 줄:

```lua
sclop.events.subscribe(sclop.events.STATUS, function(segs)
	segs[#segs + 1] = os.date('%H:%M')
end)
sclop.timer(30000, sclop.redraw, true)

local live = sclop.view.live
sclop.view.live = function(lines)
	live(lines)
	if #sclop.agent.messages == 0 then
		lines[#lines + 1] = sclop.style.gray('할 일을 쓰고 Enter')
	end
end
```

## 세션

`sclop.session`: `dir()`, `write(entry)`, `load(path)` → 메시지들, `latest()`,
`resume()` → 경로와 메시지 수, `reset()`(다음 메시지부터 새 파일), `enable()`,
`path`(현재 파일).

세션 파일은 한 줄에 JSON 값 하나다. 머리 `{"type":"session","model":...,"cwd":...}`, 그다음 메시지들,
대화를 요약한 자리에는 `{"type":"compact","summary":...}`.

## 도우미

`sclop.util`:

| | |
|---|---|
| `expand(path)` | 맨 앞 `~`를 홈으로 |
| `quote(s)` | 셸용 따옴표 |
| `has(cmd)` | 명령이 설치돼 있는지 |
| `lines(text)` | 줄로 나눔 |
| `truncate(text, max_lines, max_bytes [, tail])` | 앞(또는 끝)만 남기고 얼마나 잘랐는지 적음 |
| `capture(argv, done [, opts])` | 명령을 실행해 출력 모으기: `done(output, code, signal)`. `opts.cwd`, `opts.progress` |

그 밖에 `sclop.cwd`, `sclop.platform`(`'linux/x64'`), `sclop.version`, `sclop.set_model(spec)`.

## sclop.core

| 함수 | |
|---|---|
| `term_start()` → true, 또는 nil과 오류 | raw 모드, bracketed paste, 키 읽기 시작 |
| `term_stop()` | 터미널 돌려주기 |
| `size()` → cols, rows | |
| `draw(lines, row, col)` | live 영역 그리기. `row`는 `lines`의 인덱스, `col`은 그 줄의 바이트 오프셋 |
| `commit(text)` | live 영역 위에 출력. 터미널이 없으면 그냥 stdout |
| `write(s)` | 바이트를 그대로 출력 |
| `reset()` | 지난 프레임을 잊는다. 다음 draw는 지금 커서 자리부터 그린다 |
| `width(s)` | 화면 폭(열 수) |
| `feed(bytes)` | 입력 바이트를 해석해 처리 |
| `timer(ms, fn [, repeat])` → id, `timer_stop(id)` | |
| `watch(fd, 'r' \| 'w' \| 'rw', fn)`, `unwatch(fd)` | fd가 준비되면 `fn(events)`. `events`는 `r`, `w`, `e`의 조합 |
| `spawn(opts)` → id, `proc_write(id, s)`, `proc_close(id)`, `proc_kill(id [, signal])` | |
| `http(opts)` → id, `http_cancel(id)` | |
| `json_encode`, `json_decode`, `null`, `array_mt` | |
| `now()` | 단조 시계, ms |
| `quit([code])` | |
| `version` | |
| `dispatch` | 런타임이 넣는다. C가 key, paste, resize, draw, error, quit 때 `dispatch(event, ...)`를 부른다 |

`watch`로 직접 연 fd를 루프에 걸 수 있다. 예를 들면 `ffi`로 연 소켓이나 FIFO
([플러그인](plugins.md#ffi로-fifo-읽기) 참고). fd를 닫기 전에 unwatch하고, sclop이 쓰는
fd(0번 등)는 감시하지 않는다.
