# sclop

C와 LuaJIT으로 만든 최소 코딩 에이전트. C는 이벤트 루프, 터미널, 화면, 프로세스, HTTP, JSON만
하고, 대화 루프와 provider, tool, 입력기, 화면 배치는 전부 Lua라서 설정 파일에서 바꿀 수 있다.

자세한 설계와 Lua API는 [SPEC.md](SPEC.md).

## 빌드

필요한 것: C99 컴파일러, make, pkg-config, LuaJIT 2.1, libcurl.

```sh
make
make test             # python3가 있으면 실제 HTTP 테스트도 돈다
make install          # PREFIX는 config.mk
```

## 사용

```sh
export ANTHROPIC_API_KEY=...
sclop                 # 대화형
sclop -c              # 이 디렉토리의 마지막 세션 이어하기
sclop -m openai/gpt-5 # 모델 바꾸기 (provider/model)
sclop -p '테스트 고쳐줘' --allow-edit --allow-bash
```

Enter 전송, Alt+Enter·Ctrl+J 줄바꿈, Esc 중단, Ctrl+C 중단/입력 비움/종료.
명령: `/help`, `/model`, `/clear`, `/compact`, `/quit`.

## 설정

`~/.config/sclop/init.lua`:

```lua
sclop.provider = 'anthropic'
sclop.model = 'claude-sonnet-4-5'

-- 다른 OpenAI 호환 서버
sclop.providers.openrouter = require('sclop.providers.openai').new{
	base_url = 'https://openrouter.ai/api/v1', api_key = os.getenv('OPENROUTER_API_KEY') }

-- 권한: 'allow' / 'ask' / 'deny' 또는 함수
sclop.permissions.bash = function(args)
	return args.command:match('^rm ') and 'ask' or 'allow'
end

-- 한글 입력
local ime = require('plugins/korean-ime')
ime.setup()
sclop:map(sclop.modes.INPUT, '<M-\\>', ime.change_mode)

require('plugins/question')
require('plugins/webfetch')
```

## 라이선스

MIT. `lua/plugins/korean-ime.lua`는 vis-korea-ime와 Korean-IME.nvim(Kiyoon Kim)에서 왔다.
