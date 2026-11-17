/* child processes: fork/exec in a new session, pipes read through the event loop */
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

#include "sclop.h"

#define GRACE 200 /* ms to wait for output pipes after the child exits */

struct Proc {
	pid_t pid;
	int in, out, err;
	char *wbuf;
	size_t wlen, woff;
	int closein; /* close stdin once wbuf is written */
	int exited, code, sig;
	int grace;
	ProcOpts o;
	Proc *next;
};

static Proc *procs;

static void unlinkproc(Proc *p)
{
	for (Proc **pp = &procs; *pp; pp = &(*pp)->next) {
		if (*pp == p) {
			*pp = p->next;
			return;
		}
	}
}

static void closefd(int *fd)
{
	if (*fd >= 0) {
		loop_unwatch(*fd);
		close(*fd);
		*fd = -1;
	}
}

/* the exit callback runs once the child is gone and its output is read */
static void finish(Proc *p)
{
	if (!p->exited || p->out >= 0 || p->err >= 0)
		return;
	if (p->grace)
		loop_timer_stop(p->grace);
	closefd(&p->in);
	unlinkproc(p);
	if (p->o.exit)
		p->o.exit(p, p->code, p->sig, p->o.data);
	free(p->wbuf);
	free(p);
}

static void onread(int fd, int revents, void *data)
{
	Proc *p = data;
	char buf[65536];
	ssize_t n = read(fd, buf, sizeof buf);
	(void)revents;
	if (n > 0) {
		if (p->o.out)
			p->o.out(p, fd == p->out ? 1 : 2, buf, n, p->o.data);
		return;
	}
	if (n < 0 && (errno == EAGAIN || errno == EINTR))
		return;
	closefd(fd == p->out ? &p->out : &p->err);
	finish(p);
}

static void onwrite(int fd, int revents, void *data)
{
	Proc *p = data;
	(void)revents;
	while (p->woff < p->wlen) {
		ssize_t n = write(fd, p->wbuf + p->woff, p->wlen - p->woff);
		if (n < 0 && errno == EINTR)
			continue;
		if (n < 0 && errno == EAGAIN)
			return;
		if (n < 0) { /* the child closed its stdin */
			p->closein = 1;
			break;
		}
		p->woff += n;
	}
	p->wlen = p->woff = 0;
	loop_unwatch(fd);
	if (p->closein)
		closefd(&p->in);
}

static void graceful(void *data)
{
	Proc *p = data;
	p->grace = 0;
	closefd(&p->out);
	closefd(&p->err);
	finish(p);
}

static void reap(int sig)
{
	(void)sig;
	for (Proc *p = procs, *next; p; p = next) {
		int st = 0;
		pid_t r = 0;
		next = p->next;
		if (p->exited || (r = waitpid(p->pid, &st, WNOHANG)) == 0 || (r < 0 && errno != ECHILD))
			continue;
		p->exited = 1;
		p->code = r > 0 && WIFEXITED(st) ? WEXITSTATUS(st) : -1;
		p->sig = r > 0 && WIFSIGNALED(st) ? WTERMSIG(st) : 0;
		if (p->out >= 0 || p->err >= 0) /* a background child may hold the pipes open */
			p->grace = loop_timer(GRACE, 0, graceful, p);
		else
			finish(p);
	}
}

static void nonblock(int fd)
{
	fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK);
	fcntl(fd, F_SETFD, FD_CLOEXEC);
}

Proc *proc_spawn(const ProcOpts *o)
{
	static int once;
	int in[2] = { -1, -1 }, out[2] = { -1, -1 }, err[2] = { -1, -1 };
	Proc *p;
	pid_t pid;

	if (!once) {
		once = 1;
		loop_signal(SIGCHLD, reap);
	}
	if ((o->keep_stdin && pipe(in) < 0) || pipe(out) < 0 || (!o->merge && pipe(err) < 0) ||
	    !(p = calloc(1, sizeof *p)))
		goto fail;
	long max = sysconf(_SC_OPEN_MAX);
	if (max <= 0 || max > 4096)
		max = 4096;
	if ((pid = fork()) < 0) {
		free(p);
		goto fail;
	}
	if (pid == 0) {
		int null = open("/dev/null", O_RDWR);
		const char *what = o->argv[0];
		setsid();
		dup2(o->keep_stdin ? in[0] : null, 0);
		dup2(out[1], 1);
		dup2(o->merge ? out[1] : err[1], 2);
		for (int fd = 3; fd < max; fd++)
			close(fd);
		signal(SIGPIPE, SIG_DFL);
		if (!o->cwd || chdir(what = o->cwd) == 0)
			execvp(what = o->argv[0], o->argv);
		const char *msg = strerror(errno);
		if (write(2, what, strlen(what)) < 0 || write(2, ": ", 2) < 0 ||
		    write(2, msg, strlen(msg)) < 0 || write(2, "\n", 1) < 0) {
			/* nothing left to tell */
		}
		_exit(127);
	}
	if (in[0] >= 0)
		close(in[0]);
	close(out[1]);
	if (err[1] >= 0)
		close(err[1]);
	p->pid = pid;
	p->in = in[1];
	p->out = out[0];
	p->err = err[0];
	p->o = *o;
	p->next = procs;
	procs = p;
	nonblock(p->out);
	loop_watch(p->out, LOOP_READ, onread, p);
	if (p->err >= 0) {
		nonblock(p->err);
		loop_watch(p->err, LOOP_READ, onread, p);
	}
	if (p->in >= 0)
		nonblock(p->in);
	return p;
fail:
	for (int i = 0; i < 2; i++) {
		if (in[i] >= 0)
			close(in[i]);
		if (out[i] >= 0)
			close(out[i]);
		if (err[i] >= 0)
			close(err[i]);
	}
	return NULL;
}

void proc_write(Proc *p, const char *buf, size_t len)
{
	char *nb;
	if (p->in < 0 || !len || !(nb = realloc(p->wbuf, p->wlen + len)))
		return;
	p->wbuf = nb;
	memcpy(p->wbuf + p->wlen, buf, len);
	p->wlen += len;
	loop_watch(p->in, LOOP_WRITE, onwrite, p);
}

void proc_close(Proc *p)
{
	if (p->wlen > p->woff)
		p->closein = 1;
	else
		closefd(&p->in);
}

void proc_kill(Proc *p, int sig)
{
	if (!p->exited)
		kill(-p->pid, sig);
}

void proc_killall(void)
{
	for (Proc *p = procs; p; p = p->next)
		proc_kill(p, SIGTERM);
}
