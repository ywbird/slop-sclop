# TODO

## 피드백

- [x] 이름에 c 포함 → `sclop`
- [x] question은 플러그인으로 구현
- [x] webfetch는 플러그인으로, 기본 동작은 HTML → markdown 변환
  - [x] 확정: 기본으로 켤지 → 설정에서 켬 (question과 같음)
- [x] skill 경로는 Lua 설정에 명시, 기본값 덮어쓰기 가능
- [x] 세션은 프로젝트 `.sclop/sessions`에 저장
- [x] `-p` 모드: ask는 기본 거부 + 허용 플래그 (`--allow-edit`, `--allow-bash`, `--allow-all` 등)
  - [x] 확정: `--allow-edit`가 write도 허용하는지 → 아니오, 플래그는 `--allow-<tool 이름>` 그대로
- [x] docs 폴더에 영어/한글 문서
  - [x] 확정: `docs/en`, `docs/ko` 폴더
  - [x] 확정: 시작하기, 설정, Lua API, 플러그인 (아키텍처 문서는 빼기)
  - [x] 확정: README는 영어로 바꾸고 문서 링크
- [x] SPEC에만 있던 `core.watch` / `core.unwatch` 구현 (문서 쓰다 발견)

## 작업

### M0 문서
- [x] SPEC.md, TODO.md, LICENSE

### M1 골격
- [x] Makefile, config.mk
- [x] main.c, loop.c, lua.c: LuaJIT 시작, 런타임 경로, `sclop.main()`

### M2 터미널
- [x] term.c: raw 모드, 키 해석, paste, 창 크기
- [x] ui.c: live 영역 diff, commit, 글자 폭
- [x] editor.lua, view.lua: 입력을 되돌려주는 REPL

### M3 통신
- [x] json.c
- [x] http.c
- [x] sse.lua, providers (anthropic, openai)
- [x] 스트리밍 채팅, thinking은 live 영역에만

### M4 에이전트
- [x] proc.c
- [x] tool: read, write, edit, bash, grep, glob, skill
- [x] tool 루프, 중단
- [x] 권한 + ask

### M5 플러그인
- [x] korean-ime 포팅
- [x] question
- [x] webfetch (HTML → markdown)

### M6 추가 기능
- [x] AGENTS.md
- [x] 세션 저장/재개
- [x] compaction (자동 80% + `/compact`)
- [x] `-p` 모드
