/* Lua glue: the sclop.core module, runtime paths, C -> Lua entry points */
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <lauxlib.h>
#include <lua.h>
#include <lualib.h>

#include "sclop.h"

#define CORE "sclop.core"

static lua_State *L;
static char *dirs[16];
static int ndirs;

/* errors and calls */

static int traceback(lua_State *L)
{
	const char *msg = lua_tostring(L, 1);
	if (!msg) {
		if (luaL_callmeta(L, 1, "__tostring") && lua_isstring(L, -1))
			return 1;
		msg = lua_pushfstring(L, "(error object is a %s value)", luaL_typename(L, 1));
	}
	luaL_traceback(L, L, msg, 1);
	return 1;
}

/* push core.dispatch and the event name; 0 if Lua has no dispatcher */
static int pushdispatch(const char *ev)
{
	lua_getfield(L, LUA_REGISTRYINDEX, CORE);
	lua_getfield(L, -1, "dispatch");
	lua_remove(L, -2);
	if (!lua_isfunction(L, -1)) {
		lua_pop(L, 1);
		return 0;
	}
	lua_pushstring(L, ev);
	return 1;
}

static void report(const char *msg)
{
	static int busy;
	if (!msg)
		msg = "unknown error";
	if (!busy && pushdispatch("error")) {
		busy = 1;
		lua_pushstring(L, msg);
		int r = lua_pcall(L, 2, 0, 0);
		busy = 0;
		if (!r)
			return;
		fprintf(stderr, "sclop: %s\n", lua_tostring(L, -1));
		lua_pop(L, 1);
	}
	if (term_active()) {
		ui_commit(msg, strlen(msg));
		ui_flush();
	} else {
		fprintf(stderr, "sclop: %s\n", msg);
	}
}

/* call the function below nargs arguments; errors are reported, not raised */
static int call(int nargs)
{
	int base = lua_gettop(L) - nargs;
	lua_pushcfunction(L, traceback);
	lua_insert(L, base);
	int r = lua_pcall(L, nargs, 0, base);
	if (r) {
		report(lua_tostring(L, -1));
		lua_pop(L, 1);
	}
	lua_remove(L, base);
	return r;
}

/* timers */

typedef struct LTimer {
	int id, ref, repeat;
	struct LTimer *next;
} LTimer;

static LTimer *ltimers;

static void unlinktimer(LTimer *t)
{
	for (LTimer **p = &ltimers; *p; p = &(*p)->next) {
		if (*p == t) {
			*p = t->next;
			return;
		}
	}
}

static void ontimer(void *data)
{
	LTimer *t = data;
	lua_rawgeti(L, LUA_REGISTRYINDEX, t->ref);
	if (!t->repeat) {
		unlinktimer(t);
		luaL_unref(L, LUA_REGISTRYINDEX, t->ref);
		free(t);
	}
	call(0);
}

static int l_timer(lua_State *L)
{
	double ms = luaL_checknumber(L, 1);
	luaL_checktype(L, 2, LUA_TFUNCTION);
	LTimer *t = malloc(sizeof *t);
	if (!t)
		return luaL_error(L, "out of memory");
	t->repeat = lua_toboolean(L, 3);
	if (t->repeat && ms < 1)
		ms = 1;
	lua_pushvalue(L, 2);
	t->ref = luaL_ref(L, LUA_REGISTRYINDEX);
	t->id = loop_timer(ms, t->repeat ? ms : 0, ontimer, t);
	t->next = ltimers;
	ltimers = t;
	lua_pushinteger(L, t->id);
	return 1;
}

static int l_timer_stop(lua_State *L)
{
	int id = luaL_checkinteger(L, 1);
	for (LTimer *t = ltimers; t; t = t->next) {
		if (t->id == id) {
			loop_timer_stop(id);
			unlinktimer(t);
			luaL_unref(L, LUA_REGISTRYINDEX, t->ref);
			free(t);
			break;
		}
	}
	return 0;
}

/* terminal and screen */

static void onkey(const char *name)
{
	if (pushdispatch("key")) {
		lua_pushstring(L, name);
		call(2);
	}
}

static void onpaste(const char *s, size_t n)
{
	if (pushdispatch("paste")) {
		lua_pushlstring(L, s, n);
		call(2);
	}
}

static void onresize(int c, int r)
{
	if (pushdispatch("resize")) {
		lua_pushinteger(L, c);
		lua_pushinteger(L, r);
		call(3);
	}
}

static const TermEvents termevents = { onkey, onpaste, onresize };

static int l_term_start(lua_State *L)
{
	if (term_start() < 0) {
		lua_pushnil(L);
		lua_pushliteral(L, "not a terminal");
		return 2;
	}
	lua_pushboolean(L, 1);
	return 1;
}

static int l_term_stop(lua_State *L)
{
	(void)L;
	term_stop();
	return 0;
}

static int l_size(lua_State *L)
{
	int c, r;
	term_size(&c, &r);
	lua_pushinteger(L, c);
	lua_pushinteger(L, r);
	return 2;
}

static int l_draw(lua_State *L)
{
	luaL_checktype(L, 1, LUA_TTABLE);
	int n = lua_objlen(L, 1);
	int row = luaL_optinteger(L, 2, n);
	lua_Integer col = luaL_optinteger(L, 3, 0);
	const char **lines = lua_newuserdata(L, (n + 1) * sizeof *lines);
	size_t *lens = lua_newuserdata(L, (n + 1) * sizeof *lens);
	for (int i = 0; i < n; i++) {
		lua_rawgeti(L, 1, i + 1);
		if (lua_type(L, -1) != LUA_TSTRING)
			return luaL_error(L, "draw: line %d is not a string", i + 1);
		lines[i] = lua_tolstring(L, -1, &lens[i]);
		lua_pop(L, 1); /* still referenced by the table */
	}
	ui_draw(lines, lens, n, row, col < 0 ? 0 : (size_t)col);
	return 0;
}

static int l_commit(lua_State *L)
{
	size_t n;
	const char *s = luaL_checklstring(L, 1, &n);
	ui_commit(s, n);
	return 0;
}

static int l_write(lua_State *L)
{
	size_t n;
	const char *s = luaL_checklstring(L, 1, &n);
	ui_write(s, n);
	return 0;
}

static int l_reset(lua_State *L)
{
	(void)L;
	ui_reset();
	return 0;
}

static int l_width(lua_State *L)
{
	size_t n;
	const char *s = luaL_checklstring(L, 1, &n);
	lua_pushinteger(L, ui_width(s, n));
	return 1;
}

static int l_feed(lua_State *L)
{
	size_t n;
	const char *s = luaL_checklstring(L, 1, &n);
	term_feed(s, n);
	return 0;
}

/* misc */

static int l_now(lua_State *L)
{
	lua_pushnumber(L, loop_now());
	return 1;
}

static int l_quit(lua_State *L)
{
	loop_quit(luaL_optinteger(L, 1, 0));
	return 0;
}

static const luaL_Reg corefns[] = {
	{ "term_start", l_term_start },
	{ "term_stop", l_term_stop },
	{ "size", l_size },
	{ "draw", l_draw },
	{ "commit", l_commit },
	{ "write", l_write },
	{ "reset", l_reset },
	{ "width", l_width },
	{ "feed", l_feed },
	{ "timer", l_timer },
	{ "timer_stop", l_timer_stop },
	{ "now", l_now },
	{ "quit", l_quit },
	{ NULL, NULL },
};

/* runtime paths */

static void adddir(const char *dir, size_t len)
{
	char *d;
	if (!len || ndirs == (int)LENGTH(dirs) || !(d = malloc(len + 1)))
		return;
	memcpy(d, dir, len);
	d[len] = '\0';
	dirs[ndirs++] = d;
}

static void finddirs(const char *argv0)
{
	const char *env = getenv("SCLOP_PATH"), *xdg = getenv("XDG_CONFIG_HOME");
	const char *home = getenv("HOME");
	char buf[PATH_MAX], *p;
	ssize_t n;

	for (const char *s = env; s && *s;) {
		const char *e = strchr(s, ':');
		if (!e)
			e = s + strlen(s);
		adddir(s, e - s);
		s = *e ? e + 1 : e;
	}
	if (xdg && *xdg)
		snprintf(buf, sizeof buf, "%s/sclop", xdg);
	else
		snprintf(buf, sizeof buf, "%s/.config/sclop", home ? home : "");
	adddir(buf, strlen(buf));
	if ((n = readlink("/proc/self/exe", buf, sizeof buf - 1)) > 0)
		buf[n] = '\0';
	else if (!strchr(argv0, '/') || !realpath(argv0, buf))
		buf[0] = '\0';
	if ((p = strrchr(buf, '/'))) {
		snprintf(p, sizeof buf - (p - buf), "/lua");
		adddir(buf, strlen(buf));
	}
	adddir(SHAREDIR, strlen(SHAREDIR));
}

static void setpath(const char *field, const char *const *suffixes)
{
	luaL_Buffer b;
	lua_getglobal(L, "package");
	lua_getfield(L, -1, field);
	const char *old = lua_tostring(L, -1);
	luaL_buffinit(L, &b);
	for (int i = 0; i < ndirs; i++) {
		for (const char *const *s = suffixes; *s; s++) {
			luaL_addstring(&b, dirs[i]);
			luaL_addstring(&b, *s);
			luaL_addchar(&b, ';');
		}
	}
	luaL_addstring(&b, old ? old : "");
	luaL_pushresult(&b);
	lua_setfield(L, -3, field);
	lua_pop(L, 2);
}

/* entry points */

int script_start(int argc, char *argv[])
{
	if (!(L = luaL_newstate()))
		return -1;
	luaL_openlibs(L);
	term_init(&termevents);
	finddirs(argv[0]);
	setpath("path", (const char *const[]){ "/?.lua", "/?/init.lua", NULL });
	setpath("cpath", (const char *const[]){ "/?.so", NULL });

	lua_newtable(L);
	luaL_setfuncs(L, corefns, 0);
	lua_pushliteral(L, VERSION);
	lua_setfield(L, -2, "version");
	lua_pushvalue(L, -1);
	lua_setfield(L, LUA_REGISTRYINDEX, CORE);
	lua_getglobal(L, "package");
	lua_getfield(L, -1, "loaded");
	lua_pushvalue(L, -3);
	lua_setfield(L, -2, CORE);
	lua_pop(L, 3);

	lua_createtable(L, argc, 1);
	for (int i = 0; i < argc; i++) {
		lua_pushstring(L, argv[i]);
		lua_rawseti(L, -2, i);
	}
	lua_setglobal(L, "arg");

	if (luaL_loadstring(L, "require('sclop').main()")) {
		report(lua_tostring(L, -1));
		return -1;
	}
	return call(0) ? -1 : 0;
}

void script_idle(void)
{
	if (pushdispatch("draw"))
		call(1);
	ui_flush();
}

void script_stop(void)
{
	if (!L)
		return;
	if (pushdispatch("quit"))
		call(1);
	lua_close(L);
	L = NULL;
}
