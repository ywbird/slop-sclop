/* poll(2) event loop: fd watches, timers, signals through a self-pipe */
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include "sclop.h"

typedef struct {
	int fd, events;
	WatchFn fn;
	void *data;
} Watch;

typedef struct {
	int id;
	double when, repeat;
	TimerFn fn;
	void *data;
} Timer;

static Watch *watches;
static int nwatches;
static Timer *timers;
static int ntimers, lastid;
static struct { int sig; void (*fn)(int); } sigs[8];
static int nsigs;
static int sigfd[2] = { -1, -1 };
static int quitting, exitcode;

static void *xrealloc(void *p, size_t n)
{
	if (!(p = realloc(p, n)) && n)
		abort();
	return p;
}

double loop_now(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec * 1e3 + ts.tv_nsec / 1e6;
}

void loop_watch(int fd, int events, WatchFn fn, void *data)
{
	for (int i = 0; i < nwatches; i++) {
		if (watches[i].fd == fd) {
			watches[i] = (Watch){ fd, events, fn, data };
			return;
		}
	}
	watches = xrealloc(watches, (nwatches + 1) * sizeof *watches);
	watches[nwatches++] = (Watch){ fd, events, fn, data };
}

void loop_unwatch(int fd)
{
	for (int i = 0; i < nwatches; i++) {
		if (watches[i].fd == fd) {
			watches[i] = watches[--nwatches];
			return;
		}
	}
}

int loop_timer(double ms, double repeat, TimerFn fn, void *data)
{
	timers = xrealloc(timers, (ntimers + 1) * sizeof *timers);
	timers[ntimers++] = (Timer){ ++lastid, loop_now() + ms, repeat, fn, data };
	return lastid;
}

void *loop_timer_stop(int id)
{
	for (int i = 0; i < ntimers; i++) {
		if (timers[i].id == id) {
			void *data = timers[i].data;
			timers[i] = timers[--ntimers];
			return data;
		}
	}
	return NULL;
}

static void onsignal(int sig)
{
	int saved = errno;
	unsigned char c = sig;
	if (write(sigfd[1], &c, 1) < 0) {
		/* pipe full: the signal is already pending */
	}
	errno = saved;
}

static void readsignals(int fd, int revents, void *data)
{
	unsigned char buf[64];
	ssize_t n;
	(void)revents;
	(void)data;
	while ((n = read(fd, buf, sizeof buf)) > 0)
		for (ssize_t i = 0; i < n; i++)
			for (int j = 0; j < nsigs; j++)
				if (sigs[j].sig == buf[i])
					sigs[j].fn(buf[i]);
}

int loop_init(void)
{
	if (pipe(sigfd) < 0)
		return -1;
	for (int i = 0; i < 2; i++) {
		fcntl(sigfd[i], F_SETFL, O_NONBLOCK);
		fcntl(sigfd[i], F_SETFD, FD_CLOEXEC);
	}
	loop_watch(sigfd[0], LOOP_READ, readsignals, NULL);
	return 0;
}

void loop_signal(int sig, void (*fn)(int))
{
	struct sigaction sa;
	if (nsigs == (int)LENGTH(sigs))
		return;
	sigs[nsigs].sig = sig;
	sigs[nsigs++].fn = fn;
	memset(&sa, 0, sizeof sa);
	sa.sa_handler = onsignal;
	sa.sa_flags = SA_RESTART;
	sigemptyset(&sa.sa_mask);
	sigaction(sig, &sa, NULL);
}

void loop_quit(int code)
{
	quitting = 1;
	exitcode = code;
}

/* fire timers that were due when we started, so new 0ms timers wait a turn */
static void runtimers(void)
{
	double now = loop_now();
	for (;;) {
		int first = -1;
		for (int i = 0; i < ntimers; i++)
			if (timers[i].when <= now && (first < 0 || timers[i].when < timers[first].when))
				first = i;
		if (first < 0 || quitting)
			return;
		Timer t = timers[first];
		if (t.repeat > 0)
			timers[first].when = now + t.repeat;
		else
			timers[first] = timers[--ntimers];
		t.fn(t.data);
	}
}

static int timeout(void)
{
	if (!ntimers)
		return -1;
	double next = timers[0].when;
	for (int i = 1; i < ntimers; i++)
		if (timers[i].when < next)
			next = timers[i].when;
	double ms = next - loop_now();
	return ms <= 0 ? 0 : (int)ms + 1;
}

int loop_run(void (*idle)(void))
{
	struct pollfd *fds = NULL;
	int cap = 0;
	while (!quitting) {
		runtimers();
		if (!quitting && idle)
			idle();
		if (quitting)
			break;
		int n = nwatches;
		if (n > cap)
			fds = xrealloc(fds, (cap = n) * sizeof *fds);
		for (int i = 0; i < n; i++) {
			fds[i].fd = watches[i].fd;
			fds[i].events = (watches[i].events & LOOP_READ ? POLLIN : 0) |
			                (watches[i].events & LOOP_WRITE ? POLLOUT : 0);
			fds[i].revents = 0;
		}
		if (poll(fds, n, timeout()) < 0) {
			if (errno == EINTR)
				continue;
			loop_quit(1);
			break;
		}
		for (int i = 0; i < n && !quitting; i++) {
			int r = fds[i].revents;
			if (!r)
				continue;
			int rev = (r & (POLLIN | POLLHUP) ? LOOP_READ : 0) |
			          (r & POLLOUT ? LOOP_WRITE : 0) |
			          (r & (POLLERR | POLLNVAL) ? LOOP_ERROR : 0);
			for (int j = 0; j < nwatches; j++) {
				if (watches[j].fd == fds[i].fd) {
					Watch w = watches[j];
					w.fn(w.fd, rev, w.data);
					break;
				}
			}
			if (r & POLLNVAL)
				loop_unwatch(fds[i].fd);
		}
	}
	free(fds);
	return exitcode;
}
