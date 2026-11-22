---
title: 설정
lang: ko
---

# 설정

sclop은 시작할 때 Lua 파일 하나를 읽는다. `$XDG_CONFIG_HOME/sclop/init.lua`, 없으면
`~/.config/sclop/init.lua`. 런타임을 전부 불러온 다음에 실행되므로 설정값, 키, tool, provider는
물론 런타임을 이루는 함수까지 무엇이든 바꿀 수 있다. 오류가 나면 sclop은 오류를 보여주고,
오류 전까지 실행된 내용으로 시작한다. `sclop -l`로 실행하는 스크립트는 설정을 읽지 않는다.

## 설정값

| 설정 | 기본값 | 뜻 |
|---|---|---|
| `sclop.provider` | `'anthropic'` | `sclop.providers`에 있는 provider 이름 |
| `sclop.model` | `'claude-sonnet-4-5'` | provider에 보내는 모델 이름 |
| `sclop.max_tokens` | `16384` | 답 하나의 한도. Anthropic에 보낸다 |
| `sclop.context_window` | `200000` | 모델이 받는 토큰 수. compaction 기준 |
| `sclop.compact_at` | `0.8` | 마지막 요청이 창의 이 비율을 넘으면 compaction |
| `sclop.system` | 내장 | 기본 system prompt |
| `sclop.skills` | `{ '~/.agents/skills', '.agents/skills' }` | 스킬 디렉토리 |
| `sclop.permissions` | 전부 허용, `.env` 읽기만 확인 | [권한](#권한) 참고 |

## 모델과 provider

```lua
sclop.provider = 'openai'
sclop.model = 'gpt-5'
```

명령행에서는 `sclop -m openai/gpt-5`, 실행 중에는 `/model openai/gpt-5`로 같은 일을 한다.

provider는 두 개가 내장돼 있다.

**anthropic** — Anthropic Messages API:

| 필드 | 기본값 |
|---|---|
| `api_key` | `$ANTHROPIC_API_KEY` |
| `base_url` | `https://api.anthropic.com` |
| `extra` | `{}`, 요청 본문마다 합쳐진다 |

**openai** — OpenAI 호환 Chat Completions:

| 필드 | 기본값 |
|---|---|
| `api_key` | `key_env`가 가리키는 환경 변수 |
| `key_env` | `'OPENAI_API_KEY'` |
| `base_url` | `https://api.openai.com/v1` |
| `extra` | `{}`, 요청 본문마다 합쳐진다 |

키가 없으면 `openai`는 `Authorization` 헤더를 보내지 않는다. 로컬 서버에 맞다.

```lua
sclop.providers.anthropic.api_key = 'sk-ant-...'   -- 환경 변수 대신
```

다른 OpenAI 호환 서버는 `new`로 추가한다.

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

`sclop -m openrouter/anthropic/claude-sonnet-4.5`도 된다. 그 이름의 provider가 있으므로 첫
`/` 앞부분을 provider로 본다.

API 옵션은 `extra`에 넣는다. Anthropic extended thinking 예:

```lua
sclop.providers.anthropic.extra = {
	thinking = { type = 'enabled', budget_tokens = 8000 },
}
```

`sclop.max_tokens`는 예산보다 커야 한다. `reasoning_content`나 `reasoning`을 스트리밍하는
OpenAI 호환 서버는 설정 없이도 thinking으로 보인다. sclop은 `openai`에 답 한도를 보내지 않으니,
서버가 요구하면 `extra = { max_tokens = 4096 }`처럼 정한다.

Anthropic에서는 요청마다 system prompt와 대화 끝에 prompt cache 표시를 단다. 요청의 앞부분이
매번 같게 유지되도록(tool과 JSON 키 정렬) 해서 cache가 계속 맞게 한다.

## system prompt

요청마다 `sclop.agent.system_prompt()`가 다음을 이어 붙여 만든다.

1. `sclop.system`, 기본 문구:

   ```
   You are sclop, a minimal coding agent running in the user's terminal.
   You help with software engineering: reading, writing and editing code, and running commands.

   - Look at files before you change them. Prefer small, focused edits.
   - Run commands to check your work when it helps.
   - Keep answers short and direct. The terminal shows plain text, so avoid heavy markdown.
   - Ask before doing anything destructive or irreversible.
   - Skills available to you are listed in the skill tool's description. Answer from that list; do not scan skill directories unless the user asks you to.
   ```

2. 환경 정보:

   ```
   Environment:
   - Working directory: /home/me/project
   - Platform: linux/x64
   - Date: 2026-11-17
   ```

3. 작업 디렉토리에 있으면 `AGENTS.md`.

스킬 목록은 `skill` tool의 설명에 들어가고, tool 설명은 각 tool과 함께 보내므로 system prompt에는 없다.

기본 문구 바꾸기:

```lua
sclop.system = sclop.system .. '\n- Answer in Korean.'
```

프롬프트 전체를 만드는 방법 바꾸기:

```lua
local base = sclop.agent.system_prompt
sclop.agent.system_prompt = function()
	return base() .. '\n\nMore rules...'
end
```

프롬프트는 요청마다 같게 유지한다. 시각처럼 매번 바뀌는 값을 넣으면 prompt cache가 깨진다.
기본값은 날짜 때문에 하루에 한 번 바뀐다.

compaction에 쓰는 지시문은 `sclop.agent.compact_prompt`다.

## 권한

tool을 실행하기 전에 `'allow'`, `'ask'`, `'deny'` 중 하나를 정한다. 아래에서 처음 나온 답을 쓴다.

1. 셋 중 하나를 돌려주는 TOOL_CALL 이벤트 핸들러
2. `sclop.permissions[tool 이름]`
3. `sclop.permissions['*']`

권한 값은 세 문자열 중 하나이거나, tool 인자를 받아 그중 하나를 돌려주는 함수다.

기본값은 전부 허용이다. 단 `read`가 `.env`로 끝나거나 `.env.`가 들어간 경로를 읽을 때는 묻는다
(`.env.example`은 허용).

```lua
-- 셸 명령마다 확인
sclop.permissions.bash = 'ask'

-- 일부만 확인
sclop.permissions.bash = function(args)
	return args.command:match('^%s*rm ') and 'ask' or 'allow'
end

-- 파일 수정 금지
sclop.permissions.write = 'deny'
sclop.permissions.edit = 'deny'

-- 규칙이 없는 tool은 묻기
sclop.permissions['*'] = 'ask'
```

거부된 호출은 오류로 모델에 전달되므로 모델이 다른 방법을 찾을 수 있다. 물을 때 `a`로 답하면
종료할 때까지 `sclop.permissions[이름] = 'allow'`가 된다. `-p` 모드에서는 `--allow-이름`이나
`--allow-all`이 없으면 `ask`를 거부로 처리한다.

## 스킬

스킬은 `SKILL.md`가 든 디렉토리이고, frontmatter에 `name`과 `description`이 있다.

```markdown
---
name: release
description: 이 프로젝트를 릴리스하는 방법
---
1. config.mk의 버전을 올린다.
...
```

`sclop.skills`의 각 디렉토리에서 `*/SKILL.md`를 찾는다. 상대 경로는 작업 디렉토리 기준이다.
이름과 설명은 `skill` tool 설명에 들어가고, 모델이 스킬을 불러오면 스킬 디렉토리 경로도 함께
받아서 딸린 파일을 찾을 수 있다. 목록은 실행할 때 한 번 읽는다.

```lua
sclop.skills = { '~/.agents/skills', '.agents/skills', '~/notes/skills' }
```

## tool

`sclop.tools`는 이름 → tool 표다. tool을 빼거나, 모델이 읽는 설명을 바꿀 수 있다.

```lua
sclop.tools.glob = nil
sclop.tools.bash.description = sclop.tools.bash.description .. ' Prefer make targets.'
```

새 tool은 플러그인이나 `sclop.tools.register`로 추가한다. [Lua API](lua-api.md#tool) 참고.

## 키

모드의 키를 함수나 다른 키에 연결한다.

```lua
local I = sclop.modes.INPUT
sclop:map(I, '<C-o>', function() sclop.input:insert('TODO: ') end)
sclop:map(I, '<C-s>', '<Enter>')     -- Ctrl+S로도 전송
sclop:unmap(I, '<C-l>')
```

키 이름은 vis를 따른다. 일반 문자는 그대로(`a`, `한`, `' '`), 특수키는 꺾쇠 안에(`<Enter>`,
`<Up>`, `<F5>`), 수식키는 `C-`, `M-`, `S-` 순서로 쓴다(`<C-M-Left>`). 전체 목록은
[Lua API](lua-api.md#모드와-키).

## 플러그인

```lua
local ime = require('plugins/korean-ime')
ime.setup()
sclop:map(sclop.modes.INPUT, '<M-\\>', ime.change_mode)

require('plugins/question')
require('plugins/webfetch')
```

[플러그인](plugins.md) 참고.

## 예시

```lua
-- ~/.config/sclop/init.lua
local openai = require('sclop.providers.openai')
sclop.providers.openrouter = openai.new{
	base_url = 'https://openrouter.ai/api/v1',
	key_env = 'OPENROUTER_API_KEY',
}

sclop.provider = 'anthropic'
sclop.model = 'claude-sonnet-4-5'
sclop.system = sclop.system .. '\n- 한국어로 답해.'

sclop.permissions.bash = function(args)
	return args.command:match('^%s*rm ') and 'ask' or 'allow'
end

local ime = require('plugins/korean-ime')
ime.setup()
sclop:map(sclop.modes.INPUT, '<M-\\>', ime.change_mode)
require('plugins/question')
require('plugins/webfetch')
```
