---
title: 시작하기
lang: ko
---

# 시작하기

sclop은 터미널에서 쓰는 작은 코딩 에이전트다. C 코어가 이벤트 루프, 터미널, 화면,
자식 프로세스, HTTP, JSON을 맡고, 에이전트가 하는 일은 전부 Lua 코드라서 설정에서 바꿀 수 있다.

## 빌드와 설치

C99 컴파일러, make, pkg-config, LuaJIT 2.1, libcurl이 필요하다.

```sh
make
make test
make install
```

`make test`는 테스트(`./sclop -l test/run.lua`)를 돌린다. `python3`가 있으면 작은 가짜 서버
`test/mock.py`를 띄워서 실제 HTTP도 테스트한다.

빌드 설정은 `config.mk`에 있다.

| 변수 | 기본값 | 뜻 |
|---|---|---|
| `PREFIX` | `/usr/local` | 설치 경로 |
| `SHAREDIR` | `$(PREFIX)/share/sclop` | Lua 런타임이 설치되는 곳 |
| `PKGS` | `luajit libcurl` | pkg-config 패키지 |
| `CC`, `CFLAGS`, `LDFLAGS` | | 컴파일러와 플래그 |

`make install`은 실행 파일을 `$(PREFIX)/bin`에, `lua/` 디렉토리를 `$(SHAREDIR)`에 복사한다.
`DESTDIR`도 따른다.

실행 파일은 Lua 모듈을 다음 순서로 찾는다.

1. `$SCLOP_PATH`의 디렉토리들 (콜론으로 구분)
2. 설정 디렉토리: `$XDG_CONFIG_HOME/sclop`, 없으면 `~/.config/sclop`
3. 실행 파일 옆의 `lua/` — 소스 트리에서 `./sclop`이 바로 동작
4. 실행 파일 기준 `../share/sclop` — 설치한 트리를 옮겨도 동작
5. 빌드할 때 정한 `SHAREDIR`

설정 디렉토리가 앞에 있으므로, 거기에 런타임 모듈과 같은 이름의 파일을 두면 그 모듈을 대신한다.

## API 키

| provider | 환경 변수 |
|---|---|
| `anthropic` (기본) | `ANTHROPIC_API_KEY` |
| `openai` | `OPENAI_API_KEY` |

키는 설정 파일에서도 정할 수 있다. [설정](configuration.md) 참고.

## 실행

```sh
sclop                       # 대화형
sclop -m openai/gpt-5       # 모델 고르기
sclop -c                    # 이 디렉토리의 마지막 세션 이어하기
sclop -p 'README.md 요약해줘' > summary.txt
```

| 옵션 | 뜻 |
|---|---|
| `-m MODEL` | 모델. `provider/model` 형식이고 그 이름의 provider가 있으면 provider도 바꾼다 |
| `-c` | 작업 디렉토리의 가장 최근 세션을 이어 한다 |
| `-p [PROMPT]` | 대화형 화면 없이 프롬프트 하나에 답한다. PROMPT가 없거나 `-`이면 stdin에서 읽는다 |
| `--allow-TOOL` | `-p`에서, 권한이 `ask`인 tool을 실행한다. `--allow-all`은 전부 |
| `-l FILE [ARGS]` | 설정과 터미널 없이 런타임만 올리고 Lua 파일을 실행한다 |
| `-v`, `-h` | 버전, 사용법 |

## 화면

sclop은 터미널 화면 전체를 차지하지 않는다. 끝난 출력(내 메시지, 답, tool 호출과 결과)은
일반 스크롤백에 찍히므로 터미널로 평소처럼 스크롤하고 검색하고 복사하면 된다.
화면 아래쪽만 다시 그린다.

```
∴ 모델이 지금 하는 생각…                 생각하는 동안
아직 도착 중인 답의 한 줄
  │ 실행 중인 tool의 출력
Allow bash? [y]es [n]o [a]lways         tool이 권한을 물을 때
─────────────────────────────────────
> 입력
anthropic/claude-sonnet-4-5  12.3k tokens  ⠋
```

상태줄에는 provider와 모델, 마지막 요청의 토큰 수, 작업 중이면 스피너, 플러그인이 넣은 것이 나온다.

모델이 생각하는 동안에는 그 생각이 아래에 흐리게 보이고, 끝나면 `∴ thought for 12s` 같은
한 줄만 스크롤백에 남는다.

## 키

| 키 | 동작 |
|---|---|
| Enter | 전송 |
| Alt+Enter, Ctrl+J | 줄바꿈 |
| Backspace, Ctrl+H / Delete | 커서 앞 / 뒤 글자 지움 |
| ← →, Ctrl+B / Ctrl+F | 글자 단위 이동 |
| Alt+B / Alt+F, Ctrl+← / Ctrl+→ | 단어 단위 이동 |
| Home / End, Ctrl+A / Ctrl+E | 줄 처음 / 끝 |
| ↑ ↓, Ctrl+P / Ctrl+N | 줄 이동. 첫 줄이나 끝 줄이면 이전 입력 기록 |
| Ctrl+W, Alt+Backspace | 커서 앞 단어 지움 |
| Ctrl+U / Ctrl+K | 줄 처음까지 / 끝까지 지움 |
| Esc | 진행 중인 답이나 tool 멈춤 |
| Ctrl+C | 멈춤. 쉬는 중이면 입력 비움. 입력이 비었으면 종료 |
| Ctrl+D | 입력이 비었으면 종료, 아니면 커서 뒤 글자 지움 |
| Ctrl+L | 화면 지움 |

붙여넣은 텍스트는 줄바꿈까지 그대로 들어간다. 에이전트가 일하는 동안 Enter는 아무것도
하지 않고, 쓴 텍스트는 입력창에 그대로 남는다.

tool이 권한을 물으면 `y`는 이번만 허용, `n`은 거부, `a`는 끝낼 때까지 이 tool 허용,
Esc는 거부, Ctrl+C는 이번 턴을 멈춘다.

## 명령

| 명령 | 동작 |
|---|---|
| `/help` | 명령 목록 |
| `/model [provider/]model` | 모델 보기 또는 바꾸기 |
| `/clear` | 새 대화, 새 세션 파일 |
| `/compact` | 대화를 요약해서 컨텍스트 비우기 |
| `/quit` | 종료 |

`/`로 시작하지만 등록된 명령 이름이 아니면 그대로 모델에 보낸다.

## tool

| tool | 하는 일 |
|---|---|
| `read` | 텍스트 파일을 줄 번호와 함께 읽는다. 한 번에 최대 2000줄, 64KB. `offset`과 `limit`로 나눠 읽는다. 디렉토리면 목록 |
| `write` | 파일을 만들거나 덮어쓴다. 없는 디렉토리는 만든다 |
| `edit` | 정확히 한 번 나오는 문자열을 바꾼다. `replace_all`이면 전부 |
| `bash` | 셸 명령 실행. 출력은 합쳐서 끝 50KB만 남긴다. 호출에서 `timeout`을 안 주면 2분 뒤 종료 |
| `grep` | ripgrep으로 내용 검색. 없으면 grep. 최대 200줄 |
| `glob` | ripgrep이나 find로 패턴에 맞는 파일 찾기. 최대 500개 |
| `skill` | 스킬 지시문 불러오기. 스킬이 있을 때만 모델에 보인다 |

기본값으로는 모든 tool을 묻지 않고 실행한다. `.env` 파일을 `read`할 때만 묻는다.
바꾸는 방법은 [설정](configuration.md#권한).

## 세션

메시지는 전부 작업 디렉토리의 `.sclop/sessions/<시각>.jsonl`에 덧붙여 저장된다.
그 디렉토리를 만들 때 `.sclop/.gitignore`도 같이 만들어서, tool 출력 속 비밀이 들어갈 수
있는 세션 파일이 git에 올라가지 않게 한다. `sclop -c`는 가장 최근 세션을 불러와 보여주고
그 파일에 이어 쓴다.

## compaction

마지막 요청이 `context_window × compact_at` 토큰(기본 200000 × 0.8)을 넘으면, 모델에게
대화 요약을 받아 요약에서부터 이어 간다. `/compact`로 언제든 할 수 있다. 세션 파일에도 기록된다.

## AGENTS.md

작업 디렉토리에 `AGENTS.md`가 있으면 그 내용을 요청마다 system prompt에 붙인다.

## print 모드

`sclop -p`는 프롬프트 하나를 보내고, 물어볼 사람 없이 tool 루프를 돌린 다음, 마지막 답을
stdout에 찍고 끝난다.

```sh
sclop -p 'make test가 왜 실패해?' --allow-bash
echo 'TODO 주석 목록 뽑아줘' | sclop -p
sclop -c -p '이제 첫 번째 거 고쳐줘'
```

- 권한이 `ask`인 tool은 `--allow-TOOL`이나 `--allow-all`로 허용하지 않으면 거부한다.
  거부는 stderr에 알린다. 기본 권한에서는 `.env` 읽기만 `ask`라서 나머지 tool은 다 실행된다.
  막고 싶은 tool은 설정에서 `ask`로 정해 둔다.
- 오류는 stderr로 간다.
- 종료 코드는 성공 0, 실패 1, 시그널로 끊기면 128 + 시그널 번호.
- 설정은 평소처럼 불러오고 세션도 저장한다.
