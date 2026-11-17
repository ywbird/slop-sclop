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

/* lua.c */
int script_start(int argc, char *argv[]);
void script_idle(void);
void script_stop(void);

#endif
