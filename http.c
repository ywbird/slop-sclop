/* HTTP through libcurl's multi socket interface, driven by the event loop */
#include <stdlib.h>
#include <string.h>

#include <curl/curl.h>

#include "sclop.h"

struct Http {
	CURL *easy;
	struct curl_slist *headers;
	HttpOpts o;
	int cancelled;
	char err[CURL_ERROR_SIZE];
	Http *next;
};

static CURLM *multi;
static Http *reqs;
static int curltimer, reaptimer;

static void unlinkreq(Http *h)
{
	for (Http **p = &reqs; *p; p = &(*p)->next) {
		if (*p == h) {
			*p = h->next;
			return;
		}
	}
}

static void destroy(Http *h)
{
	curl_multi_remove_handle(multi, h->easy);
	curl_easy_cleanup(h->easy);
	curl_slist_free_all(h->headers);
	free(h);
}

static void check(void)
{
	CURLMsg *m;
	int left;
	while ((m = curl_multi_info_read(multi, &left))) {
		if (m->msg != CURLMSG_DONE)
			continue;
		CURL *easy = m->easy_handle;
		CURLcode res = m->data.result;
		char *priv;
		long status = 0;
		curl_easy_getinfo(easy, CURLINFO_PRIVATE, &priv);
		curl_easy_getinfo(easy, CURLINFO_RESPONSE_CODE, &status);
		Http *h = (Http *)priv;
		unlinkreq(h);
		curl_multi_remove_handle(multi, easy);
		if (!h->cancelled && h->o.done)
			h->o.done(h, status, res == CURLE_OK ? NULL : h->err[0] ? h->err : curl_easy_strerror(res),
			          h->o.ud);
		curl_easy_cleanup(easy);
		curl_slist_free_all(h->headers);
		free(h);
	}
}

static void onsock(int fd, int revents, void *data)
{
	int flags = 0, running;
	(void)data;
	if (revents & LOOP_READ)
		flags |= CURL_CSELECT_IN;
	if (revents & LOOP_WRITE)
		flags |= CURL_CSELECT_OUT;
	if (revents & LOOP_ERROR)
		flags |= CURL_CSELECT_ERR;
	curl_multi_socket_action(multi, fd, flags, &running);
	check();
}

static int sockcb(CURL *e, curl_socket_t s, int what, void *u, void *sp)
{
	(void)e;
	(void)u;
	(void)sp;
	if (what == CURL_POLL_REMOVE)
		loop_unwatch(s);
	else
		loop_watch(s, (what & CURL_POLL_IN ? LOOP_READ : 0) | (what & CURL_POLL_OUT ? LOOP_WRITE : 0),
		           onsock, NULL);
	return 0;
}

static void ontimeout(void *data)
{
	int running;
	(void)data;
	curltimer = 0;
	curl_multi_socket_action(multi, CURL_SOCKET_TIMEOUT, 0, &running);
	check();
}

static int timercb(CURLM *m, long ms, void *u)
{
	(void)m;
	(void)u;
	if (curltimer)
		loop_timer_stop(curltimer);
	curltimer = ms >= 0 ? loop_timer(ms, 0, ontimeout, NULL) : 0;
	return 0;
}

static size_t onwrite(char *p, size_t size, size_t n, void *u)
{
	Http *h = u;
	if (h->cancelled)
		return 0;
	if (h->o.data)
		h->o.data(h, p, size * n, h->o.ud);
	return size * n;
}

/* cancelled transfers are removed from a timer: curl forbids it inside its callbacks */
static void reap(void *data)
{
	(void)data;
	reaptimer = 0;
	for (Http *h = reqs, *next; h; h = next) {
		next = h->next;
		if (h->cancelled) {
			unlinkreq(h);
			destroy(h);
		}
	}
}

void http_cancel(Http *h)
{
	h->cancelled = 1;
	if (!reaptimer)
		reaptimer = loop_timer(0, 0, reap, NULL);
}

Http *http_request(const HttpOpts *o)
{
	Http *h = calloc(1, sizeof *h);
	if (!h || !(h->easy = curl_easy_init())) {
		free(h);
		return NULL;
	}
	CURL *e = h->easy;
	h->o = *o;
	curl_easy_setopt(e, CURLOPT_URL, o->url);
	curl_easy_setopt(e, CURLOPT_PRIVATE, h);
	curl_easy_setopt(e, CURLOPT_WRITEFUNCTION, onwrite);
	curl_easy_setopt(e, CURLOPT_WRITEDATA, h);
	curl_easy_setopt(e, CURLOPT_ERRORBUFFER, h->err);
	curl_easy_setopt(e, CURLOPT_NOSIGNAL, 1L);
	curl_easy_setopt(e, CURLOPT_FOLLOWLOCATION, 1L);
	curl_easy_setopt(e, CURLOPT_MAXREDIRS, 10L);
	curl_easy_setopt(e, CURLOPT_ACCEPT_ENCODING, "");
	curl_easy_setopt(e, CURLOPT_USERAGENT, "sclop/" VERSION);
	curl_easy_setopt(e, CURLOPT_CONNECTTIMEOUT_MS, 30000L);
	if (o->timeout > 0)
		curl_easy_setopt(e, CURLOPT_TIMEOUT_MS, o->timeout);
	if (o->body) {
		curl_easy_setopt(e, CURLOPT_POSTFIELDSIZE_LARGE, (curl_off_t)o->bodylen);
		curl_easy_setopt(e, CURLOPT_COPYPOSTFIELDS, o->body);
		h->headers = curl_slist_append(h->headers, "Expect:");
	}
	if (o->method)
		curl_easy_setopt(e, CURLOPT_CUSTOMREQUEST, o->method);
	for (const char *const *hd = o->headers; hd && *hd; hd++)
		h->headers = curl_slist_append(h->headers, *hd);
	if (h->headers)
		curl_easy_setopt(e, CURLOPT_HTTPHEADER, h->headers);
	h->next = reqs;
	reqs = h;
	if (curl_multi_add_handle(multi, e) != CURLM_OK) {
		unlinkreq(h);
		curl_easy_cleanup(e);
		curl_slist_free_all(h->headers);
		free(h);
		return NULL;
	}
	return h;
}

int http_init(void)
{
	if (curl_global_init(CURL_GLOBAL_DEFAULT) || !(multi = curl_multi_init()))
		return -1;
	curl_multi_setopt(multi, CURLMOPT_SOCKETFUNCTION, sockcb);
	curl_multi_setopt(multi, CURLMOPT_TIMERFUNCTION, timercb);
	return 0;
}

void http_cleanup(void)
{
	while (reqs) {
		Http *h = reqs;
		reqs = h->next;
		destroy(h);
	}
	curl_multi_cleanup(multi);
	curl_global_cleanup();
}
