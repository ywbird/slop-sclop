# sclop

C로 만든 최소 코딩 에이전트. opencode·pi가 neovim·vim이라면 sclop은 vis다.

## 1. 원칙

- **메커니즘은 C, 정책은 Lua.** C는 이벤트 루프, 터미널, 화면, 프로세스, HTTP, JSON만 한다.
  대화 루프, provider, tool, 입력기, 화면 배치는 전부 Lua(LuaJIT)이고 사용자가 교체할 수 있다.
- 설정은 Lua 파일 하나.
- 링크하는 라이브러리는 libc, LuaJIT, libcurl뿐.
- 코드는 vis처럼 평평하고 짧게.

## 2. 범위

v0에 포함:
- 대화형 inline TUI, 스트리밍 출력
- provider: Anthropic Messages, OpenAI 호환 Chat Completions
- 기본 tool: read, write, edit, bash, grep, glob, skill
- 권한: tool별 allow / ask / deny
- 함께 배포하는 플러그인(설정에서 켬): korean-ime, question, webfetch
- AGENTS.md 로드, 세션 저장/재개, compaction, `-p` 비대화형 모드

v0에서 제외 (필요하면 플러그인으로):
- fullscreen 화면, 마우스, markdown 렌더링
- MCP, subagent, patch, websearch, 이미지 입력
- 구독 OAuth
- Windows

## 3. 의존성

- 빌드: C99 컴파일러, make, pkg-config
- 링크: libc(POSIX), LuaJIT 2.1, libcurl
- 실행 시 선택: `rg`(없으면 grep/find), `bash`(없으면 sh)

## 4. 파일 구조

```
Makefile, config.mk     빌드
sclop.h                 C 모듈 공용 선언
main.c                  시작과 종료 정리
loop.c                  poll 이벤트 루프, 타이머, 시그널(self-pipe)
term.c                  raw 모드, 키 해석, bracketed paste, 창 크기
ui.c                    inline 화면: live 영역 diff, commit, 글자 폭
proc.c                  자식 프로세스: fork/exec, pipe, 프로세스 그룹 kill
http.c                  libcurl multi를 루프에 연결
json.c                  Lua 값 ↔ JSON
lua.c                   C 기능을 Lua 모듈 `sclop.core`로 노출, 런타임 경로
lua/sclop.lua           전역 `sclop`: 이벤트, 키맵, 모드, 명령, 설정 기본값, main
lua/sclop/editor.lua    입력 버퍼와 기본 키맵
lua/sclop/view.lua      화면 구성(TEA의 view)과 기록 출력 형식
lua/sclop/agent.lua     대화 루프, tool 실행, 권한
lua/sclop/sse.lua       SSE 파서
lua/sclop/providers/    anthropic.lua, openai.lua
lua/sclop/tools/        read, write, edit, bash, grep, glob, skill
lua/plugins/            korean-ime, question, webfetch
test/                   Lua 테스트 (`make test`)
docs/en, docs/ko        사용자 문서: 시작하기, 설정, Lua API, 플러그인
```

## 5. 실행 흐름

1. `main.c`: UTF-8 로캘 강제, SIGPIPE 무시, curl 초기화, Lua 상태 생성,
   `package.path` 설정, 전역 `arg`, `require('sclop').main()`, 루프 실행.
2. `sclop.main()`: 인자 해석 → 설정 로드 → 터미널 시작 → START 이벤트.
3. 루프가 끝나면: QUIT 이벤트, live 영역 지움, 터미널 복원, 자식 프로세스 종료.

런타임 경로. 아래 순서로 각 디렉토리 D의 `D/?.lua;D/?/init.lua`를 `package.path` 앞에,
`D/?.so`를 `package.cpath` 앞에 넣는다:
1. `$SCLOP_PATH` (콜론 구분)
2. 설정 디렉토리 `$XDG_CONFIG_HOME/sclop` (없으면 `~/.config/sclop`)
3. 실행 파일 옆 `lua/` (소스 트리에서 바로 실행)
4. 실행 파일 기준 `../share/sclop` (설치 위치를 옮겨도 동작)
5. `$(PREFIX)/share/sclop`

설정 디렉토리가 앞에 있으므로 같은 이름의 파일로 런타임 모듈을 덮어쓸 수 있다.
설정 파일은 `$XDG_CONFIG_HOME/sclop/init.lua`.

명령행:
```
sclop [옵션]
  -m MODEL       모델. 'provider/model'이고 provider가 등록돼 있으면 provider도 바꿈
  -c [SESSION]   세션 이어하기. SESSION(절대/상대 경로)이 없으면 이 디렉토리의 마지막 세션
  -p [PROMPT]    비대화형: 답만 stdout에 출력하고 종료. PROMPT가 없거나 '-'면 stdin
  --allow-TOOL   -p에서 해당 tool의 ask를 허용. --allow-all은 전부
  -l FILE [ARG]  설정·터미널 없이 런타임만 올리고 Lua 파일 실행 (테스트, 스크립트)
  -v, -h
```

## 6. 이벤트 루프 (TEA-lite)

- C 루프는 poll(2) 하나로 fd, 타이머, 시그널, curl 소켓을 다룬다.
- 입력(키, 붙여넣기, 창 크기, 타이머, 프로세스 출력, HTTP 데이터)은 Lua 콜백으로 들어온다.
  Lua 핸들러가 model(가변 테이블)을 고치고 `sclop.redraw()`를 부른다.
- 루프 한 바퀴의 끝에서 C가 `draw`를 보낸다. Lua는 DRAW 이벤트를 내고, 다시 그릴 게 있으면
  `sclop.view.render()`로 줄 배열을 만들어 `core.draw`에 넘긴다. 출력은 한 번에 내보낸다
  (동기화 출력 `\e[?2026h`).
- TEA의 Cmd에 해당하는 것은 `spawn` / `http` / `timer` 콜백이다.

## 7. 화면 (inline)

- 대체 화면(alt screen)을 쓰지 않는다. 끝난 내용은 `core.commit(text)`로 live 영역 위에
  출력해서 터미널 스크롤백으로 보낸다.
- live 영역(스트리밍 중인 줄, 실행 중인 tool, 권한 질문, 입력창, 상태줄)은
  `core.draw(lines, row, col)`로 매번 다시 그린다. C가 논리 줄을 터미널 폭에 맞게 접고,
  이전 프레임과 비교해 처음 달라진 줄부터 다시 쓴다.
- 폭: UTF-8 디코드 + `wcwidth`. SGR(`\e[...m`)과 OSC 8 링크는 폭 0으로 통과,
  다른 이스케이프와 제어 문자는 버린다. 탭은 8칸 정렬.
- live 영역이 화면보다 길면 커서가 보이는 아래쪽을 보여준다.
- 창 크기가 바뀌면 live 영역 전체를 다시 그린다. 터미널이 재배치한 잔상은 남을 수 있다.

## 8. 키

- raw 모드와 bracketed paste. 붙여넣기는 키가 아니라 PASTE 이벤트 하나로 온다.
- 키 이름은 vis(termkey) 표기를 따른다.
  - 일반 문자는 그대로: `a`, `한`, ` `(스페이스)
  - 특수키: `<Enter>` `<Tab>` `<S-Tab>` `<Backspace>` `<Escape>` `<Delete>` `<Insert>`
    `<Home>` `<End>` `<PageUp>` `<PageDown>` `<Up>` `<Down>` `<Left>` `<Right>` `<F1>`–`<F12>`
  - 수식키는 `C-`, `M-`, `S-` 순서: `<C-a>`, `<M-x>`, `<M-Enter>`, `<C-M-Left>`
  - Ctrl+H는 `<C-h>`, DEL(0x7f)은 `<Backspace>`, CR은 `<Enter>`, LF(Ctrl+J)는 `<C-j>`
- ESC 다음 50ms 안에 바이트가 없으면 `<Escape>`, 있으면 Meta.

## 9. Lua API

### 9.1 `sclop.core` (C)

| 함수 | 설명 |
|---|---|
| `term_start()` → ok, err / `term_stop()` | raw·paste 모드 켜기/끄기, 키 입력 시작/중지 |
| `size()` → cols, rows | 터미널 크기 |
| `draw(lines, row, col)` | live 영역 그리기. row는 lines 인덱스(1부터), col은 그 줄의 바이트 오프셋(0부터) |
| `commit(text)` | live 영역 위로 출력(스크롤백). 터미널이 아니면 stdout에 그대로 |
| `write(s)` | 바이트 그대로 출력 (호출자 책임) |
| `reset()` | 이전 프레임을 잊음. 다음 draw는 현재 커서 위치부터 전부 그림 |
| `width(s)` → n | 표시 폭 |
| `feed(bytes)` | 바이트를 키 입력처럼 해석해 처리 |
| `timer(ms, fn [, repeat])` → id / `timer_stop(id)` | 타이머 |
| `watch(fd, 'r'\|'w'\|'rw', fn)` / `unwatch(fd)` | fd 감시. `fn(revents)` |
| `now()` → ms | 단조 시계 |
| `spawn(opts)` → id / nil, err | 자식 프로세스 (아래) |
| `proc_write(id, s)` / `proc_close(id)` / `proc_kill(id [, sig])` | stdin 쓰기, stdin 닫기, 시그널(기본 SIGTERM) |
| `http(opts)` → id / `http_cancel(id)` | HTTP 요청 (아래) |
| `json_encode(v)` / `json_decode(s)` → v / nil, err | JSON |
| `null`, `array_mt`, `version` | JSON null, 배열 표시용 메타테이블, 버전 |
| `quit([code])` | 루프 종료 |
| `dispatch` | Lua가 넣는 C → Lua 진입점: `dispatch(ev, ...)`, ev는 key, paste, resize, draw, error, quit |

`spawn(opts)`:
- `argv`(배열), `cwd`
- `stdin`: 문자열이면 써 넣고 닫음, `true`면 열어 둠(`proc_write`), 없으면 /dev/null
- `merge`: stderr를 stdout으로 합침
- `on_stdout(data)`, `on_stderr(data)`, `on_exit(code, signal)`
- 자식은 새 세션(setsid)에서 돌고, kill은 프로세스 그룹 전체에 간다.
- `on_exit`는 출력이 다 끝난 뒤 불린다. 자식이 끝나고 200ms 안에 출력 pipe가 닫히지 않으면
  (백그라운드 손자 프로세스) 강제로 닫는다.

`http(opts)`:
- `url`, `method`(기본: body가 있으면 POST, 없으면 GET), `headers`(`{Name = 'value'}`),
  `body`, `timeout`(ms, 전체 시간)
- `on_data(chunk)`, `on_done(status, err)`
- 리다이렉트를 따라가고 압축을 푼다. `http_cancel` 뒤로는 콜백이 오지 않는다.

JSON:
- 객체 키는 정렬해서 출력한다 (같은 값 → 같은 바이트, prompt cache에 유리).
- 빈 테이블은 `{}`. 빈 배열은 `setmetatable({}, core.array_mt)`.
- 잘못된 UTF-8은 U+FFFD로 바꾼다.
- 디코드: 배열에는 `array_mt`가 붙는다. 배열 안의 null은 `core.null`, 객체 안의 null은 키 생략.

### 9.2 `sclop` (Lua 전역)

이벤트 (vis와 같은 계약 — emit은 처음으로 nil이 아닌 값을 돌려준 핸들러에서 멈추고 그 값을 돌려줌):
```lua
sclop.events.subscribe(ev, fn)  sclop.events.unsubscribe(ev, fn)  sclop.events.emit(ev, ...)
```

| 이벤트 | 인자 | 반환값 |
|---|---|---|
| START, QUIT | | |
| KEY | key | true면 키를 먹음 |
| PASTE | text | true면 먹음 |
| RESIZE | cols, rows | |
| DRAW | | |
| STATUS | segs | segs에 문자열을 넣으면 상태줄에 나옴 |
| SUBMIT | text | true면 기본 처리(명령/전송)를 하지 않음 |
| MESSAGE | msg | 대화에 메시지가 추가됨 |
| STREAM | kind, delta | kind는 'text' 또는 'thinking' |
| TOOL_CALL | call | 'allow' / 'ask' / 'deny'를 돌려주면 권한 결정 |
| TOOL_RESULT | call, text, is_error | |
| TURN_END | | |
| COMPACT | summary | 대화가 요약으로 바뀜 |
| ERROR | msg | |

모드와 키맵:
```lua
sclop.modes = { INPUT = 'input', ASK = 'ask' }
sclop.mode                               -- 현재 모드
sclop:map(mode, key, fn_or_key, help)    -- 문자열이면 다른 키의 별칭
sclop:unmap(mode, key)
sclop:mappings(mode)                     -- key → fn 또는 별칭 문자열
sclop:feedkeys(bytes)
```
키 처리 순서: KEY 이벤트 → 현재 모드 키맵 → 모드 기본 동작(INPUT에서는 일반 문자 삽입).

입력 버퍼 `sclop.input` (위치는 0부터 시작하는 바이트 오프셋):
```lua
input.text  input.pos
input:insert(s)  input:delete(pos, len)  input:content(pos, len)  input:set(text [, pos])
```

명령: `sclop:command_register(name, fn, help)`. 입력이 `/name args`이고 등록된 이름이면 `fn(args)`.
기본 명령: `/help`, `/quit`, `/clear`, `/model`, `/compact`.

그 밖: `sclop.redraw()`, `sclop.quit([code])`, `sclop.commit(text)`, `sclop.info(text)`,
`sclop.error(text)`, `sclop.timer(ms, fn, repeat)` → `:stop()`, `sclop.spawn(opts)` →
`:write(s)` `:close()` `:kill(sig)`, `sclop.http(opts)` → `:cancel()`, `sclop.json`,
`sclop.style`(bold, dim, italic, red, green, yellow, blue, magenta, cyan, gray).

### 9.3 설정 값과 기본값

```lua
sclop.provider = 'anthropic'
sclop.model = 'claude-sonnet-4-5'
sclop.max_tokens = 16384
sclop.context_window = 200000      -- compaction 기준
sclop.compact_at = 0.8
sclop.system = '...'               -- 기본 system prompt
sclop.skills = { '~/.agents/skills', '.agents/skills' }
sclop.permissions = { ['*'] = 'allow', read = <.env 경로면 'ask'> }
sclop.providers.anthropic          -- { api_key, base_url, extra }
sclop.providers.openai
sclop.tools                        -- 이름 → tool
```

## 10. 대화

provider 중립 메시지 형식:
```lua
{ role = 'user', content = {
    { type = 'text', text = '...' },
    { type = 'tool_result', id = '...', content = '...', is_error = false } } }
{ role = 'assistant', content = {
    { type = 'thinking', thinking = '...', signature = '...' },
    { type = 'text', text = '...' },
    { type = 'tool_call', id = '...', name = '...', args = { ... } } } }
```

턴:
1. 사용자 입력 → user 메시지 추가 → provider 요청.
2. 스트림: text는 줄이 끝날 때마다 commit. thinking은 live 영역에만 보여주고,
   끝나면 `∴ N초 생각` 한 줄만 기록에 남긴다.
3. assistant 메시지에 tool_call이 있으면 순서대로 권한 확인 → 실행 → 결과를
   user 메시지(tool_result)로 추가 → 1의 요청으로 돌아감.
4. tool_call이 없으면 턴 끝 (TURN_END).

- Esc / Ctrl+C는 진행 중인 요청이나 tool을 멈춘다. 받은 텍스트는 남기고, 답이 없는
  tool_call에는 'aborted' 결과를 채워 대화가 유효하게 남는다.
- 진행 중 Enter는 무시한다 (입력은 그대로 남음).

system prompt = `sclop.system` + 작업 디렉토리, 날짜, 플랫폼 + AGENTS.md(있으면).
스킬 목록은 skill tool 설명에 들어간다.

## 11. provider

`sclop.providers[name]`은 `stream(req, h)`를 가진 객체.
- `req = { model, system, messages, tools, max_tokens }`
- `h = { text(delta), thinking(delta), done(msg, usage), error(err) }`
- 반환값은 `:cancel()`을 가진 핸들.

anthropic:
- `POST {base_url}/v1/messages`, 헤더 `x-api-key`, `anthropic-version: 2023-06-01`, `stream: true`
- system 블록과 마지막 메시지의 마지막 블록에 `cache_control = { type = 'ephemeral' }`
- 키: `api_key` 또는 `ANTHROPIC_API_KEY`. base_url 기본 `https://api.anthropic.com`

openai (호환):
- `POST {base_url}/chat/completions`, `Authorization: Bearer`, `stream: true`,
  `stream_options = { include_usage = true }`
- tool_result는 `role = 'tool'` 메시지로. thinking은 `reasoning_content` / `reasoning` 델타.
- 키: `api_key` 또는 `OPENAI_API_KEY`. base_url 기본 `https://api.openai.com/v1`

둘 다 `extra` 테이블을 요청 본문에 합친다 (thinking 설정 등). 다른 OpenAI 호환 서버는:
```lua
sclop.providers.openrouter = require('sclop.providers.openai').new{
	base_url = 'https://openrouter.ai/api/v1', api_key = os.getenv('OPENROUTER_API_KEY') }
```

## 12. tool

```lua
sclop.tools.register{ name, description, schema, run = function(args, done, progress) ... end,
                      summary = function(args) end, render = function(text, is_error, args) end,
                      available = function() end }
```
`run`은 끝나면 `done(text, is_error)`를 부르고, 중단 함수를 돌려줄 수 있다. 실행 중 출력은
`progress(text)`로 live 영역에 보여준다. `description`은 문자열 또는 함수(요청 때마다 계산).
`available`이 false를 돌려주면 그 요청에서는 tool을 내놓지 않는다. 요청에 넣는 tool 목록은
이름순(같은 요청 앞부분 → prompt cache 적중).

| tool | 인자 | 동작 |
|---|---|---|
| read | path, offset?, limit? | 줄 번호를 붙여 최대 2000줄, 줄당 2000자. 디렉토리는 목록. 바이너리는 오류 |
| write | path, content | 부모 디렉토리를 만들고 덮어씀 |
| edit | path, old_string, new_string, replace_all? | 정확히 한 곳(또는 replace_all이면 전부) 치환 |
| bash | command, timeout? | `bash -c`, stdout과 stderr 합침, 기본 120초, 출력은 끝 50KB만 |
| grep | pattern, path?, include?, ignore_case?, literal? | rg, 없으면 `grep -rn`. 최대 200줄 |
| glob | pattern, path? | `rg --files -g`, 없으면 find. 최대 500개 |
| skill | name | SKILL.md 내용과 기준 디렉토리. 스킬 목록은 tool 설명에 |

스킬: `sclop.skills`의 각 디렉토리에서 `*/SKILL.md`를 찾고 frontmatter의 name, description을 읽는다.

## 13. 권한

- 결정 순서: TOOL_CALL 이벤트 반환값 → `sclop.permissions[name]` → `sclop.permissions['*']`.
- 값은 'allow', 'ask', 'deny' 또는 `function(args)` → 그중 하나.
- 기본: 전부 allow. read는 `.env`, `.env.*` 경로면 ask (`.env.example`은 allow).
- ask: live 영역에 tool 호출을 보여주고 ASK 모드에서 `y` 허용 / `n` 거부 /
  `a` 이번 실행 동안 이 tool 항상 허용. 거부하면 오류 결과로 모델에 알린다.
  묻는 방법은 `sclop.agent.ask(call, answer)`를 바꿔서 교체한다 (`-p`가 이렇게 함).
- `-p` 모드: ask는 거부. `--allow-TOOL`, `--allow-all`로 허용.

## 14. 세션, compaction, AGENTS.md

- 세션: `.sclop/sessions/<시각>.jsonl`. 첫 줄은 메타
  `{"type":"session","model":...,"cwd":...}`, 다음부터 메시지 한 줄에 하나.
  메시지가 추가될 때마다 append. `-c`는 가장 최근 파일을, `-c PATH`는 그 파일을 불러와
  이어 쓴다(상대 경로는 작업 디렉토리 기준, 없는 파일이나 머리가 없는 파일은 오류).
- compaction: 마지막 요청의 입력 토큰이 `context_window * compact_at`를 넘으면 자동,
  `/compact`로 수동. 지금까지의 대화를 요약하게 한 뒤 대화를 요약 메시지 하나로 바꾼다.
  세션 파일에는 `{"type":"compact","summary":...}` 줄을 남긴다.
- AGENTS.md: 작업 디렉토리의 `AGENTS.md`를 system prompt 끝에 붙인다.

## 15. 플러그인

- 플러그인은 Lua 모듈이다. `package.path` 위에 있으면 `require`로 로드. 매니저는 없다.
- 함께 배포 (설정에서 켬):
  - `plugins/korean-ime`: vis-korea-ime 포팅. 두벌식. `setup()` 뒤 원하는 키에 `change_mode`를
    매핑. 한글 모드면 상태줄에 `한`.
  - `plugins/question`: `question` tool. 질문과 번호 붙은 선택지를 live 영역에 보여주고,
    입력창에서 번호(여러 개는 쉼표) 또는 직접 쓴 답을 받는다.
  - `plugins/webfetch`: `webfetch` tool. 받은 HTML은 markdown으로 바꾼다.
- LuaJIT `ffi`로 C 함수를 바로 부를 수 있고, `package.cpath`의 C 모듈도 `require`된다.
- LuaJIT에 없는 Lua 5.3 `utf8`은 `char`, `codepoint`, `len`, `charpattern`만 런타임이 채운다.

설정 예:
```lua
-- ~/.config/sclop/init.lua
sclop.provider = 'anthropic'
sclop.model = 'claude-sonnet-4-5'
sclop.permissions.bash = function(args)
	return args.command:match('^rm ') and 'ask' or 'allow'
end

local ime = require('plugins/korean-ime')
ime.setup()
sclop:map(sclop.modes.INPUT, '<M-\\>', ime.change_mode)
require('plugins/question')
```

## 16. 입력창 기본 키

| 키 | 동작 |
|---|---|
| Enter | 전송 |
| Alt+Enter, Ctrl+J | 줄바꿈 |
| Backspace, Ctrl+H / Delete | 앞 / 뒤 글자 지움 |
| ← →, Ctrl+B / Ctrl+F | 글자 이동 |
| Alt+B / Alt+F, Ctrl+← → | 단어 이동 |
| Home / End, Ctrl+A / Ctrl+E | 줄 처음 / 끝 |
| ↑ ↓, Ctrl+P / Ctrl+N | 줄 이동, 첫 줄·끝 줄이면 입력 기록 |
| Ctrl+W, Alt+Backspace | 앞 단어 지움 |
| Ctrl+U / Ctrl+K | 줄 처음까지 / 끝까지 지움 |
| Esc | 진행 중이면 중단 |
| Ctrl+C | 진행 중이면 중단, 입력이 있으면 비움, 비었으면 종료 |
| Ctrl+D | 입력이 비었으면 종료, 아니면 뒤 글자 지움 |
| Ctrl+L | 화면 지우고 다시 그림 |

## 17. 빌드와 테스트

- `make`, `make install PREFIX=...`, `make test`(= `./sclop -l test/run.lua`)
- `config.mk`에서 컴파일러, 플래그, pkg-config 패키지 이름을 바꾼다.

## 18. 마일스톤

- M0 문서: SPEC.md, TODO.md, LICENSE
- M1 골격: Makefile, main.c, loop.c, lua.c, `sclop.main()`
- M2 터미널: term.c, ui.c, editor, view → 입력을 되돌려주는 REPL
- M3 통신: json.c, http.c, SSE, provider 2개 → 스트리밍 채팅
- M4 에이전트: proc.c, tool 7개, tool 루프, 중단, 권한과 ask
- M5 플러그인: korean-ime, question, webfetch
- M6 추가 기능: AGENTS.md → 세션 → compaction → `-p`
