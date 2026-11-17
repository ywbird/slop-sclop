# TODO

## 피드백

- [x] 이름에 c 포함 → `sclop`
- [x] question은 플러그인으로 구현
- [x] webfetch는 플러그인으로, 기본 동작은 HTML → markdown 변환
  - [ ] 확정: 기본으로 켤지 (지금은 question처럼 설정에서 켬)
- [x] skill 경로는 Lua 설정에 명시, 기본값 덮어쓰기 가능
- [x] 세션은 프로젝트 `.sclop/sessions`에 저장
- [ ] `-p` 모드: ask는 기본 거부 + 허용 플래그 (`--allow-edit`, `--allow-bash`, `--allow-all` 등)
  - [ ] 확정: `--allow-edit`가 write도 허용하는지 (opencode는 edit 권한 하나로 edit·write를 함께 다룸)

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
- [ ] `-p` 모드
