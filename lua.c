/* Lua glue: the sclop.core module, runtime paths, C -> Lua entry points */
#include <errno.h>
#include <limits.h>
#include <signal.h>
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

/* fd watches for plugins */

typedef struct LWatch {
	int fd, ref;
	struct LWatch *next;
} LWatch;

static LWatch *lwatches;

static void onwatch(int fd, int revents, void *data)
{
	LWatch *w = data;
	char ev[4];
	int n = 0;
	(void)fd;
	if (revents & LOOP_READ)
		ev[n++] = 'r';
	if (revents & LOOP_WRITE)
		ev[n++] = 'w';
	if (revents & LOOP_ERROR)
		ev[n++] = 'e';
	ev[n] = '\0';
	lua_rawgeti(L, LUA_REGISTRYINDEX, w->ref);
	lua_pushstring(L, ev);
	call(1);
}

static int l_watch(lua_State *L)
{
	int fd = luaL_checkinteger(L, 1);
	const char *how = luaL_checkstring(L, 2);
	LWatch *w;
	luaL_checktype(L, 3, LUA_TFUNCTION);
	for (w = lwatches; w && w->fd != fd; w = w->next)
		;
	if (!w) {
		if (!(w = calloc(1, sizeof *w)))
			return luaL_error(L, "out of memory");
		w->fd = fd;
		w->ref = LUA_NOREF;
		w->next = lwatches;
		lwatches = w;
	}
	luaL_unref(L, LUA_REGISTRYINDEX, w->ref);
	lua_pushvalue(L, 3);
	w->ref = luaL_ref(L, LUA_REGISTRYINDEX);
	loop_watch(fd, (strchr(how, 'r') ? LOOP_READ : 0) | (strchr(how, 'w') ? LOOP_WRITE : 0), onwatch, w);
	return 0;
}

static int l_unwatch(lua_State *L)
{
	int fd = luaL_checkinteger(L, 1);
	for (LWatch **p = &lwatches; *p; p = &(*p)->next) {
		if ((*p)->fd == fd) {
			LWatch *w = *p;
			*p = w->next;
			loop_unwatch(fd);
			luaL_unref(L, LUA_REGISTRYINDEX, w->ref);
			free(w);
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

/* processes */

typedef struct LProc {
	int id, ref;
	Proc *p;
	struct LProc *next;
} LProc;

static LProc *lprocs;
static int lastproc;

static int pushcallback(int ref, const char *field);

static LProc *findproc(int id)
{
	for (LProc *lp = lprocs; lp; lp = lp->next)
		if (lp->id == id)
			return lp;
	return NULL;
}

static void onprocout(Proc *p, int fd, const char *buf, size_t n, void *data)
{
	LProc *lp = data;
	(void)p;
	if (pushcallback(lp->ref, fd == 1 ? "on_stdout" : "on_stderr")) {
		lua_pushlstring(L, buf, n);
		call(1);
	}
}

static void onprocexit(Proc *p, int code, int sig, void *data)
{
	LProc *lp = data;
	int ref = lp->ref;
	(void)p;
	for (LProc **pp = &lprocs; *pp; pp = &(*pp)->next) {
		if (*pp == lp) {
			*pp = lp->next;
			break;
		}
	}
	free(lp);
	int have = pushcallback(ref, "on_exit");
	luaL_unref(L, LUA_REGISTRYINDEX, ref);
	if (have) {
		lua_pushinteger(L, code);
		lua_pushinteger(L, sig);
		call(2);
	}
}

static int l_spawn(lua_State *L)
{
	ProcOpts o = { 0 };
	size_t inlen = 0;
	luaL_checktype(L, 1, LUA_TTABLE);
	lua_settop(L, 1);
	lua_getfield(L, 1, "argv");  /* 2 */
	lua_getfield(L, 1, "cwd");   /* 3 */
	lua_getfield(L, 1, "stdin"); /* 4 */
	lua_getfield(L, 1, "merge"); /* 5 */
	int n = lua_istable(L, 2) ? (int)lua_objlen(L, 2) : 0;
	if (n < 1)
		return luaL_argerror(L, 1, "argv must be a non-empty array");
	char **argv = lua_newuserdata(L, (n + 1) * sizeof *argv);
	for (int i = 0; i < n; i++) {
		lua_rawgeti(L, 2, i + 1);
		if (lua_type(L, -1) != LUA_TSTRING)
			return luaL_argerror(L, 1, "argv must hold strings");
		argv[i] = (char *)lua_tostring(L, -1); /* still referenced by argv */
		lua_pop(L, 1);
	}
	argv[n] = NULL;
	const char *in = lua_type(L, 4) == LUA_TSTRING ? lua_tolstring(L, 4, &inlen) : NULL;
	o.argv = argv;
	o.cwd = lua_tostring(L, 3);
	o.keep_stdin = in || lua_toboolean(L, 4);
	o.merge = lua_toboolean(L, 5);
	o.out = onprocout;
	o.exit = onprocexit;

	LProc *lp = calloc(1, sizeof *lp);
	if (!lp)
		return luaL_error(L, "out of memory");
	o.data = lp;
	if (!(lp->p = proc_spawn(&o))) {
		free(lp);
		lua_pushnil(L);
		lua_pushstring(L, strerror(errno));
		return 2;
	}
	lp->id = ++lastproc;
	lua_pushvalue(L, 1);
	lp->ref = luaL_ref(L, LUA_REGISTRYINDEX);
	lp->next = lprocs;
	lprocs = lp;
	if (in) {
		proc_write(lp->p, in, inlen);
		proc_close(lp->p);
	}
	lua_pushinteger(L, lp->id);
	return 1;
}

static int l_proc_write(lua_State *L)
{
	size_t n;
	LProc *lp = findproc(luaL_checkinteger(L, 1));
	const char *s = luaL_checklstring(L, 2, &n);
	if (lp)
		proc_write(lp->p, s, n);
	lua_pushboolean(L, lp != NULL);
	return 1;
}

static int l_proc_close(lua_State *L)
{
	LProc *lp = findproc(luaL_checkinteger(L, 1));
	if (lp)
		proc_close(lp->p);
	return 0;
}

static int l_proc_kill(lua_State *L)
{
	LProc *lp = findproc(luaL_checkinteger(L, 1));
	if (lp)
		proc_kill(lp->p, luaL_optinteger(L, 2, SIGTERM));
	return 0;
}

/* http */

typedef struct LHttp {
	int id, ref;
	Http *h;
	struct LHttp *next;
} LHttp;

static LHttp *lhttps;
static int lastid;

static void unlinkhttp(LHttp *lh)
{
	for (LHttp **p = &lhttps; *p; p = &(*p)->next) {
		if (*p == lh) {
			*p = lh->next;
			return;
		}
	}
}

/* push opts[field] of a handle's options table; 0 if it is not a function */
static int pushcallback(int ref, const char *field)
{
	lua_rawgeti(L, LUA_REGISTRYINDEX, ref);
	lua_getfield(L, -1, field);
	lua_remove(L, -2);
	if (lua_isfunction(L, -1))
		return 1;
	lua_pop(L, 1);
	return 0;
}

static void onhttpdata(Http *h, const char *buf, size_t n, void *ud)
{
	LHttp *lh = ud;
	(void)h;
	if (pushcallback(lh->ref, "on_data")) {
		lua_pushlstring(L, buf, n);
		call(1);
	}
}

static void onhttpdone(Http *h, long status, const char *err, void *ud)
{
	LHttp *lh = ud;
	int ref = lh->ref;
	(void)h;
	unlinkhttp(lh);
	free(lh);
	int have = pushcallback(ref, "on_done");
	luaL_unref(L, LUA_REGISTRYINDEX, ref);
	if (have) {
		lua_pushinteger(L, status);
		if (err)
			lua_pushstring(L, err);
		else
			lua_pushnil(L);
		call(2);
	}
}

static int l_http(lua_State *L)
{
	HttpOpts o = { 0 };
	int nh = 0;
	luaL_checktype(L, 1, LUA_TTABLE);
	lua_settop(L, 1);
	lua_getfield(L, 1, "url");     /* 2 */
	lua_getfield(L, 1, "method");  /* 3 */
	lua_getfield(L, 1, "body");    /* 4 */
	lua_getfield(L, 1, "timeout"); /* 5 */
	lua_getfield(L, 1, "headers"); /* 6 */
	lua_newtable(L);               /* 7: "Name: value" lines */
	if (!(o.url = lua_tostring(L, 2)))
		return luaL_argerror(L, 1, "url is required");
	o.method = lua_tostring(L, 3);
	o.body = lua_tolstring(L, 4, &o.bodylen);
	o.timeout = (long)lua_tonumber(L, 5);
	if (lua_istable(L, 6)) {
		lua_pushnil(L);
		while (lua_next(L, 6)) {
			if (lua_type(L, -2) == LUA_TSTRING) {
				lua_pushvalue(L, -2);
				lua_pushliteral(L, ": ");
				lua_pushvalue(L, -3);
				lua_concat(L, 3);
				lua_rawseti(L, 7, ++nh);
			}
			lua_pop(L, 1);
		}
	}
	const char **hdrs = lua_newuserdata(L, (nh + 1) * sizeof *hdrs);
	for (int i = 0; i < nh; i++) {
		lua_rawgeti(L, 7, i + 1);
		hdrs[i] = lua_tostring(L, -1);
		lua_pop(L, 1);
	}
	hdrs[nh] = NULL;
	o.headers = hdrs;
	o.data = onhttpdata;
	o.done = onhttpdone;

	LHttp *lh = calloc(1, sizeof *lh);
	if (!lh)
		return luaL_error(L, "out of memory");
	o.ud = lh;
	if (!(lh->h = http_request(&o))) {
		free(lh);
		lua_pushnil(L);
		lua_pushliteral(L, "http: cannot start the request");
		return 2;
	}
	lh->id = ++lastid;
	lua_pushvalue(L, 1);
	lh->ref = luaL_ref(L, LUA_REGISTRYINDEX);
	lh->next = lhttps;
	lhttps = lh;
	lua_pushinteger(L, lh->id);
	return 1;
}

static int l_http_cancel(lua_State *L)
{
	int id = luaL_checkinteger(L, 1);
	for (LHttp *lh = lhttps; lh; lh = lh->next) {
		if (lh->id == id) {
			http_cancel(lh->h);
			unlinkhttp(lh);
			luaL_unref(L, LUA_REGISTRYINDEX, lh->ref);
			free(lh);
			break;
		}
	}
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
	{ "watch", l_watch },
	{ "unwatch", l_unwatch },
	{ "spawn", l_spawn },
	{ "proc_write", l_proc_write },
	{ "proc_close", l_proc_close },
	{ "proc_kill", l_proc_kill },
	{ "http", l_http },
	{ "http_cancel", l_http_cancel },
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
		snprintf(p, sizeof buf - (p - buf), "/../share/sclop");
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
	json_open(L);
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
