---
title: 플러그인
lang: ko
---

# 플러그인

플러그인은 Lua 모듈이다. 플러그인 매니저는 없다. Lua가 모듈을 찾는 곳에 파일을 두고 설정에서
`require`하면 된다.

설정 디렉토리가 모듈 경로에 있으므로:

```
~/.config/sclop/plugins/hello.lua        -> require('plugins/hello')
~/.config/sclop/plugins/hello/init.lua   -> require('plugins/hello')
```

두 번째 형태는 `~/.config/sclop/plugins/`에 `git clone`할 때 맞다. 설정 디렉토리의 파일이 같은
이름의 번들 파일보다 먼저 쓰인다.

C도 된다. `~/.config/sclop/foo.so`는 `require('foo')`로 불러온다(`luaopen_foo`를 내보내야 함).
LuaJIT의 `ffi`를 쓰면 모듈 없이도 C 함수를 부를 수 있다.

## 플러그인 만들기

플러그인은 런타임과 같은 [Lua API](lua-api.md)를 쓴다. 지키면 좋은 것:

- 표를 돌려준다. 옵션이 필요하거나 불러오기만 해서 동작하면 안 되는 경우 `setup(opts)`에서 일한다.
- 사용자가 원하지 않은 키는 건드리지 않는다. 대신 매핑하는 방법을 알려준다.
- 핸들러에서는 상태를 바꾸고 `sclop.redraw()`를 부른다. 화면은 view 함수로 표현한다.

### 상태줄 항목과 명령

턴이 끝날 때마다 git 브랜치를 상태줄에 보여준다.

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

### 자기 화면이 있는 tool

모델이 관리하는 할 일 목록을 입력창 위에 보여준다.

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

tool 설명은 모델이 읽는 글이라 영어로 두었다. 한국어로 써도 된다.

### ffi로 FIFO 읽기

named pipe에 쓴 프롬프트를 에이전트에 보낸다. 다른 프로그램이 sclop을 움직일 수 있다.
`ffi`로 파이프를 열고 `sclop.core.watch`로 이벤트 루프에 건다. 플래그 값은 Linux 기준이다.

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
echo '테스트 돌리고 실패한 거 고쳐줘' > /tmp/sclop.fifo
```

### 화면 없이 플러그인 확인하기

`sclop -l`은 런타임을 올린 채 Lua 파일을 실행하므로 플러그인을 확인할 때 편하다.

```lua
-- check.lua
require('plugins/todo')
sclop.tools.todo.run({ items = { { text = 'a', done = true } } }, function(text) print(text) end)
sclop.quit()
```

```sh
SCLOP_PATH=~/.config/sclop sclop -l check.lua
```

## 함께 배포하는 플러그인

### korean-ime

운영체제 입력기와 상관없이 sclop 입력창 안에서 한글(두벌식 표준 자판)을 조합한다. SSH, 콘솔,
터미널 입력기가 말썽일 때 쓸모 있다.
[vis-korea-ime](https://codeberg.org/ywbird/vis-korea-ime)를 옮긴 것이고, 그것은
[Korean-IME.nvim](https://github.com/kiyoon/Korean-IME.nvim)을 옮긴 것이다.

```lua
local ime = require('plugins/korean-ime')
ime.setup()
sclop:map(sclop.modes.INPUT, '<M-\\>', ime.change_mode)   -- Alt+\로 한/영 전환
```

| | |
|---|---|
| `setup()` | INPUT 모드의 출력 가능한 키(`!`부터 `~`), 스페이스, Backspace를 맡는다. Ctrl+H가 기본 별칭이면 그것도 |
| `change_mode()` | `'en'`과 `'ko'` 전환 |
| `get_mode()`, `set_mode(mode)` | 모드 읽기, 정하기 |

한글 모드면 상태줄에 `한`이 나온다. `dkssudgktpdy`를 치면 안녕하세요가 되고, Backspace는 자모를
하나씩 되돌린다. 커서가 움직이거나 붙여넣기처럼 다른 방법으로 텍스트가 바뀌면 조합 중인 글자를
끝낸다. INPUT 모드에만 적용되므로 권한 질문의 답(`y`, `n`, `a`)은 그대로 영문 키다.

### question

모델에게 `question` tool을 주어 사용자에게 묻고 답을 기다리게 한다.

```lua
require('plugins/question')
```

모델은 질문을 하나 이상 보내고, 질문마다 선택지를 붙일 수 있다.

```json
{ "questions": [
  { "question": "Which database?", "options": [
      { "label": "sqlite" }, { "label": "postgres", "description": "needs a server" } ],
    "multiple": false } ] }
```

질문과 번호 붙은 선택지가 입력창 위에 나온다. 입력창에 선택지 번호, 쉼표로 나눈 여러 번호, 또는
직접 쓴 답을 넣고 Enter. 질문이 여러 개면 차례로 묻는다. 모델은 `Q: …` / `A: …` 쌍을 받는다.
Esc는 턴을 멈춘다. korean-ime를 켜 두면 한글로 답할 수 있다.

### webfetch

모델에게 URL을 가져오는 `webfetch` tool을 준다.

```lua
require('plugins/webfetch')
```

- 인자: `url`(http, https), `format`: `'markdown'`(기본) 또는 `'html'`
- 30초 제한, 최대 5MB. 결과는 5000줄, 100KB까지 자른다.
- HTML로 보이는 페이지는 markdown으로 바꾼다. 제목, 문단, 링크(`/`로 시작하는 경로는 절대 주소로),
  이미지, 굵게와 기울임, 코드와 `pre` 블록, 중첩 목록, 표의 행, 인용. `script`, `style`, `head`,
  `svg`, `noscript`, `template`, `iframe`은 버리고 엔티티는 풀어 준다. 그 밖의 내용은 그대로 돌려준다.
- `require('plugins/webfetch').markdown(html, base_url)`으로 변환만 따로 쓸 수 있다.
- 가져올 때마다 확인하려면 `sclop.permissions.webfetch = 'ask'`.
