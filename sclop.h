#ifndef SCLOP_H
#define SCLOP_H

#include <stddef.h>

#define LENGTH(a) (sizeof(a) / sizeof((a)[0]))

/* loop.c */
enum { LOOP_READ = 1, LOOP_WRITE = 2, LOOP_ERROR = 4 };
typedef void (*WatchFn)(int fd, int revents, void *data);
typedef void (*TimerFn)(void *data);
int loop_init(void);
void loop_watch(int fd, int events, WatchFn fn, void *data);
void loop_unwatch(int fd);
int loop_timer(double ms, double repeat, TimerFn fn, void *data);
void *loop_timer_stop(int id);
void loop_signal(int sig, void (*fn)(int sig));
double loop_now(void);
int loop_run(void (*idle)(void));
void loop_quit(int code);

/* term.c */
typedef struct {
	void (*key)(const char *name);
	void (*paste)(const char *text, size_t len);
	void (*resize)(int cols, int rows);
} TermEvents;
void term_init(const TermEvents *ev);
int term_start(void);
void term_stop(void);
int term_active(void);
void term_size(int *cols, int *rows);
void term_feed(const char *s, size_t n);

/* ui.c */
size_t utf8_decode(const char *s, size_t n, unsigned *cp);
int ui_width(const char *s, size_t n);
void ui_draw(const char **lines, const size_t *lens, int n, int row, size_t col);
void ui_commit(const char *s, size_t n);
void ui_write(const char *s, size_t n);
void ui_reset(void);
void ui_clear(void);
void ui_flush(void);
void ui_resize(int cols, int rows);

/* proc.c */
typedef struct Proc Proc;
typedef struct {
	char *const *argv;
	const char *cwd;
	int keep_stdin; /* a pipe for proc_write, else /dev/null */
	int merge;      /* stderr goes to stdout */
	void (*out)(Proc *p, int fd, const char *buf, size_t len, void *data);
	void (*exit)(Proc *p, int code, int sig, void *data);
	void *data;
} ProcOpts;
Proc *proc_spawn(const ProcOpts *o);
void proc_write(Proc *p, const char *buf, size_t len);
void proc_close(Proc *p);
void proc_kill(Proc *p, int sig);
void proc_killall(void);

/* http.c */
typedef struct Http Http;
typedef struct {
	const char *url, *method;
	const char *body;
	size_t bodylen;
	const char *const *headers; /* "Name: value", NULL terminated */
	long timeout;               /* ms, 0 for none */
	void (*data)(Http *h, const char *buf, size_t len, void *ud);
	void (*done)(Http *h, long status, const char *err, void *ud);
	void *ud;
} HttpOpts;
int http_init(void);
void http_cleanup(void);
Http *http_request(const HttpOpts *o);
void http_cancel(Http *h);

/* json.c */
struct lua_State;
int json_encode(struct lua_State *L);
int json_decode(struct lua_State *L);
void json_open(struct lua_State *L);

/* lua.c */
int script_start(int argc, char *argv[]);
void script_idle(void);
void script_stop(void);

#endif
